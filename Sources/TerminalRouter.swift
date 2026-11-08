import Foundation
import Darwin

// Routes identify a TUI instance, never a title, cwd match, or frontmost terminal.
actor TerminalRouter {
    private static let shared = TerminalRouter()
    private var opening = false
    static let routes = Bridge.root.appendingPathComponent("routes", isDirectory: true)

    struct Route: Decodable {
        let id: String
        let sessionIDs: [String]
        let currentSessionID: String?
        let launchToken: String?
        let updatedAt: Double
        let directory: String?
    }
    private struct Binding: Codable { let terminalID: String }
    private struct Request: Encodable { let sessionID: String; let nonce: String }
    private struct Ack: Decodable { let sessionID: String; let nonce: String }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Status is user-visible: fallback opens another client, not the original terminal.
    static func open(_ session: Session) async throws -> String {
        try await shared.route(session)
    }

    private func route(_ session: Session) async throws -> String {
        guard !opening else { throw Failure(message: "A session is still opening.") }
        opening = true
        defer { opening = false }
        return try await Task.detached(priority: .userInitiated) {
            try Self.openOffMain(session)
        }.value
    }

    private static func openOffMain(_ session: Session) throws -> String {
        guard validSessionID(session.id), session.directory.hasPrefix("/"), !session.directory.contains("\0") else {
            throw Failure(message: "Invalid session ID or directory.")
        }
        try FileManager.default.createDirectory(at: routes, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let routeDirectory = try routes.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard routeDirectory.isSymbolicLink != true, routeDirectory.isDirectory == true else {
            throw Failure(message: "The Dyland routes folder is not secure.")
        }
        for route in announcements().filter({ $0.sessionIDs.contains(session.id) && $0.directory == session.directory }).sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard let binding: Binding = read(file(route.id, "terminal")), UUID(uuidString: binding.terminalID) != nil else { continue }
            guard try script(existsScript, [binding.terminalID]) == "true" else { continue }
            let nonce = UUID().uuidString
            let request = file(route.id, "request")
            defer { try? FileManager.default.removeItem(at: request) }
            try write(Request(sessionID: session.id, nonce: nonce), to: request)
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if let ack: Ack = read(file(route.id, "ack")), ack.nonce == nonce, ack.sessionID == session.id {
                    _ = try script(focusScript, [binding.terminalID])
                    return "Session opened in the registered Ghostty TUI."
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        let executable = try findOpenCode()
        // V2 --session creates missing IDs. Confirm against the same default local service first.
        let response = try run(executable, ["api", "session.get", "--param", "sessionID=\(session.id)"], directory: session.directory)
        guard validResponse(response, for: session) else {
            throw Failure(message: "Session not found in the same local service. No new terminal was opened.")
        }
        let token = UUID().uuidString
        let command = [executable, "--session", session.id, session.directory].map(shellQuote).joined(separator: " ")
        let path = URL(fileURLWithPath: executable).deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let terminalID = try script(createScript, [session.directory, command, token, path])
        guard UUID(uuidString: terminalID) != nil else {
            throw Failure(message: "Ghostty opened a window but did not return a valid terminal ID.")
        }
        // Bind only the newly launched instance. Inherited launch tokens cannot redirect later TUIs.
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            let candidates = announcements().filter { $0.launchToken == token && $0.sessionIDs.contains(session.id) && $0.directory == session.directory }
            if candidates.count == 1, let route = candidates.first {
                try write(Binding(terminalID: terminalID), to: file(route.id, "terminal"))
                return "A new Ghostty window was opened for this session; this is not the original terminal. Future routing will use this TUI."
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return "A new Ghostty window was opened for this session; this is not the original terminal. The TUI plugin has not registered yet."
    }

    private static func announcements() -> [Route] {
        let now = Date().timeIntervalSince1970
        return ((try? FileManager.default.contentsOfDirectory(at: routes, includingPropertiesForKeys: nil)) ?? []).compactMap { url in
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  let route: Route = read(url), route.id == url.deletingPathExtension().lastPathComponent,
                  route.sessionIDs.count <= 1_000, route.sessionIDs.allSatisfy(validSessionID),
                  route.updatedAt > now - 10, route.updatedAt < now + 5 else { return nil }
            return route
        }
    }
    private static func file(_ id: String, _ suffix: String) -> URL {
        routes.appendingPathComponent("\(id).\(suffix).json")
    }
    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]),
              values.isSymbolicLink != true, values.isRegularFile == true, (values.fileSize ?? Int.max) <= 128_000,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func validResponse(_ response: String, for session: Session) -> Bool {
        guard let envelope = try? JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
              let object = envelope["data"] as? [String: Any],
              object["id"] as? String == session.id,
              let location = object["location"] as? [String: Any] else { return false }
        return location["directory"] as? String == session.directory
    }
    static func validSessionID(_ value: String) -> Bool {
        value.range(of: "\\Ases_[A-Za-z0-9_-]{1,240}\\z", options: .regularExpression) != nil
    }
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func findOpenCode() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { String($0) + "/opencode" }
        candidates += [".opencode/bin/opencode", ".local/bin/opencode", ".bun/bin/opencode"].map { home.appendingPathComponent($0).path }
        candidates += ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"]
        let nvm = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        candidates += ((try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/opencode").path }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Failure(message: "The opencode executable was not found. Install the OpenCode V2 CLI.")
        }
        return path
    }

    // Blocking process work runs only inside Task.detached. No shell evaluates AppleScript arguments.
    static func run(_ executable: String, _ arguments: [String], directory: String? = nil, timeout: TimeInterval = 15) throws -> String {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("dyland-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw Failure(message: "Could not create a temporary process output file.")
        }
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true) }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw Failure(message: "The process timed out. Check OpenCode and Ghostty Automation permissions.")
        }
        process.waitUntilExit()
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 2_000_001) ?? Data()
        guard data.count <= 2_000_000 else { throw Failure(message: "Process output is too large.") }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw Failure(message: "Failed to open session: \(text.prefix(1_000))")
        }
        return text
    }
    private static func script(_ source: String, _ arguments: [String]) throws -> String {
        try run("/usr/bin/osascript", ["-e", source] + arguments, timeout: 120)
    }
    private static let existsScript = """
    on run argv
        tell application id "com.mitchellh.ghostty"
            return exists (terminal id (item 1 of argv))
        end tell
    end run
    """
    private static let focusScript = """
    on run argv
        tell application id "com.mitchellh.ghostty"
            focus (terminal id (item 1 of argv))
        end tell
    end run
    """
    private static let createScript = """
    on run argv
        tell application id "com.mitchellh.ghostty"
            set cfg to new surface configuration
            set initial working directory of cfg to item 1 of argv
            set command of cfg to item 2 of argv
            set environment variables of cfg to {"DYLAND_ROUTE_TOKEN=" & (item 3 of argv), "PATH=" & (item 4 of argv)}
            set win to new window with configuration cfg
            return id of focused terminal of selected tab of win
        end tell
    end run
    """

    // Runnable without Apple events: TerminalRouter.selfCheck() from a small Swift main.
    static func selfCheck() throws {
        let session = Session(id: "ses_test", title: "Test", directory: "/test", updatedAt: 0)
        precondition(validResponse(#"{"data":{"id":"ses_test","location":{"directory":"/test"}}}"#, for: session))
        precondition(!validResponse(#"{"data":{"id":"ses_other","location":{"directory":"/test"}}}"#, for: session))
        precondition(!validResponse(#"{"id":"ses_test","location":{"directory":"/test"}}"#, for: session))
        precondition(validSessionID("ses_test-123"))
        precondition(!validSessionID("ses_bad\ninput"))
        precondition(!validSessionID("--session"))
        for value in ["", "plain", "a'b", "$(touch /never-run)", "line\nbreak", "路径 with spaces"] {
            let result = try run("/bin/sh", ["-c", "printf '%s' " + shellQuote(value)])
            precondition(result == value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            _ = try run("/bin/sleep", ["2"], timeout: 0.05)
            assertionFailure("Process timeout must fail")
        } catch is Failure {}
        print("TerminalRouter self-check passed")
    }
}
