import Foundation
import Darwin

/// One short-lived stdio session per refresh. No log parsing or token estimates.
/// All blocking pipe I/O runs on the model's dedicated background queue.
final class AppServer {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var sequence = 0
    private let timeout: TimeInterval
    private var fetchDeadline: TimeInterval = 0

    init(timeout: TimeInterval = 25) {
        self.timeout = timeout
        signal(SIGPIPE, SIG_IGN)
    }

    static func executable(custom: String = "") throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                     "/Applications/Codex.app/Contents/Resources/codex",
                     "\(home)/Applications/Codex.app/Contents/Resources/codex"]
        let search = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        let candidates = custom.isEmpty ? paths + search : [(custom as NSString).expandingTildeInPath]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw QuotaError(message: L10n.text("找不到 Codex。请安装 Codex CLI，或在设置中选择 codex 可执行文件。", "Codex was not found. Install Codex CLI or select its executable in Settings."))
        }
        return URL(fileURLWithPath: path)
    }

    func fetch(customPath: String = "", progress: (String) -> Void = { _ in }) throws -> QuotaSnapshot {
        fetchDeadline = ProcessInfo.processInfo.systemUptime + timeout
        progress(L10n.text("正在启动 Codex…", "Starting Codex…"))
        process.executableURL = try Self.executable(custom: customPath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        process.standardInput = input
        process.standardOutput = output
        // Do not persist potentially sensitive backend logs; stdout is protocol only.
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { stop() }
        progress(L10n.text("正在连接 Codex…", "Connecting to Codex…"))
        _ = try request("initialize", params: ["clientInfo": ["name": "codex_quota_bar", "title": "Codex Quota Bar", "version": "1.0.0"]])
        try send(["method": "initialized"])
        progress(L10n.text("正在读取账户…", "Reading account…"))
        let account: AccountResponse = try decode(try request("account/read", params: ["refreshToken": false]))
        guard let identity = account.account else {
            throw QuotaError(message: L10n.text("尚未登录。请在终端运行 codex login，以 ChatGPT 账户登录后刷新。", "You are not signed in. Run codex login in Terminal with your ChatGPT account, then refresh."))
        }
        guard identity.type == "chatgpt" else {
            throw QuotaError(message: L10n.text("当前登录方式为 \(identity.type)。请用 codex login 登录 ChatGPT 账户以读取订阅额度。", "Current sign-in method: \(identity.type). Sign in with a ChatGPT account using codex login to read subscription limits."))
        }
        progress(L10n.text("正在请求服务端额度…", "Requesting server quota…"))
        let quota: QuotaResponse = try decode(try request("account/rateLimits/read"))
        return QuotaSnapshot(quota: quota, account: identity, fetchedAt: Date())
    }

    private func decode<T: Decodable>(_ object: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        data.append(0x0a)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func request(_ method: String, params: [String: Any]? = nil) throws -> Any {
        sequence += 1
        let id = sequence
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)
        let deadline = fetchDeadline
        while ProcessInfo.processInfo.systemUptime < deadline {
            let line = try readLine(deadline: deadline)
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            // Explicitly decline server requests; this read-only client cannot supply credentials or approvals.
            if object["method"] != nil, let requestID = object["id"] {
                try send(["id": requestID, "error": ["code": -32601, "message": "Unsupported client request"]])
                continue
            }
            guard (object["id"] as? Int) == id else { continue }
            if let error = object["error"] as? [String: Any] {
                let detail = error["message"] as? String ?? L10n.text("未知服务端错误", "Unknown server error")
                throw QuotaError(message: "\(method)：\(detail)")
            }
            if let result = object["result"] { return result }
            throw QuotaError(message: L10n.text("服务端返回了无效响应。", "The server returned an invalid response."))
        }
        throw QuotaError(message: L10n.text("读取服务端额度超时，请检查网络后重试。", "Timed out reading server quota. Check your connection and try again."))
    }

    private func readLine(deadline: TimeInterval) throws -> Data {
        while true {
            if let end = buffer.firstIndex(of: 0x0a) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                if !line.isEmpty { return line }
                continue
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw QuotaError(message: L10n.text("读取服务端额度超时，请检查网络后重试。", "Timed out reading server quota. Check your connection and try again.")) }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, Int32(min(remaining * 1000, 500)))
            if ready < 0 {
                if errno == EINTR { continue }
                throw QuotaError(message: L10n.text("无法读取 Codex 进程输出。", "Could not read output from Codex."))
            }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw QuotaError(message: L10n.text("Codex app-server 已退出。请检查 Codex 安装和配置。", "Codex app-server exited. Check your Codex installation and configuration.")) }
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.count > 8 * 1024 * 1024 { throw QuotaError(message: L10n.text("服务端响应过大。", "The server response is too large.")) }
        }
    }

    private func stop() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        // Foundation reaps Process asynchronously. Never wait indefinitely during cleanup;
        // the successful quota result must not be held behind child-process termination.
        try? output.fileHandleForReading.close()
    }
}
