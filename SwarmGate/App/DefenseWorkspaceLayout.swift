import SwiftUI

/// The only view that chooses battlefield/control-deck placement. Surface changes
/// must preserve the existing session, selected lane and ordered tick inputs.
struct DefenseWorkspaceView<Battlefield: View, Deck: View>: View {
    let battlefield: Battlefield
    let deck: Deck

    var body: some View {
        switch DefenseWorkspaceLayout.current {
        case .portraitCompact, .dualSurface:
            VStack(spacing: 0) {
                battlefield
                deck
            }
        }
    }
}

/// Workspace layout contract for current single-window and future iPhone Duo target.
///
/// Current execution is a single portrait iPhone window hosting both the
/// battlefield and the control deck (`portraitCompact`).
///
/// iPhone Duo split target notes:
/// - One surface renders the live SpriteKit battlefield (`battlefieldSurface`).
/// - The adjacent surface renders the persistent control deck (`controlDeckSurface`).
/// - State continuity is driven by the immutable `Simulation` tick, not UI lifecycle.
/// - Neither mode depends on private or unavailable fold SDK APIs.
public enum DefenseWorkspaceLayout: Sendable, Equatable {
    case portraitCompact
    case dualSurface(battlefieldSurface: SurfaceRole, controlDeckSurface: SurfaceRole)

    public enum SurfaceRole: Sendable, Equatable {
        case primary
        case secondary
    }

    /// Single compact iPhone layout active today.
    public static var current: DefenseWorkspaceLayout { .portraitCompact }
}

public struct GameSettings: Codable, Equatable, Sendable {
    public var reduceMotion: Bool
    public var hapticsEnabled: Bool

    public init(reduceMotion: Bool = false, hapticsEnabled: Bool = true) {
        self.reduceMotion = reduceMotion
        self.hapticsEnabled = hapticsEnabled
    }
}
