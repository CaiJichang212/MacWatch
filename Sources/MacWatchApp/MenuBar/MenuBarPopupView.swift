import MacWatchCore
import SwiftUI

struct MenuBarPopupRowModel: Identifiable, Equatable {
    let id: TemperatureDomain
    let title: String
    let valueText: String?
    let averageValueText: String?
    let statusText: String?
    let reasonText: String?

    init(row: TemperatureOverviewSnapshot.Row) {
        id = row.domain
        title = row.title
        valueText = row.primaryValueText
        averageValueText = row.averageValueText
        statusText = row.abnormalStatusText
        reasonText = row.reasonText
    }
}

struct MenuBarPopupView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime

    let openDashboard: () -> Void
    let openCompatibility: () -> Void
    let openSettings: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        let localizer = runtime.localizer
        let snapshot = TemperatureOverviewSnapshot(
            liveState: runtime.liveState,
            settings: runtime.settings,
            localizer: localizer
        )
        let rows = snapshot.rows.map(MenuBarPopupRowModel.init)
        let updatedAtText = TemperatureTimestampFormatter.shortTimeText(snapshot.updatedAt, locale: localizer.locale)

        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.hottestValueText)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            HStack(spacing: 10) {
                Text(localizer.string("popup.currentHottest"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(localizer.string("popup.updated", updatedAtText))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if let valueText = row.valueText {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(valueText)
                                    .font(.subheadline.weight(.semibold))
                                if let averageValueText = row.averageValueText {
                                    Text(localizer.string("popup.average", averageValueText))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if let statusText = row.statusText {
                            Text(statusText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let reasonText = row.reasonText {
                        Text(reasonText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button(localizer.string("popup.dashboard"), action: openDashboard)
                Button(localizer.string("popup.compatibility"), action: openCompatibility)
                Spacer()
                Button(localizer.string("popup.settings"), action: openSettings)
                Button(localizer.string("popup.quit"), role: .destructive, action: quitApplication)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            AcceptanceCoordinator.shared.recordViewAppeared(.popup)
        }
    }
}
