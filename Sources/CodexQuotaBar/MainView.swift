import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var model: QuotaModel
    @State private var seconds = ""
    @State private var validation: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                QuotaPanel(model: model)
            }.frame(width: 380)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L10n.text("显示与刷新", "Display and refresh")).font(.title2.bold())
                    GroupBox(L10n.text("显示位置", "Display location")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(L10n.text("显示桌面小组件", "Show desktop widget"), isOn: $model.showWidget)
                            Text(L10n.text("关闭主窗口后仍在菜单栏运行。点击菜单栏额度，再选“打开主界面与设置”即可回来。", "The app stays in the menu bar when you close this window. Click the quota in the menu bar and choose Open main window and settings to return."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    GroupBox(L10n.text("菜单栏样式", "Menu bar appearance")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker(L10n.text("样式", "Style"), selection: $model.menuStyle) {
                                ForEach(MenuStyle.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                            Picker(L10n.text("显示额度", "Show quota"), selection: $model.windowSelection) {
                                ForEach(WindowSelection.allCases) { Text($0.title).tag($0) }
                            }
                            Toggle(L10n.text("只显示数字（隐藏 5h / w 标签）", "Numbers only (hide 5h / w labels)"), isOn: $model.numbersOnly)
                            Toggle(L10n.text("隐藏没有额度数据的窗口", "Hide windows without quota data"), isOn: $model.hideMissing)
                            Toggle(L10n.text("显示 Codex 名称", "Show Codex name"), isOn: $model.showAppName)
                            Text(L10n.text("实时预览", "Live preview")).font(.caption).foregroundStyle(.secondary)
                            Text(model.menuText).font(.system(size: model.menuStyle == .stacked ? 10 : 13, weight: .medium, design: .monospaced))
                                .padding(10).frame(maxWidth: .infinity)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            Text(L10n.text("可只显示一个额度；只显示数字时，周额度可呈现为 95%。全部未知时显示 —。", "Show either quota alone. With numbers only, weekly quota can appear as 95%. — appears when all selected values are unavailable."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                    GroupBox(L10n.text("自动刷新", "Auto-refresh")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField(L10n.text("秒数", "Seconds"), text: $seconds).frame(width: 90)
                                    .onSubmit(applyInterval)
                                Text(L10n.text("秒", "seconds"))
                                Button(L10n.text("应用", "Apply"), action: applyInterval)
                            }
                            Text(L10n.text("输入 10–86400 秒；0 为关闭。当前：\(model.interval == 0 ? "已关闭" : "每 \(model.interval) 秒")", "Enter 10–86400 seconds, or 0 to disable. Current: \(model.interval == 0 ? "Off" : "Every \(model.interval) seconds")"))
                                .font(.caption).foregroundStyle(.secondary)
                            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
                            HStack {
                                ForEach([60, 300, 900], id: \.self) { value in
                                    Button(L10n.text("\(value / 60) 分钟", "\(value / 60) min")) { seconds = String(value); applyInterval() }
                                }
                            }.controlSize(.small)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                    Text(L10n.text("所有显示位置共享同一份真实服务端数据。设置即时保存。", "All display locations share the same live server data. Settings are saved immediately."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.frame(minWidth: 340)
        }.frame(minWidth: 740, minHeight: 620)
        .onAppear { seconds = String(model.interval) }
    }
    private func applyInterval() {
        guard let value = RefreshInterval.parse(seconds) else {
            validation = L10n.text("请输入 0 或 10–86400 之间的整数。", "Enter 0 or an integer from 10 to 86400."); return
        }
        model.interval = value
        seconds = String(value)
        validation = nil
    }
}

/// MenuBarExtra flattens SwiftUI stacks; draw a template image for a true two-line label.
@MainActor
enum MenuLabelRenderer {
    static func image(text: String) -> NSImage {
        let lines = text.components(separatedBy: "\n")
        let font = NSFont.monospacedDigitSystemFont(ofSize: lines.count > 1 ? 9 : 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let width = ceil(lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 50) + 2
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            for (index, line) in lines.enumerated() {
                let y: CGFloat = lines.count > 1 ? CGFloat(11 - index * 10) : 3
                (line as NSString).draw(at: NSPoint(x: 1, y: y), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
