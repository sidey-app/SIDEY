import AppKit

/// Debug launch proof is prepared outside the sandbox by the CLI/Xcode launch action.
/// The executable's compiled build ID, never a disk-only bundle version, identifies it.
@MainActor
final class BuildReview {
    static let shared = BuildReview()
    private var ticket: Ticket?
    private var readinessTask: Task<Void, Never>?

    private struct Ticket: Codable {
        let build_id: String
        let commit: String
        let input_hash: String
        let target: String
        let configuration: String
        let bundle_id: String
        let session: String
        let executable: String
        let issued_at: Double
    }

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SIDEY/BuildReview", isDirectory: true)
    }

    func validateLaunch() -> Bool {
        #if DEBUG
        let path = directory.appendingPathComponent("\(SideyBuildStamp.buildID).ticket.json")
        do {
            let data = try Data(contentsOf: path)
            // A consumed ticket cannot authorize Run Without Building a second time.
            try FileManager.default.removeItem(at: path)
            let candidate = try JSONDecoder().decode(Ticket.self, from: data)
            let age = Date().timeIntervalSince1970 - candidate.issued_at
            guard age >= 0, age < 60,
                  candidate.build_id == SideyBuildStamp.buildID,
                  candidate.commit == SideyBuildStamp.commit,
                  candidate.input_hash == SideyBuildStamp.inputHash,
                  candidate.target == SideyBuildStamp.target,
                  candidate.configuration == SideyBuildStamp.configuration,
                  candidate.bundle_id == Bundle.main.bundleIdentifier,
                  candidate.executable == Bundle.main.executableURL?.resolvingSymlinksInPath().path
            else { throw CocoaError(.fileReadCorruptFile) }
            ticket = candidate
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "현재 소스로 빌드한 앱인지 확인할 수 없습니다."
            alert.informativeText = "scripts/macos/open_current.sh로 다시 열거나 Xcode에서 빌드 후 실행해 주세요."
            alert.addButton(withTitle: "종료")
            alert.runModal()
            return false
        }
        #else
        return true
        #endif
    }

    func observeReadyWindow() {
        #if DEBUG
        guard let ticket else { return }
        readinessTask = Task { [weak self] in
            for _ in 0..<200 {
                guard !Task.isCancelled, let self else { return }
                // Check this application's normal startup window, without screen capture.
                if let window = NSApplication.shared.windows.first(where: {
                    $0.isVisible && $0.contentView != nil && $0.level == .normal
                }) {
                    window.displayIfNeeded()
                    let value: [String: Any] = [
                        "session": ticket.session,
                        "build_id": SideyBuildStamp.buildID,
                        "commit": SideyBuildStamp.commit,
                        "input_hash": SideyBuildStamp.inputHash,
                        "target": SideyBuildStamp.target,
                        "configuration": SideyBuildStamp.configuration,
                        "executable": Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "",
                        "pid": ProcessInfo.processInfo.processIdentifier,
                        "window_ready": true,
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: value) {
                        try? data.write(to: self.directory.appendingPathComponent("\(ticket.session).ready.json"), options: .atomic)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        #endif
    }

    func stop() {
        readinessTask?.cancel()
        readinessTask = nil
    }
}
