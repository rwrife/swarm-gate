import SwiftUI

struct DefenseHomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Swarm Gate")
                .font(.largeTitle.bold())
            Text("The battlefield is under construction.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}