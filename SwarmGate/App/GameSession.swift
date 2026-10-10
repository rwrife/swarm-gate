import SwiftUI
import SpriteKit
import UIKit
import SwarmGateKit
import SwarmGateStore

@MainActor @Observable
final class GameSession {
    var simulation: Simulation
    let mode: RunMode
    let renderer = BattlefieldRenderer()
    var finished = false
    var saved = false
    var saveError: String?
    var record: RunRecord?
    var previousBests: PersonalBests?
    var heldLane: Int?
    let id = UUID().uuidString
    private var store: RunStore?

    init(seed: UInt64, mode: RunMode) {
        self.mode = mode
        simulation = Simulation(seed: RunSeed(seed), rules: .v3)
        renderer.render(simulation)
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            store = try RunStore(path: folder.appendingPathComponent("swarm-gate.sqlite").path)
            previousBests = try store?.personalBests()
        } catch {
            saveError = "Local records unavailable: \(error.localizedDescription)"
        }
    }

    func step(haptics: Bool) {
        guard !finished else { return }
        if let heldLane {
            simulation.queue(.move(lane: heldLane))
            simulation.queue(.fire)
        }
        let previousHealth = simulation.health
        simulation.step()
        renderer.render(simulation)
        if haptics && simulation.health < previousHealth {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if simulation.isEnded { finish() }
    }

    func input(_ action: InputAction) { simulation.queue(action) }

    func finish() {
        guard !finished else { return }
        heldLane = nil
        finished = true
        record = RunRecord(id: id, mode: mode, ledger: simulation.ledger,
                           waveInterval: simulation.rules.waveInterval)
        persist()
    }

    func persist() {
        guard !saved, let record else { return }
        do {
            guard let store else { return }
            try store.append(record)
            saved = true
            saveError = nil
        } catch {
            saveError = "Run not saved: \(error.localizedDescription)"
        }
    }

    var peakFirepower: Int {
        // Reconstruct from accepts/decay; the ledger stores pickup kind, not power.
        var power = 1
        var peak = 1
        for event in simulation.ledger.events {
            if event.kind == .pickupAccept {
                if event.value == PickupKind.buff.rawValue {
                    power = min(simulation.rules.maximumFirepower, power + 1)
                } else if event.value == PickupKind.powerDown.rawValue { power = 1 }
            } else if event.kind == .buffDecay { power = event.value }
            peak = max(peak, power)
        }
        return peak
    }

    func count(_ kind: LedgerEvent.Kind) -> Int {
        simulation.ledger.events.filter { $0.kind == kind }.count
    }

    func pickupsTaken(_ kind: PickupKind) -> Int {
        simulation.ledger.events.filter { $0.kind == .pickupAccept && $0.value == kind.rawValue }.count
    }
}

/// SpriteKit is a projection of fixed-tick snapshots, never a simulation clock.
/// Original geometric sprites share a small runtime atlas, with reusable nodes
/// for the large horde. No downloaded art, franchise characters, or gore.
@MainActor
final class BattlefieldRenderer {
    let scene = SKScene(size: CGSize(width: 320, height: 480))
    private let atlas: SKTextureAtlas
    private var active: [String: SKSpriteNode] = [:]
    private var pool: [SKSpriteNode] = []
    private let player = SKShapeNode(rectOf: CGSize(width: 30, height: 14), cornerRadius: 5)

    init() {
        let images: [String: Any] = ["shambler": Self.sprite(boss: false), "boss": Self.sprite(boss: true)]
        atlas = SKTextureAtlas(dictionary: images)
        pool = (0..<512).map { _ in SKSpriteNode() }
        scene.scaleMode = .resizeFill
        scene.backgroundColor = UIColor(red: 0.04, green: 0.09, blue: 0.15, alpha: 1)
        player.fillColor = .cyan
        player.strokeColor = .white
        player.zPosition = 2
        scene.addChild(player)
    }

    private static func sprite(boss: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            let cg = context.cgContext
            cg.setFillColor((boss ? UIColor.systemPurple : UIColor.systemGreen).cgColor)
            cg.fillEllipse(in: CGRect(x: 2, y: 2, width: 28, height: 28))
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(x: 7, y: 9, width: 6, height: 7))
            cg.fill(CGRect(x: 19, y: 9, width: 6, height: 7))
            cg.setFillColor(UIColor.darkGray.cgColor)
            cg.fill(CGRect(x: 9, y: 11, width: 3, height: 4))
            cg.fill(CGRect(x: 20, y: 11, width: 3, height: 4))
            cg.fill(CGRect(x: 10, y: 23, width: 12, height: 3))
        }
    }

    func render(_ sim: Simulation) {
        let width = scene.size.width
        let height = scene.size.height
        let laneWidth = width / CGFloat(sim.rules.laneCount)
        func position(lane: Int, distance: Int) -> CGPoint {
            CGPoint(x: (CGFloat(lane) + 0.5) * laneWidth,
                    y: 30 + (CGFloat(distance) / CGFloat(sim.rules.spawnDistance)) * max(1, height - 60))
        }
        var visible: Set<String> = []
        for zombie in sim.zombies {
            let key = "z\(zombie.id)"
            visible.insert(key)
            let node = node(for: key)
            node.texture = atlas.textureNamed(zombie.isBoss ? "boss" : "shambler")
            node.colorBlendFactor = 0
            node.size = CGSize(width: zombie.isBoss ? 38 : 24, height: zombie.isBoss ? 38 : 24)
            node.position = position(lane: zombie.lane, distance: zombie.distance)
        }
        for pickup in sim.pickups {
            let key = "p\(pickup.id)"
            visible.insert(key)
            let node = node(for: key)
            node.texture = nil
            node.color = pickup.kind == .powerDown ? .systemRed : .systemYellow
            node.colorBlendFactor = 1
            node.size = CGSize(width: 14, height: 14)
            node.position = position(lane: pickup.lane, distance: pickup.distance)
        }
        for key in active.keys.filter({ !visible.contains($0) }) {
            if let node = active.removeValue(forKey: key) {
                node.removeFromParent()
                pool.append(node)
            }
        }
        player.position = position(lane: sim.playerLane, distance: 0)
    }

    private func node(for key: String) -> SKSpriteNode {
        if let node = active[key] { return node }
        // ponytail: 512 warm nodes cover the current table; larger future tables
        // grow the pool on demand rather than silently dropping simulation entities.
        let node = pool.popLast() ?? SKSpriteNode()
        active[key] = node
        scene.addChild(node)
        return node
    }
}
