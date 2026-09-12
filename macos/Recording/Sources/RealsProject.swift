#if (DEBUG && !APP_STORE) || SIDEY_REALS
import Foundation

struct RealsParticipant: Codable, Equatable, Identifiable {
    var id = UUID()
    var nickname: String
    var characterID: String
}

struct RealsLine: Codable, Equatable, Identifiable {
    var id = UUID()
    var speakerID: UUID
    var body: String
    /// nil uses the project's default; interval is measured after this line.
    var interval: Double?
}

struct RealsAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case pulse, toss }
    var id = UUID()
    var kind: Kind = .toss
    var actorID: UUID
    var targetID: UUID?
    var start: Double = 0
    var end: Double = 0
    var interval: Double = 1
    var throwableID = "patch_soft_ball"

    static let throwables = [
        ("patch_soft_ball", "말랑공"), ("mini_paprika", "미니 파프리카"), ("banana", "바나나"),
        ("dust_bath_pouch", "모래주머니"), ("starlight_orb", "별빛 구슬"),
        ("throwable_bouncy_heart", "통통 하트"), ("throwable_squeaky_duck", "오리"),
        ("throwable_toy_cannon", "대포")
    ]

    var repetitionCount: Int {
        guard start.isFinite, end.isFinite, interval.isFinite,
              start >= 0, end >= start, end <= 3600, interval >= 0.5 else { return 0 }
        return Int(floor((end - start + 0.000001) / interval)) + 1
    }
}

struct RealsProject: Codable, Equatable {
    var version = 1
    var title = "수업 중 몰래 채팅"
    var participants: [RealsParticipant]
    var lines: [RealsLine]
    var actions: [RealsAction] = []
    var soundEnabled = true
    var defaultInterval: Double = 2.8
    var countdown: Double = 5
    var bubbleLifetime: Double = 10
    var endingHold: Double = 5
    var overlayWidth: Double = 960
    var fixedPositions = true

    static var example: Self {
        let people = ["pixel_hamster", "pixel_cat", "pixel_puppy"].enumerated().map {
            RealsParticipant(nickname: "유저\($0.offset + 1)", characterID: $0.element)
        }
        let script: [(Int, String, Double)] = [
            (0, "아오 교수님 수업 개안끝내주네", 2.8), (0, "50분 고봉밥 실화?", 2.2),
            (1, "근데 교수님 지금 뭐라 하시는 거임?", 3), (1, "발음 왤케 셈?", 2),
            (2, "이해 못한 사람 푸처핸섭", 2.8), (1, "이해는 진작 포기했고 받아쓰기에서 막힘", 3.5),
            (0, "나 방금 질문하고 왔는데", 2.5), (0, "교수님 입냄새 개심함", 2.7),
            (2, "지식을 숨결에 담아 전달하시네", 3), (1, "그래서 대면 수업 고집하셨구나", 3),
            (2, "야 근데 교수님 바지 지퍼 열림", 3), (0, "수업은 닫고 그걸 여셨네", 2.7),
            (1, "열린 교육 실천하시잖아", 2.8), (2, "ㅅㅂ 웃지 마", 1.5), (2, "여기 보심", 2.3),
            (0, "햄스터 귀여워서 웃었다고 해", 3.2), (1, "교수님이 햄스터 뭐 하는 거냐고 물어보심", 4),
            (2, "동물 키우는 거라 해", 3), (1, "교수님도 키우고 싶으시대", 4), (0, "초대하지 마라", 3)
        ]
        return Self(participants: people, lines: script.map {
            RealsLine(speakerID: people[$0.0].id, body: $0.1, interval: $0.2)
        })
    }

