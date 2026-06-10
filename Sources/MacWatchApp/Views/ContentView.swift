import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacWatch")
                .font(.largeTitle)
                .bold()

            Text("Engineering skeleton ready")
                .font(.headline)

            Text("No samples yet")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 240, alignment: .topLeading)
        .padding(24)
    }
}
