import AppKit
import SwiftUI

@MainActor
final class DesktopWidgetController {
    private let panel: NSPanel
    init(model: QuotaModel) {
        panel = NSPanel(contentRect: NSRect(x: 80, y: 120, width: 260, height: 230),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: DesktopWidgetView(model: model))
        panel.setFrameAutosaveName("CodexQuotaDesktopWidget")
    }
    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
}

struct DesktopWidgetView: View {
    @ObservedObject var model: QuotaModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Codex").font(.headline)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.mini) }
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(model.isRefreshing).help("刷新额度")
            }
            if let quota = model.snapshot?.quota {
                if let window = quota.fiveHour { WindowRow(window: window, name: "5h") }
                else if !model.hideMissing { Text("5h  —").foregroundStyle(.secondary) }
                if let window = quota.week { WindowRow(window: window, name: "week") }
                else if !model.hideMissing { Text("week  —").foregroundStyle(.secondary) }
                if quota.fiveHour == nil && quota.week == nil { Text("暂未提供窗口数据").font(.caption) }
            } else {
                Text(model.isRefreshing ? "正在读取…" : "暂无额度数据").foregroundStyle(.secondary)
            }
            if model.error != nil {
                Label("刷新失败 · 数据可能过期", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            } else if let time = model.snapshot?.fetchedAt {
                Text("更新于 \(time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(width: 260, height: 230)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.2)))
    }
}
