#!/bin/bash
set -euo pipefail
# Copy sibling packages off NFS to avoid GRDB repository/fixture ownership errors.
apt-get update -qq
apt-get install -y -qq libsqlite3-dev
mkdir -p /work/Packages
for pkg in SwarmGateKit SwarmGateStore; do
  mkdir -p "/work/Packages/$pkg"
  cp -r "/src/Packages/$pkg/Sources" "/src/Packages/$pkg/Tests" "/src/Packages/$pkg/Package.swift" "/work/Packages/$pkg/"
done
cp /src/Packages/SwarmGateStore/Package.resolved /work/Packages/SwarmGateStore/
cd /work
swift test --package-path Packages/SwarmGateKit --scratch-path /work/engine-build
swift test --package-path Packages/SwarmGateStore --scratch-path /work/store-build
