import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacWatch")
                .font(.largeTitle)
                .bold()

            Text("App name: MacWatch")
                .font(.headline)

            Text("Status: Engineering skeleton ready")

            Text("Temperature: No samples yet")
                .foregroundStyle(.secondary)

            Text("Stage 1 only validates the app shell, lifecycle entrypoints, and adapter boundary.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 420, minHeight: 240, alignment: .topLeading)
        .padding(24)
    }
}
