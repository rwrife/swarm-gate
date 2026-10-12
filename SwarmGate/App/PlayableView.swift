import SwiftUI
import SpriteKit
import SwarmGateKit
import SwarmGateStore

struct PlayableView: View {
    @Bindable var session: GameSession
    let reduceMotion: Bool
    let haptics: Bool
    let onDismiss: @MainActor @Sendable () -> Void
    @Environment(\.scenePhase) private var phase

    @State private var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.07, blue: 0.12).ignoresSafeArea()
            if session.finished {
                RunSummaryView(session: session, onDismiss: onDismiss)
            } else {
                VStack(spacing: 0) {
                    hud
                    DefenseWorkspaceView(battlefield: battlefield, deck: controlDeck)
                }
            }
        }
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .onReceive(timer) { _ in
            if phase == .active { session.step(haptics: haptics) }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase != .active { session.heldLane = nil }
        }
    }

    private var hud: some View {
        HStack {
            Label("HP \(session.simulation.health)", systemImage: "heart.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("hud.health")
            Spacer()
            Text("Wave \(session.simulation.tick / session.simulation.rules.waveInterval + 1)")
                .font(.headline)
                .foregroundStyle(.white)
                .accessibilityIdentifier("hud.wave")
            Spacer()
            Label("Power \(session.simulation.firepower)", systemImage: "bolt.fill")
                .foregroundStyle(.yellow)
                .accessibilityIdentifier("hud.power")
            Spacer()
            Label("Bombs \(session.simulation.bombs)", systemImage: "burst.fill")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("hud.bombs")
        }
        .font(.subheadline.bold())
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var battlefield: some View {
        GeometryReader { geometry in
            SpriteView(scene: session.renderer.scene)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let lane = min(session.simulation.rules.laneCount - 1,
                            max(0, Int(value.location.x / max(1, geometry.size.width)
                                * CGFloat(session.simulation.rules.laneCount))))
                        session.heldLane = lane
                    }
                    .onEnded { value in
                        if value.translation.height < -45 {
                            session.input(.bomb)
                        } else {
                            // A short tap still emits a shot before the next tick.
                            if let lane = session.heldLane { session.input(.move(lane: lane)) }
                            session.input(.fire)
                        }
                        session.heldLane = nil
                    })
                .accessibilityLabel("Battlefield. Drag to aim and fire; swipe up to bomb.")
                .accessibilityIdentifier("battlefield")
        }
        .padding(8)
    }

    private var controlDeck: some View {
        VStack(spacing: 8) {
            pickupsDeck
            oneThumbDeck
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var pickupsDeck: some View {
        let inZone = session.simulation.pickups.filter(\.inZone)
        return Group {
            if !inZone.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Incoming Gate Drop (Explicit Opt-In Required)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(inZone, id: \.id) { pickup in
                            pickupButton(pickup)
                        }
                    }
                }
            }
        }
    }

    private func pickupButton(_ pickup: Pickup) -> some View {
        let label: String
        switch pickup.kind {
        case .buff: label = "Firepower Buff"
        case .weapon: label = "Weapon Ammo"
        case .bomb: label = "Bomb"
        case .powerDown: label = "Power-Down Penalty"
        }
        return HStack(spacing: 4) {
            Button {
                session.input(.acceptPickup(id: pickup.id))
            } label: {
                Text(pickup.kind == .powerDown ? "Accept Penalty" : "Accept Buff")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(pickup.kind == .powerDown ? .red : .yellow)
            .accessibilityLabel("Accept \(label)")
            .accessibilityIdentifier("pickup.accept.\(pickup.id)")

            Button {
                session.input(.ignorePickup(id: pickup.id))
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Ignore \(label)")
            .accessibilityIdentifier("pickup.ignore.\(pickup.id)")
        }
    }

    private var oneThumbDeck: some View {
        HStack(spacing: 12) {
            Button {
                session.input(.bomb)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "burst.fill")
                    Text("Swipe Bomb")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(session.simulation.bombs == 0)
            .accessibilityIdentifier("control.bomb")
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { _ in
                        session.input(.bomb)
                    }
            )

            Button {
                session.finish()
            } label: {
                Text("End Run")
                    .font(.caption.bold())
                    .frame(maxWidth: 90, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier("control.surrender")
        }
    }
}

struct RunSummaryView: View {
    let session: GameSession
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(session.simulation.isEnded ? "Run Complete" : "Run Stopped — Incomplete")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("summary.title")
                    .accessibilityAddTraits(.isHeader)

                metricsGrid
                economyAudit
                personalBestsComparison
                if !session.simulation.isEnded {
                    Text("Personal-best eligibility: Unknown (run stopped before completion)")
                        .font(.caption).foregroundStyle(.orange)
                }

                if let summary = session.record?.summary {
                    Text(pbStatus(summary))
                        .font(.caption).foregroundStyle(.green)
                }
                Text("Boss encounters: \(session.count(.bossSpawn))")
                    .foregroundStyle(.white)
                Text("Seed: \(session.simulation.ledger.seed)")
                    .font(.caption).foregroundStyle(.secondary)

                if let err = session.saveError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Return to Menu")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("summary.dismiss")
            }
            .padding()
        }
    }

    private func pbStatus(_ summary: RunSummary) -> String {
        guard session.saved else { return "PB: Unknown (run not persisted)" }
        guard let previous = session.previousBests else { return "PB: Unknown (records unavailable)" }
        let wave = previous.bestWave.map { summary.wave > $0 ? "New best wave" : "No new best wave" } ?? "First recorded wave"
        let score = previous.bestScore.map { summary.score > $0 ? "New best score" : "No new best score" } ?? "First recorded score"
        return "PB: \(wave); \(score)"
    }

    private var metricsGrid: some View {
        VStack(spacing: 12) {
            let lastTick = session.simulation.tick
            let wave = lastTick / session.simulation.rules.waveInterval + 1
            let score = session.count(.kill) + session.count(.bombKill)
            let bosses = session.simulation.ledger.events.filter { event in
                if event.kind == .kill {
                    let bossIDs = Set(session.simulation.ledger.events.filter { $0.kind == .bossSpawn }.map(\.id))
                    return bossIDs.contains(event.id)
                }
                return false
            }.count

            HStack {
                summaryTile(title: "Waves", value: "\(wave)", id: "summary.waves")
                summaryTile(title: "Score", value: "\(score)", id: "summary.score")
            }
            HStack {
                summaryTile(title: "Peak Firepower", value: "\(session.peakFirepower)", id: "summary.firepower")
                summaryTile(title: "Bosses Slain", value: "\(bosses)", id: "summary.bosses")
            }
        }
    }

    private var economyAudit: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fairness & Pickups Audit")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Power-downs applied only when explicitly accepted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                auditRow(label: "Buffs Taken", count: session.pickupsTaken(.buff))
                Spacer()
                auditRow(label: "Penalties Taken", count: session.pickupsTaken(.powerDown))
                Spacer()
                auditRow(label: "Bombs Used", count: session.count(.bomb))
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var personalBestsComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal Best Status")
                .font(.headline)
                .foregroundStyle(.white)
            let bestWave = session.previousBests?.bestWave
            let bestScore = session.previousBests?.bestScore
            HStack {
                VStack(alignment: .leading) {
                    Text("Previous Best Wave").font(.caption).foregroundStyle(.secondary)
                    Text(bestWave.map(String.init) ?? "Unknown (None)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("Previous Best Score").font(.caption).foregroundStyle(.secondary)
                    Text(bestScore.map(String.init) ?? "Unknown (None)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryTile(title: String, value: String, id: String) -> some View {
        VStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier(id)
    }

    private func auditRow(label: String, count: Int) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(count)").font(.body.bold()).foregroundStyle(.white)
        }
    }
}
