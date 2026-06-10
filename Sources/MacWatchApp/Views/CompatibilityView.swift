import SwiftUI

struct CompatibilityView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let compact: Bool

    var body: some View {
        let snapshot = CompatibilitySnapshot(liveState: runtime.liveState)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if compact == false {
                    Text("Compatibility")
                        .font(.title2.weight(.semibold))
                }

                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.title)
                                .font(.headline)
                            Spacer()
                            Text(row.statusText)
                                .foregroundStyle(row.statusText == "Valid" ? .primary : .secondary)
                        }

                        Text("Source: \(row.sourceText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let reasonText = row.reasonText {
                            Text("Reason: \(reasonText)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let rawKey = row.rawKey {
                            Text("Raw Key: \(rawKey)")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(compact ? 0 : 24)
        }
        .navigationTitle("Compatibility")
    }
}