    var issues: [String] {
        var result: [String] = []
        if version != 1 { result.append("지원하지 않는 설정 파일 버전이에요.") }
        if !(1...12).contains(participants.count) { result.append("출연자는 1~12명으로 설정하세요.") }
        if Set(participants.map(\.id)).count != participants.count { result.append("출연자 식별자가 중복돼요.") }
        if title.count > 80 { result.append("제목은 80자 이내로 입력하세요.") }
        for (index, person) in participants.enumerated() {
            if person.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || person.nickname.count > 8
                || person.nickname.contains(where: { $0.isNewline }) {
                result.append("출연자 \(index + 1)의 이름은 줄바꿈 없이 1~8자로 입력하세요.")
            }
            if !PixelCharacterCatalog.all.contains(where: { $0.id == person.characterID }) {
                result.append("출연자 \(index + 1)의 캐릭터를 다시 선택하세요.")
            }
        }
        if lines.count > 500 { result.append("채팅은 최대 500개까지 넣을 수 있어요.") }
        if Set(lines.map(\.id)).count != lines.count { result.append("채팅 식별자가 중복돼요.") }
        let people = Set(participants.map(\.id))
        for (index, line) in lines.enumerated() {
            if !people.contains(line.speakerID) { result.append("\(index + 1)번 채팅의 출연자가 없어요.") }
            if line.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || line.body.count > 200
                || line.body.components(separatedBy: .newlines).count > 3 {
                result.append("\(index + 1)번 채팅은 1~200자, 최대 3줄로 입력하세요.")
            }
            if let interval = line.interval, !interval.isFinite || !(0.1...120).contains(interval) {
                result.append("\(index + 1)번 채팅 간격은 0.1~120초로 설정하세요.")
            }
        }
        if actions.count > 100 { result.append("액션은 최대 100개까지 넣을 수 있어요.") }
        if Set(actions.map(\.id)).count != actions.count { result.append("액션 식별자가 중복돼요.") }
        if actions.reduce(0, { $0 + $1.repetitionCount }) > 2000 { result.append("반복 액션은 총 2,000회 이내로 설정하세요.") }
        for (index, action) in actions.enumerated() {
            let prefix = "액션 \(index + 1): "
            if !people.contains(action.actorID) { result.append(prefix + "행동할 출연자를 선택하세요.") }
            if action.kind == .toss {
                if action.targetID == action.actorID || !people.contains(action.targetID ?? UUID()) {
                    result.append(prefix + "자신을 제외한 던질 대상을 선택하세요.")
                }
                if !RealsAction.throwables.contains(where: { $0.0 == action.throwableID }) {
                    result.append(prefix + "투척물을 다시 선택하세요.")
                }
            }
            if action.repetitionCount == 0 { result.append(prefix + "시간은 0~3,600초, 종료는 시작 이후로 설정하세요.") }
            let minimum = action.kind == .pulse ? 1.0 : 0.5
            if !action.interval.isFinite || !(minimum...120).contains(action.interval) {
                result.append(prefix + "반복 간격은 \(minimum)~120초로 설정하세요.")
            }
        }
        if actions.count <= 100 && actions.reduce(0, { $0 + $1.repetitionCount }) <= 2000 {
            for person in participants {
                for kind in RealsAction.Kind.allCases {
                    let times = actions.filter { $0.actorID == person.id && $0.kind == kind }.flatMap { action in
                        (0..<action.repetitionCount).map { action.start + Double($0) * action.interval }
                    }.sorted()
                    let minimum = kind == .pulse ? 1.0 : 0.5
                    if zip(times, times.dropFirst()).contains(where: { $1 - $0 < minimum - 0.000001 }) {
                        result.append("\(person.nickname)의 \(kind == .pulse ? "확대" : "던지기") 예약이 겹쳐요. 최소 \(minimum)초 간격으로 조정하세요.")
                    }
                }
            }
        }
        for (label, value, range) in [
            ("기본 간격", defaultInterval, 0.1...120), ("준비 시간", countdown, 0...30),
            ("말풍선 유지", bubbleLifetime, 1...60), ("마지막 여운", endingHold, 1...30),
            ("화면 폭", overlayWidth, 360...3000)
        ] {
            if !value.isFinite || !range.contains(value) { result.append("\(label) 값을 허용 범위 안으로 설정하세요.") }
        }
        return result
    }

