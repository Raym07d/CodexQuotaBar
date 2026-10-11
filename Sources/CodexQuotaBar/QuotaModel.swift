import AppKit
import SwiftUI

@MainActor
final class QuotaModel: ObservableObject {
    static let shared = QuotaModel()
    private var started = false
    private var refreshID = UUID()
    @Published private(set) var refreshStage = ""
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    @Published private(set) var lastAttempt: Date?
    @Published var interval: Int {
        didSet { UserDefaults.standard.set(interval, forKey: "refreshInterval"); schedule() }
    }
    @Published var customPath: String {
        didSet { UserDefaults.standard.set(customPath, forKey: "codexPath") }
    }
    @Published var menuStyle: MenuStyle {
        didSet { UserDefaults.standard.set(menuStyle.rawValue, forKey: "menuStyle") }
    }
    @Published var showAppName: Bool {
        didSet { UserDefaults.standard.set(showAppName, forKey: "showAppName") }
    }
    @Published var hideMissing: Bool {
        didSet { UserDefaults.standard.set(hideMissing, forKey: "hideMissing") }
    }
    @Published var windowSelection: WindowSelection {
        didSet { UserDefaults.standard.set(windowSelection.rawValue, forKey: "windowSelection") }
    }
    @Published var numbersOnly: Bool {
        didSet { UserDefaults.standard.set(numbersOnly, forKey: "numbersOnly") }
    }
    @Published var showWidget: Bool {
        didSet {
            UserDefaults.standard.set(showWidget, forKey: "showWidget")
            updateWidget()
        }
    }
    private var desktopController: DesktopWidgetController?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let worker = DispatchQueue(label: "CodexQuotaBar.refresh", qos: .utility)

    init() {
        let saved = UserDefaults.standard.object(forKey: "refreshInterval") as? Int ?? 300
        interval = RefreshInterval.parse(String(saved)) ?? 300
        customPath = UserDefaults.standard.string(forKey: "codexPath") ?? ""
        menuStyle = MenuStyle(rawValue: UserDefaults.standard.string(forKey: "menuStyle") ?? "") ?? .standard
        showAppName = UserDefaults.standard.bool(forKey: "showAppName")
        hideMissing = UserDefaults.standard.object(forKey: "hideMissing") as? Bool ?? true
        windowSelection = WindowSelection(rawValue: UserDefaults.standard.string(forKey: "windowSelection") ?? "") ?? .both
        numbersOnly = UserDefaults.standard.bool(forKey: "numbersOnly")
        showWidget = UserDefaults.standard.bool(forKey: "showWidget")
    }

    func start() {
        guard !started else { return }
        started = true
        schedule()
        updateWidget()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.interval > 0 else { return }
                self.refresh()
            }
        }
        refresh()
    }

    var menuText: String {
        let prefix = error == nil ? "" : "! "
        return prefix + (showAppName ? "Codex " : "")
            + menuStyle.text(quota: snapshot?.quota, hideMissing: hideMissing,
                             selection: windowSelection, numbersOnly: numbersOnly)
    }

    private func updateWidget() {
        if showWidget {
            if desktopController == nil { desktopController = DesktopWidgetController(model: self) }
            desktopController?.show()
        } else {
            desktopController?.hide()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastAttempt = Date()
        refreshStage = "正在启动 Codex…"
        let requestID = UUID()
        refreshID = requestID
        DispatchQueue.main.asyncAfter(deadline: .now() + 32) { [weak self] in
            guard let self, self.refreshID == requestID, self.isRefreshing else { return }
            self.refreshID = UUID()
            self.isRefreshing = false
            self.error = "读取超过 32 秒，已停止等待。请点击刷新重试。"
            self.refreshStage = ""
        }
        let path = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        worker.async { [weak self] in
            let result = Result { try AppServer().fetch(customPath: path, progress: { stage in
                DispatchQueue.main.async {
                    guard let self, self.refreshID == requestID else { return }
                    self.refreshStage = stage
                    NSLog("CodexQuota refresh: %@", stage)
                }
            }) }
            DispatchQueue.main.async {
                guard let self, self.refreshID == requestID else { return }
                self.refreshStage = ""
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.error = nil
                    NSLog("CodexQuota refresh completed: %@", self.menuText)
                case .failure(let error):
                    // Keep the last successful snapshot visibly marked as stale, with its original account.
                    self.error = error.localizedDescription
                    NSLog("CodexQuota refresh failed: %@", error.localizedDescription)
                }
            }
        }
    }

    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 codex 可执行文件"
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
            snapshot = nil
            refresh()
        }
    }

    private func schedule() {
        timer?.invalidate()
        guard interval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = min(15, Double(interval) * 0.1)
    }
}
