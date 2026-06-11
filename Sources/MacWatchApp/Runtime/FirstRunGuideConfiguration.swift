import MacWatchCore

struct FirstRunGuideConfiguration: Equatable {
    var temperatureUnit: TemperatureUnit
    var menuBarDisplayMetric: MenuBarDisplayMetric
    var refreshInterval: RefreshInterval

    init(
        temperatureUnit: TemperatureUnit,
        menuBarDisplayMetric: MenuBarDisplayMetric,
        refreshInterval: RefreshInterval
    ) {
        self.temperatureUnit = temperatureUnit
        self.menuBarDisplayMetric = menuBarDisplayMetric
        self.refreshInterval = refreshInterval
    }

    init(settings: AppSettings) {
        self.init(
            temperatureUnit: settings.temperatureUnit,
            menuBarDisplayMetric: settings.menuBarDisplayMetric,
            refreshInterval: settings.refreshInterval
        )
    }
}