    struct InvalidProject: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func validated() throws -> Self {
        if let issue = issues.first { throw InvalidProject(message: issue) }
        return self
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 2_000_000 else { throw InvalidProject(message: "설정 파일은 2MB 이하여야 해요.") }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }

    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func importing(_ text: String) throws -> [RealsLine] {
        guard text.count <= 120_000 else { throw InvalidProject(message: "붙여넣을 대화가 너무 길어요.") }
        var imported: [RealsLine] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let row = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if row.isEmpty { continue }
            guard let colon = row.firstIndex(of: ":") else {
                throw InvalidProject(message: "\(index + 1)번째 줄을 ‘유저1: 대사’ 형식으로 입력하세요.")
            }
            let name = String(row[..<colon]).trimmingCharacters(in: .whitespaces)
            let body = String(row[row.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let number = Int(name) ?? (name.hasPrefix("유저") ? Int(name.dropFirst(2)) : nil)
            let person: RealsParticipant?
            if let number, participants.indices.contains(number - 1) {
                person = participants[number - 1]
            } else {
                let matches = participants.filter { $0.nickname == name }
                person = matches.count == 1 ? matches[0] : nil
            }
            guard let person else {
                throw InvalidProject(message: "\(index + 1)번째 줄의 ‘\(name)’ 출연자를 찾을 수 없어요. 이름이 겹치면 출연자 번호를 쓰세요.")
            }
            imported.append(RealsLine(speakerID: person.id, body: body))
        }
        guard !imported.isEmpty else { throw InvalidProject(message: "붙여넣을 대화를 입력하세요.") }
        var candidate = self
        candidate.lines = imported
        _ = try candidate.validated()
        return imported
    }
}

struct RealsTimeline {
    struct Event {
        let second: Double
        let line: RealsLine
    }
    let project: RealsProject
    let events: [Event]
    struct ActionEvent {
        let second: Double
        let action: RealsAction
        let id = UUID()
    }
    let actionEvents: [ActionEvent]
    let duration: Double
    let roomID = UUID()

    init(project: RealsProject) {
        self.project = project
        var second = 0.0
        events = project.lines.map { line in
            defer { second += line.interval ?? project.defaultInterval }
            return Event(second: second, line: line)
        }
        var scheduled: [ActionEvent] = []
        for action in project.actions where scheduled.count + action.repetitionCount <= 2000 {
            scheduled += (0..<action.repetitionCount).map {
                ActionEvent(second: action.start + Double($0) * action.interval, action: action)
            }
        }
        actionEvents = scheduled.sorted { $0.second < $1.second }
        duration = max(events.last?.second ?? 0, actionEvents.last?.second ?? 0) + project.endingHold
    }

    struct Presentation: Equatable {
        let members: [PixelWorldMember]
        let bubbles: [ActiveBubble]
        let delivered: Int
    }

    func presentation(at elapsed: Double) -> Presentation {
        let delivered = events.filter { $0.second <= elapsed }
        let upcoming = events.first { $0.second > elapsed }
        let typing = upcoming.flatMap { elapsed >= $0.second - 0.8 ? $0.line.speakerID : nil }
        var ledger = ActiveBubbleLedger()
        for event in delivered {
            ledger.show(senderID: event.line.speakerID, messageID: event.line.id, body: event.line.body,
                        expiresAt: Date(timeIntervalSinceReferenceDate: event.second + project.bubbleLifetime))
        }
        ledger.prune(at: Date(timeIntervalSinceReferenceDate: elapsed))
        return Presentation(members: project.participants.map {
            PixelWorldMember(id: $0.id, nickname: $0.nickname, characterID: $0.characterID,
                             presence: .online, isTyping: typing == $0.id, isCurrentUser: false)
        }, bubbles: ledger.bubbles, delivered: delivered.count)
    }
}
#endif
