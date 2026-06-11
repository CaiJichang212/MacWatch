import MacWatchCore
import SwiftUI

struct FirstRunGuideView: View {
    let context: FirstRunGuideContext
    let onContinue: (FirstRunGuideConfiguration) -> Void

    @State private var configuration: FirstRunGuideConfiguration

    init(
        context: FirstRunGuideContext,
        initialSettings: AppSettings,
        onContinue: @escaping (FirstRunGuideConfiguration) -> Void
    ) {
        self.context = context
        self.onContinue = onContinue
        _configuration = State(initialValue: FirstRunGuideConfiguration(settings: initialSettings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("首次启动说明")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("MacWatch MVP 已启动。应用默认只采集本机温度，不做数据导出、不上传、不联网。")
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                Text("设备识别")
                    .font(.headline)
                Text("机型：\(context.displayModel)")
                    .font(.body)
                Text("芯片：\(context.displayChip)")
                    .font(.body)
                Text("兼容状态：\(context.isSupportedTargetMachine ? "在范围内" : "不在范围内")")
                    .font(.body)
                Text(context.supportMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("隐私声明")
                .font(.headline)
            Text("MVP 默认不联网。所有温度样本仅保留在本次运行会话内本地数据库，且不记录网络内容。")
                .font(.body)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("初始配置")
                    .font(.headline)

                Picker("温度单位", selection: $configuration.temperatureUnit) {
                    Text("摄氏度").tag(TemperatureUnit.celsius)
                    Text("华氏度").tag(TemperatureUnit.fahrenheit)
                }
                .pickerStyle(.segmented)

                Picker("菜单栏显示", selection: $configuration.menuBarDisplayMetric) {
                    Text("最高温度").tag(MenuBarDisplayMetric.hottest)
                    Text("CPU").tag(MenuBarDisplayMetric.cpu)
                    Text("GPU").tag(MenuBarDisplayMetric.gpu)
                    Text("SSD/NAND").tag(MenuBarDisplayMetric.ssd)
                    Text("电池").tag(MenuBarDisplayMetric.battery)
                }

                Picker("刷新间隔", selection: $configuration.refreshInterval) {
                    Text("5 秒").tag(RefreshInterval.fiveSeconds)
                    Text("10 秒").tag(RefreshInterval.tenSeconds)
                    Text("30 秒").tag(RefreshInterval.thirtySeconds)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button("开始监控") {
                    onContinue(configuration)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            AcceptanceCoordinator.shared.recordViewAppeared(.firstRunGuide)
        }
        .padding(28)
        .frame(minWidth: 520)
    }
}
