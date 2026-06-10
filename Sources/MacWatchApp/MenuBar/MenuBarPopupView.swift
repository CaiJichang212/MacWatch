import MacWatchCore
import SwiftUI

struct MenuBarPopupRowModel: Identifiable, Equatable {
    let id: TemperatureDomain
    let title: String
    let sourceText: String
    let updatedAtText: String
    let valueText: String
    let statusText: String
    let isPrimaryValue: Bool

    init(row: TemperatureOverviewSnapshot.Row) {
        id = row.domain
        title = row.title
        sourceText = "Source: \(row.sourceText)"
        updatedAtText = "Updated: \(row.updatedAtText)"
        valueText = row.valueText
        statusText = row.statusText
        isPrimaryValue = row.statusText == "Valid"
    }
}

struct MenuBarPopupView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let openDashboard: () -> Void
    let openCompatibility: () -> Void
    let openSettings: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        let snapshot = TemperatureOverviewSnapshot(
            liveState: runtime.liveState,
            settings: runtime.settings
        )
        let rows = snapshot.rows.map(MenuBarPopupRowModel.init)

        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.hottestValueText)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Current hottest")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(rows) { row in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.subheadline.weight(.medium))
                        Text(row.sourceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.updatedAtText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.valueText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.isPrimaryValue ? .primary : .secondary)
                        Text(row.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("Dashboard", action: openDashboard)
                Button("Compatibility", action: openCompatibility)
                Spacer()
                Button("Settings", action: openSettings)
                Button("Quit", role: .destructive, action: quitApplication)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 360)
    }
}
