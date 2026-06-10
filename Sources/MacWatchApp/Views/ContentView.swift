import MacWatchCore
import SwiftUI

struct ContentView: View {
    @State private var selection: MainWindowRoute? = .dashboard
    private let windowCommandCenter = WindowCommandCenter.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Overview") {
                    Label("Dashboard", systemImage: "rectangle.grid.2x2")
                        .tag(MainWindowRoute.dashboard)
                    Label("Compatibility", systemImage: "checklist")
                        .tag(MainWindowRoute.compatibility)
                }

                Section("Metrics") {
                    ForEach(TemperatureMetricCatalog.overviewMetrics) { descriptor in
                        Label(descriptor.title, systemImage: iconName(for: descriptor.domain))
                            .tag(MainWindowRoute.detail(descriptor.domain))
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 920, minHeight: 640)
        .task {
            windowCommandCenter.registerNavigationAction { route in
                selection = route
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .dashboard {
        case .dashboard:
            TemperatureDashboardView(
                onSelectMetric: { selection = .detail($0) },
                onOpenCompatibility: { selection = .compatibility }
            )
        case .compatibility:
            CompatibilityView(compact: false)
        case let .detail(domain):
            TemperatureDetailView(descriptor: TemperatureMetricCatalog.requiredMetric(for: domain))
        }
    }

    private func iconName(for domain: TemperatureDomain) -> String {
        switch domain {
        case .cpu:
            return "cpu"
        case .gpu:
            return "display"
        case .memory:
            return "memorychip"
        case .ssd:
            return "internaldrive"
        case .battery:
            return "battery.100"
        case .system:
            return "fanblades"
        case .sensor:
            return "dot.scope"
        }
    }
}
