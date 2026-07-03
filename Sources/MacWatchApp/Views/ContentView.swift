import MacWatchCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var runtime: MacWatchRuntime
    @State private var selection: MainWindowRoute? = .dashboard
    @State private var showFirstRunGuide = false
    private let windowCommandCenter = WindowCommandCenter.shared

    var body: some View {
        let localizer = runtime.localizer

        NavigationSplitView {
            List(selection: $selection) {
                Section(localizer.string("navigation.overview")) {
                    Label(localizer.string("dashboard.title"), systemImage: "rectangle.grid.2x2")
                        .tag(MainWindowRoute.dashboard)
                    Label(localizer.string("navigation.compatibility"), systemImage: "checklist")
                        .tag(MainWindowRoute.compatibility)
                }

                Section(localizer.string("navigation.metrics")) {
                    ForEach(TemperatureMetricCatalog.overviewMetrics) { descriptor in
                        Label(descriptor.localizedTitle(localizer), systemImage: iconName(for: descriptor.domain))
                            .tag(MainWindowRoute.detail(descriptor.domain))
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 560)
        .sheet(isPresented: $showFirstRunGuide) {
            FirstRunGuideView(
                context: runtime.firstRunGuideContext,
                initialSettings: runtime.settings
            ) { configuration in
                runtime.completeFirstRunGuide(configuration: configuration)
                showFirstRunGuide = false
            }
            .interactiveDismissDisabled(true)
        }
        .task {
            windowCommandCenter.registerNavigationAction { route in
                selection = route
            }
        }
        .task {
            showFirstRunGuide = runtime.shouldShowFirstRunGuide
        }
        .onChange(of: runtime.shouldShowFirstRunGuide) { showFirstRunGuide = $0 }
    }

    @ViewBuilder
    private var detailView: some View {
        if runtime.shouldShowFirstRunGuide && showFirstRunGuide {
            Color.clear
        } else {
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
    }

    private func iconName(for domain: TemperatureDomain) -> String {
        switch domain {
        case .cpu:
            return "cpu"
        case .gpu:
            return "display"
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
