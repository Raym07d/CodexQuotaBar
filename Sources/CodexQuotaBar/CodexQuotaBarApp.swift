import SwiftUI
import AppKit

@main
struct CodexQuotaBarApp: App {
    @NSApplicationDelegateAdaptor(QuotaAppDelegate.self) private var delegate
    @StateObject private var model = QuotaModel.shared

    init() {
        // Diagnostic mode uses exactly the same transport and parser as the UI.
        if CommandLine.arguments.contains("--probe") {
            do {
                let snapshot = try AppServer().fetch()
                print("Live account/rateLimits/read succeeded; plan: \(snapshot.account.planType ?? "unknown")")
                for bucket in snapshot.quota.buckets {
                    for window in [bucket.value.primary, bucket.value.secondary].compactMap({ $0 }) {
                        print("\(bucket.id) | \(window.duration) | used=\(window.usedPercent.map { String($0) } ?? "unknown")% | remaining=\(window.remaining.map { String($0) } ?? "unknown")% | resetsAt=\(window.resetsAt.map { String($0) } ?? "unknown")")
                    }
                }
                exit(0)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        MenuBarExtra {
            QuotaPanel(model: model)
        } label: {
            if model.menuStyle == .stacked {
                Image(nsImage: MenuLabelRenderer.image(text: model.menuText))
                    .accessibilityLabel("Codex 剩余额度 \(model.menuText)")
            } else {
                Text(model.menuText).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct QuotaPanel: View {
    @ObservedObject var model: QuotaModel
    @State private var showSettings = false


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Quota").font(.system(size: 19, weight: .semibold))
                    Text("账户额度").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(model.isRefreshing).help("立即刷新")
                    .accessibilityLabel("立即刷新")
            }
            if let snapshot = model.snapshot {
                HStack {
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                    Text(snapshot.account.email ?? "ChatGPT 账户").lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text((snapshot.account.planType ?? "ChatGPT").uppercased())
                        .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }.font(.caption)
            }
            if model.isRefreshing && model.snapshot != nil {
                Text(model.refreshStage).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 5) {
                    Label(model.snapshot == nil ? "无法获取额度" : "刷新失败 · 以下为上次数据", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold()).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(5)
                }
            }
            if let snapshot = model.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Codex · 剩余额度").font(.subheadline.weight(.semibold))
                            coreRow(snapshot.quota.fiveHour, title: "5h · 5 小时")
                            Divider()
                            coreRow(snapshot.quota.week, title: "week · 7 天")
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        ForEach(snapshot.quota.buckets.filter { $0.id != "codex" || snapshot.quota.coreWindows.contains { ![300, 10080].contains($0.windowDurationMins ?? 0) } }, id: \.id) { bucket in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(bucket.value.limitName ?? (bucket.id == "codex" ? "Codex" : bucket.id))
                                    .font(.subheadline.weight(.semibold))
                                if let primary = bucket.value.primary { WindowRow(window: primary, name: "主要窗口") }
                                if let secondary = bucket.value.secondary { WindowRow(window: secondary, name: "次要窗口") }
                                if bucket.value.primary == nil && bucket.value.secondary == nil {
                                    Text("服务端未提供额度窗口").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if snapshot.quota.buckets.isEmpty {
                            Text("服务端暂未提供额度信息。未提供的数据不会视为 0%。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }.frame(height: snapshot.quota.buckets.count > 1 ? 300 : 220)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 4) {
                        Circle().fill(model.error == nil ? Color.green : Color.orange).frame(width: 5, height: 5)
                        Text("更新于 \(snapshot.fetchedAt.formatted(date: .omitted, time: .standard))")
                        if context.date.timeIntervalSince(snapshot.fetchedAt) > Double(max(model.interval * 2, 600)) {
                            Text("· 数据较旧").foregroundStyle(.orange)
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else if model.isRefreshing {
                Text(model.refreshStage)
                    .foregroundStyle(.secondary).font(.callout).frame(maxWidth: .infinity, minHeight: 90)
            }
            Divider()
            HStack {
                Text("自动刷新").font(.caption).foregroundStyle(.secondary)
                Text(model.interval == 0 ? "已关闭" : "每 \(model.interval) 秒").font(.caption)
                Spacer()
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("设置").accessibilityLabel("设置")
                Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless).font(.caption)
            }
            Button("打开主界面与设置…") {
                MainWindowController.shared.show(model: model)
            }.buttonStyle(.borderless)
            if showSettings {
                VStack(alignment: .leading, spacing: 8) {
                    Text("菜单栏显示样式").font(.caption.bold())
                    Picker("显示样式", selection: $model.menuStyle) {
                        ForEach(MenuStyle.allCases) { style in Text(style.title).tag(style) }
                    }.labelsHidden()
                    Toggle("显示 Codex 名称", isOn: $model.showAppName).toggleStyle(.checkbox)
                    Text("预览：\(model.menuText)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Codex 路径设置") {
                    Text("Codex 可执行文件").font(.caption.bold())
                    Text(model.customPath.isEmpty ? ((try? AppServer.executable().path) ?? "未找到 codex") : model.customPath)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button("选择文件…", action: model.chooseExecutable)
                        Button("自动查找") { model.customPath = ""; model.refresh() }
                    }.controlSize(.small).disabled(model.isRefreshing)
                    }
                    Text("菜单栏显示两个窗口的剩余比例。— 表示服务端未返回该窗口，不能视为 0% 或 100%。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(18).frame(width: 380).fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder
    private func coreRow(_ window: QuotaWindow?, title: String) -> some View {
        if let window {
            WindowRow(window: window, name: title)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("—").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("剩余").font(.caption).foregroundStyle(.secondary)
                }
                Text("服务端未返回此窗口").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct WindowRow: View {
    let window: QuotaWindow
    let name: String
    private var tint: Color {
        guard let remaining = window.remaining else { return .secondary }
        return remaining <= 10 ? .red : remaining <= 25 ? .orange : .accentColor
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(name == "主要窗口" || name == "次要窗口" ? window.duration : name).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(window.remaining.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))%" } ?? "—")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("剩余").font(.caption).foregroundStyle(.secondary)
            }
            if let remaining = window.remaining {
                ProgressView(value: remaining, total: 100).tint(tint)
                    .accessibilityLabel("剩余 \(remaining.formatted())%")
            }
            HStack {
                Text(window.usedPercent.map { "已用 \($0.formatted(.number.precision(.fractionLength(0...1))))%" } ?? "已用比例未知")
                Spacer()
                if let reset = window.resetDate {
                    Text("重置 \(reset.formatted(.dateTime.month().day().hour().minute()))")
                        .help(reset.formatted(date: .complete, time: .complete))
                } else { Text("重置时间未知") }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
