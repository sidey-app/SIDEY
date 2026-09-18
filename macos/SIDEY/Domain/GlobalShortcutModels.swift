import Carbon.HIToolbox
import Foundation

enum GlobalShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case toggleComposer
    case toggleOverlay
    case toggleQuietMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleComposer: "메시지 작성 창 열기·닫기"
        case .toggleOverlay: "오버레이 보이기·숨기기"
        case .toggleQuietMode: "조용히 모드 켜기·끄기"
        }
    }

    var summary: String {
        switch self {
        case .toggleComposer: "메시지 입력창을 열고, 열려 있으면 작성 중인 내용을 그대로 두고 닫습니다."
        case .toggleOverlay: "픽셀 월드를 화면에 표시하거나 숨깁니다."
        case .toggleQuietMode: "메시지 본문 말풍선을 숨기는 조용히 모드를 켜거나 끕니다."
        }
    }
}

/// A short confirmation for a shortcut whose result would otherwise not be visible.
struct GlobalShortcutNotice: Equatable, Sendable {
    let symbolName: String
    let title: String
    let detail: String

    static let quietModeOn = GlobalShortcutNotice(
        symbolName: "moon.fill",
        title: "조용히 모드 켜짐",
        detail: "새 메시지 말풍선을 숨깁니다."
    )
    static let quietModeOff = GlobalShortcutNotice(
        symbolName: "moon",
        title: "조용히 모드 꺼짐",
        detail: "새 메시지 말풍선을 다시 표시합니다."
    )
    static let groupRequired = GlobalShortcutNotice(
        symbolName: "person.2",
        title: "보낼 그룹이 없습니다",
        detail: "그룹을 만들거나 참가하면 보낼 수 있습니다."
    )
    static let waitingForGroups = GlobalShortcutNotice(
        symbolName: "person.2",
        title: "그룹 정보를 아직 불러오지 못했습니다",
        detail: "그룹 정보를 불러온 뒤 보낼 수 있습니다."
    )

    var accessibilityAnnouncement: String { "\(title). \(detail)" }
}

/// Carbon hot-key modifier masks, stored as-is so a saved value maps directly to registration.
struct GlobalShortcutModifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt32

    static let command = GlobalShortcutModifiers(rawValue: UInt32(cmdKey))
    static let shift = GlobalShortcutModifiers(rawValue: UInt32(shiftKey))
    static let option = GlobalShortcutModifiers(rawValue: UInt32(optionKey))
    static let control = GlobalShortcutModifiers(rawValue: UInt32(controlKey))
    static let supported: GlobalShortcutModifiers = [.command, .shift, .option, .control]
}

/// A physical key plus modifiers. Key names follow the ANSI layout because the
/// active input source (for example Korean) does not change which key is registered.
struct GlobalShortcut: Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: GlobalShortcutModifiers

    static let escapeKeyCode = UInt32(kVK_Escape)

    private static let reservedBySystem: Set<GlobalShortcut> = {
        let space = UInt32(kVK_Space)
        return [
            GlobalShortcut(keyCode: space, modifiers: [.command]),
            GlobalShortcut(keyCode: space, modifiers: [.option, .command]),
            GlobalShortcut(keyCode: space, modifiers: [.control, .command]),
            GlobalShortcut(keyCode: space, modifiers: [.control]),
            GlobalShortcut(keyCode: space, modifiers: [.control, .option]),
            GlobalShortcut(keyCode: space, modifiers: [.shift, .command]),
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: [.shift, .command]),
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: [.shift, .command]),
            GlobalShortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: [.shift, .command])
        ]
    }()

    var displayString: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + (keyName ?? "?")
    }

    /// Rules that do not depend on other assignments. Stored values must pass them as well.
    var validationRejection: GlobalShortcutRejection? {
        if Self.reservedBySystem.contains(self) { return .reservedBySystem }
        guard modifiers.isSubset(of: .supported),
              modifiers.rawValue.nonzeroBitCount >= 2,
              !modifiers.isDisjoint(with: [.command, .control])
        else { return .modifiersRequired }
        guard keyName != nil else { return .unsupportedKey }
        return nil
    }

    func rejection(
        for action: GlobalShortcutAction,
        among assignments: GlobalShortcutAssignments
    ) -> GlobalShortcutRejection? {
        if let rejection = validationRejection { return rejection }
        if let owner = GlobalShortcutAction.allCases.first(where: { $0 != action && assignments[$0] == self }) {
            return .assigned(to: owner)
        }
        return nil
    }

    /// Letters, digits, Space and F1-F12 only.
    private var keyName: String? {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        default: return nil
        }
    }
}

// Declared in an extension so the memberwise initializer stays available.
extension GlobalShortcut: Codable {
    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try values.decode(UInt32.self, forKey: .keyCode)
        let rawModifiers = try values.decode(UInt32.self, forKey: .modifiers)
        modifiers = GlobalShortcutModifiers(rawValue: rawModifiers)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(keyCode, forKey: .keyCode)
        try values.encode(modifiers.rawValue, forKey: .modifiers)
    }
}

enum GlobalShortcutRejection: Equatable, Sendable {
    case reservedBySystem
    case modifiersRequired
    case unsupportedKey
    case assigned(to: GlobalShortcutAction)
    case unavailable

    var message: String {
        switch self {
        case .reservedBySystem: "macOS가 이미 쓰는 조합이라 지정할 수 없어요."
        case .modifiersRequired: "⌘나 ⌃를 포함해 보조 키를 두 개 이상 함께 눌러 주세요."
        case .unsupportedKey: "영문자, 숫자, Space, F1~F12 중 하나와 함께 눌러 주세요."
        case .assigned(let action): "‘\(action.title)’에 이미 지정된 조합이에요."
        case .unavailable: "다른 앱이 이미 사용 중이라 등록할 수 없어요."
        }
    }
}

enum GlobalShortcutStatus: Equatable, Sendable {
    /// The saved combination is registered with macOS.
    case active
    /// The saved combination is kept, but macOS refused to register it.
    case unavailable
    /// The last recording attempt was refused and the previous combination stays.
    case rejected(GlobalShortcutRejection)
}

/// Per-device assignments. Every action starts unassigned.
struct GlobalShortcutAssignments: Codable, Equatable, Sendable {
    var toggleComposer: GlobalShortcut?
    var toggleOverlay: GlobalShortcut?
    var toggleQuietMode: GlobalShortcut?

    enum CodingKeys: String, CodingKey {
        case toggleComposer
        case toggleOverlay
        case toggleQuietMode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // A damaged, no-longer-valid or duplicated value leaves only that action unassigned.
        for action in GlobalShortcutAction.allCases {
            guard let shortcut = try? values.decodeIfPresent(GlobalShortcut.self, forKey: Self.codingKey(for: action)),
                  shortcut.rejection(for: action, among: self) == nil
            else { continue }
            self[action] = shortcut
        }
    }

    subscript(action: GlobalShortcutAction) -> GlobalShortcut? {
        get {
            switch action {
            case .toggleComposer: toggleComposer
            case .toggleOverlay: toggleOverlay
            case .toggleQuietMode: toggleQuietMode
            }
        }
        set {
            switch action {
            case .toggleComposer: toggleComposer = newValue
            case .toggleOverlay: toggleOverlay = newValue
            case .toggleQuietMode: toggleQuietMode = newValue
            }
        }
    }

    private static func codingKey(for action: GlobalShortcutAction) -> CodingKeys {
        switch action {
        case .toggleComposer: .toggleComposer
        case .toggleOverlay: .toggleOverlay
        case .toggleQuietMode: .toggleQuietMode
        }
    }
}
