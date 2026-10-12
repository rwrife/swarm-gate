import SwiftUI
import SwarmGateStore

struct DefenseHomeView: View {
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("haptics") private var haptics = true
    @FocusState private var seedFocused: Bool
    private var settings: Binding<GameSettings> {
        Binding(get: { GameSettings(reduceMotion: reduceMotion, hapticsEnabled: haptics) },
                set: { reduceMotion = $0.reduceMotion; haptics = $0.hapticsEnabled })
    }
    @State private var showSettings = false
    @State private var session: GameSession?
    @State private var customSeedText = ""
    @State private var personalBests: PersonalBests?
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.08, blue: 0.12).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        header
                        bestsCard
                        modeButtons
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings.button")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            .fullScreenCover(item: $session) { currentSession in
                PlayableView(session: currentSession,
                             reduceMotion: reduceMotion || systemReduceMotion,
                             haptics: haptics) {
                    session = nil
                    loadBests()
                }
            }
            .onAppear(perform: loadBests)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Swarm Gate")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("Local-first iPhone lane defense")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Offline original IP • Zero network")
                .font(.caption2)
                .foregroundStyle(.gray)
        }
    }

    private var bestsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Career Records")
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                bestMetric(title: "Best Wave", value: personalBests?.bestWave)
                Spacer()
                bestMetric(title: "Best Score", value: personalBests?.bestScore)
                Spacer()
                bestMetric(title: "Bosses", value: personalBests?.mostBossesSlain)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Career records: \(bestVoiceOver)")
    }

    private func bestMetric(title: String, value: Int?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "Unknown")
                .font(.title3.bold())
                .foregroundStyle(.white)
        }
    }

    private var bestVoiceOver: String {
        guard let p = personalBests else { return "No records logged yet" }
        let wave = p.bestWave.map { "\($0)" } ?? "unknown"
        let score = p.bestScore.map { "\($0)" } ?? "unknown"
        return "Best wave \(wave), best score \(score)"
    }

    private var modeButtons: some View {
        VStack(spacing: 12) {
            Button {
                start(seed: UInt64(Date().timeIntervalSince1970 * 1000) & 0xffff_ffff, mode: .career)
            } label: {
                Label("Quick Seeded Run", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityIdentifier("mode.quick")

            Button {
                start(seed: 0xfeed_cafe, mode: .endless)
            } label: {
                Label("Endless Horde", systemImage: "infinity")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityIdentifier("mode.endless")

            VStack(spacing: 8) {
                HStack {
                    TextField("Enter custom seed (numeric)", text: $customSeedText)
                        .keyboardType(.numberPad)
                        .focused($seedFocused)
                        .onSubmit { seedFocused = false }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("seed.input")
                    Button("Play") {
                        seedFocused = false
                        guard !customSeedText.isEmpty,
                              customSeedText.utf8.allSatisfy({ (48...57).contains($0) }),
                              let parsed = UInt64(customSeedText) else {
                            errorMessage = "Enter a whole-number seed from 0 to 18446744073709551615."
                            return
                        }
                        errorMessage = nil
                        start(seed: parsed, mode: .career)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("seed.play")
                }
            }
            .padding(.top, 8)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("seed.error")
            }
        }
    }

    private func start(seed: UInt64, mode: RunMode) {
        session = GameSession(seed: seed, mode: mode)
    }

    private func loadBests() {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask, appropriateFor: nil, create: true)
            let path = folder.appendingPathComponent("swarm-gate.sqlite").path
            if FileManager.default.fileExists(atPath: path) {
                let store = try RunStore(path: path)
                personalBests = try store.personalBests()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension GameSession: Identifiable {}

struct SettingsView: View {
    @Binding var settings: GameSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    Toggle("Reduce Motion", isOn: $settings.reduceMotion)
                        .accessibilityIdentifier("settings.reducemotion")
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                        .accessibilityIdentifier("settings.haptics")
                }
                Section("Architecture") {
                    LabeledContent("Layout Seam", value: "DefenseWorkspaceLayout")
                    LabeledContent("Current Layout", value: "Portrait Compact (Single Window)")
                    LabeledContent("Dual-Screen Target", value: "iPhone Duo (Documented Seam)")
                    LabeledContent("Network Policy", value: "Strict Zero Network")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }
}
