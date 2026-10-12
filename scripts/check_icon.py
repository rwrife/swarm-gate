#!/usr/bin/env python3
"""Fail closed unless the committed App Store icon is real edge-to-edge art.

Checks 1024x1024, opaque (no alpha channel), and that all four corners plus
top/bottom edge strips carry varied image content, so a baked white margin,
frame, or corner radius cannot pass. Pure stdlib PNG decode (non-interlaced,
8-bit RGB/RGBA/gray) because CI lanes cannot rely on Pillow.
"""
import struct
import sys
import zlib
from pathlib import Path


def decode_png(data: bytes):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    idat = bytearray()
    size = channels = None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, compression, filter_mode, interlace = \
                struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or interlace != 0 or compression != 0 or filter_mode != 0:
                raise ValueError(f"unsupported PNG: depth={depth} interlace={interlace}")
            channels = {0: 1, 2: 3, 6: 4}.get(color)
            if channels is None:
                raise ValueError(f"unsupported PNG color type {color}")
            if color == 4:
                raise ValueError("gray-alpha PNG has alpha")
            size = (width, height)
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
        pos += 12 + length
    if size is None or channels is None:
        raise ValueError("PNG missing IHDR")
    width, height = size
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    expected = (stride + 1) * height
    if len(raw) != expected:
        raise ValueError(f"IDAT size {len(raw)} != expected {expected}")

    def recon_line(filter_type, line, prev):
        out = bytearray(stride)
        for x in range(stride):
            raw_byte = line[x]
            left = out[x - channels] if x >= channels else 0
            up = prev[x]
            upper_left = prev[x - channels] if x >= channels else 0
            if filter_type == 0:
                value = raw_byte
            elif filter_type == 1:
                value = raw_byte + left
            elif filter_type == 2:
                value = raw_byte + up
            elif filter_type == 3:
                value = raw_byte + ((left + up) >> 1)
            elif filter_type == 4:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                predict = left if (pa <= pb and pa <= pc) else (up if pb <= pc else upper_left)
                value = raw_byte + predict
            else:
                raise ValueError(f"bad filter {filter_type}")
            out[x] = value & 0xFF
        return out

    pixels = bytearray()
    prev = bytes(stride)
    for y in range(height):
        start = y * (stride + 1)
        row = recon_line(raw[start], raw[start + 1:start + stride + 1], prev)
        pixels += row
        prev = bytes(row)
    return width, height, channels, bytes(pixels)


def pixel(pixels, stride, channels, x, y):
    o = y * stride + x * channels
    return tuple(pixels[o:o + channels])


def verify(path: Path) -> None:
    data = path.read_bytes()
    width, height, channels, pixels = decode_png(data)
    if (width, height) != (1024, 1024):
        raise ValueError(f"icon must be 1024x1024, got {width}x{height}")
    if channels == 4:
        rgba_min = min(pixels[i] for i in range(3, len(pixels), 4))
        if rgba_min < 255:
            raise ValueError("icon contains transparency")
    stride = width * channels
    corners = [pixel(pixels, stride, channels, x, y)
               for x, y in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]]
    if all(sum(c) > 720 for c in corners):
        raise ValueError(f"near-white corners suggest baked margin/radius: {corners}")
    if len(set(corners)) == 1:
        raise ValueError(f"identical corners suggest baked frame: {corners}")
    strip = [pixel(pixels, stride, channels, x, 0) for x in range(0, width, 64)] + \
            [pixel(pixels, stride, channels, x, height - 1) for x in range(0, width, 64)]
    if len(set(strip)) < 8:
        raise ValueError("top/bottom edge strips are near-uniform; art is not edge-to-edge")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1] if len(sys.argv) > 1 else "AppStore/icon.png").resolve())
    except Exception as exc:  # noqa: BLE001 - surface any image/IO failure as gate failure
        print(f"Icon FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
    print("Icon PASS: 1024x1024 opaque edge-to-edge, no alpha, no baked margin/frame")
