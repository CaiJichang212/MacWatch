import SwiftUI

struct CompatibilityView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let compact: Bool

    var body: some View {
        let localizer = runtime.localizer
        let snapshot = CompatibilitySnapshot(liveState: runtime.liveState, localizer: localizer)

        if compact {
            content(snapshot: snapshot, localizer: localizer)
        } else {
            content(snapshot: snapshot, localizer: localizer)
                .navigationTitle(localizer.string("compatibility.title"))
        }
    }

    private func content(snapshot: CompatibilitySnapshot, localizer: AppLocalizer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if compact == false {
                    Text(localizer.string("compatibility.title"))
                        .font(.title2.weight(.semibold))
                }

                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.title)
                                .font(.headline)
                            Spacer()
                            Text(row.statusText)
                                .foregroundStyle(row.statusText == localizer.string("status.valid") ? .primary : .secondary)
                        }

                        Text(localizer.string("compatibility.source", row.sourceText))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let reasonText = row.reasonText {
                            Text(localizer.string("compatibility.reason", reasonText))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let rawKey = row.rawKey {
                            Text(localizer.string("compatibility.rawKey", rawKey))
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
    }
}
