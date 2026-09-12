#if (DEBUG && !APP_STORE) || SIDEY_REALS
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class RealsEditor: ObservableObject {
    @Published var project: RealsProject { didSet { scheduleAutosave() } }
    @Published var error: String?
    @Published var fileStatus = "이 Mac에 자동 저장"
    let player = RealsPlayer()
    private let defaults: UserDefaults?
    private var saveTask: Task<Void, Never>?

    convenience init() {
        #if SIDEY_REALS
        // The standalone app already owns app.sidey.reals as its standard domain.
        self.init(defaults: .standard)
        #else
        // The Debug tool must keep its drafts separate from SIDEY preferences.
        self.init(defaults: UserDefaults(suiteName: "app.sidey.reals"))
        #endif
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        guard let defaults else {
            project = .example
            fileStatus = "자동 저장 불가 · 설정을 파일로 저장해주세요"
            return
        }
        if let data = defaults.data(forKey: "draft") {
            do { project = try JSONDecoder().decode(RealsProject.self, from: data) }
            catch {
                project = .example
                self.error = "이전 설정을 읽지 못했어요. 저장된 원본은 복구용으로 남겨뒀어요."
                defaults.set(data, forKey: "unreadable-draft-backup")
            }
        } else { project = .example }
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        // Editing must not mutate the immutable timeline of an active take.
        if player.overlayVisible { player.stop() }
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        guard let defaults else { return }
        do {
            defaults.set(try JSONEncoder().encode(project), forKey: "draft")
            fileStatus = project.issues.isEmpty ? "이 Mac에 자동 저장됨" : "편집 중인 내용 저장됨 · 입력 확인 필요"
        } catch { fileStatus = "입력을 확인하면 자동 저장돼요" }
    }

    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = error.localizedDescription }
    }

    func addParticipant() {
        guard project.participants.count < 12 else { return }
        let index = project.participants.count
        let characters = PixelCharacterCatalog.all.filter { $0.entitlementKey == nil }
        project.participants.append(RealsParticipant(nickname: "유저\(index + 1)", characterID: characters[index % characters.count].id))
    }

    func removeParticipant(_ id: UUID) {
        guard project.participants.count > 1 else { return }
        guard !project.lines.contains(where: { $0.speakerID == id }),
              !project.actions.contains(where: { $0.actorID == id || ($0.kind == .toss && $0.targetID == id) }) else {
            error = "이 출연자의 채팅·액션을 먼저 삭제하거나 다른 출연자로 바꿔주세요."
            return
        }
        project.participants.removeAll { $0.id == id }
    }

    func addLine() {
        guard project.lines.count < 500, let speaker = project.participants.first else { return }
        project.lines.append(RealsLine(speakerID: speaker.id, body: ""))
    }

    func addAction() {
        guard project.actions.count < 100, let actor = project.participants.first else { return }
        project.actions.append(RealsAction(kind: project.participants.count > 1 ? .toss : .pulse,
                                          actorID: actor.id, targetID: project.participants.dropFirst().first?.id))
    }

    func moveLine(_ id: UUID, by offset: Int) {
        guard let index = project.lines.firstIndex(where: { $0.id == id }), project.lines.indices.contains(index + offset) else { return }
        project.lines.swapAt(index, index + offset)
    }

    func importText(_ text: String, replacing: Bool) throws {
        let lines = try project.importing(text)
        var candidate = project
        candidate.lines = replacing ? lines : candidate.lines + lines
        project = try candidate.validated()
    }

    func saveFile() {
        perform {
            let data = try project.encoded()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "\(project.title.isEmpty ? "sidey-reals" : project.title).json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            fileStatus = "\(url.lastPathComponent) 저장됨"
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000 else { throw RealsProject.InvalidProject(message: "설정 파일은 2MB 이하여야 해요.") }
            let candidate = try RealsProject.decode(Data(contentsOf: url))
            player.stop()
            project = candidate
            fileStatus = "\(url.lastPathComponent) 불러옴"
        }
    }

    func shutdown() { flush(); player.stop() }
}
#endif
