import Foundation

struct BackendSnapshot: Equatable, Sendable {
    var profile: Profile?
    var rooms: [Room]
}

enum BackendEvent: Sendable {
    case snapshot(BackendSnapshot)
    case message(ChatMessage)
    case presence(roomID: UUID, userID: UUID, state: PresenceState)
    case typing(roomID: UUID, userID: UUID, active: Bool)
    case connection(Bool)
}

struct CreatedRoom: Equatable, Sendable {
    let roomID: UUID
    let inviteCode: String
}

enum BackendConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case online
    case failed(String)

    var label: String {
        switch self {
        case .idle: "대기 중"
        case .connecting: "연결 중"
        case .online: "연결됨"
        case .failed: "연결 오류"
        }
    }
}

struct DatabaseProfile: Codable, Sendable {
    let id: UUID
    let nickname: String
    let characterID: String

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case characterID = "character_id"
    }

    var domain: Profile {
        Profile(
            id: id,
            nickname: nickname,
            characterID: PixelCharacterCatalog.canonicalID(for: characterID)
        )
    }
}

struct DatabaseRoom: Codable, Sendable {
    let id: UUID
    let name: String
    let ownerID: UUID
    let inviteCodeHint: String
    let inviteVersion: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id"
        case inviteCodeHint = "invite_code_hint"
        case inviteVersion = "invite_version"
        case createdAt = "created_at"
    }
}

struct DatabaseMembership: Codable, Sendable {
    let roomID: UUID
    let userID: UUID
    let joinedAt: String

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
    }
}

struct DatabaseMessage: Codable, Sendable {
    let id: UUID
    let roomID: UUID
    let senderID: UUID
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case roomID = "room_id"
        case senderID = "sender_id"
        case createdAt = "created_at"
    }

    var domain: ChatMessage {
        ChatMessage(
            id: id,
            roomID: roomID,
            senderID: senderID,
            body: body,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? .now
        )
    }
}

struct UpsertProfileParameters: Encodable, Sendable {
    let nickname: String
    let characterID: String

    enum CodingKeys: String, CodingKey {
        case nickname = "p_nickname"
        case characterID = "p_character_id"
    }
}

struct CreateRoomParameters: Encodable, Sendable {
    let name: String
    enum CodingKeys: String, CodingKey { case name = "p_name" }
}

struct CreateRoomRow: Decodable, Sendable {
    let roomID: UUID
    let inviteCode: String
    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case inviteCode = "invite_code"
    }
}

struct JoinRoomParameters: Encodable, Sendable {
    let inviteCode: String
    enum CodingKeys: String, CodingKey { case inviteCode = "p_invite_code" }
}

struct JoinRoomRow: Decodable, Sendable {
    let roomID: UUID?
    let errorCode: String?
    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case errorCode = "error_code"
    }
}

struct LeaveRoomParameters: Encodable, Sendable {
    let roomID: UUID
    enum CodingKeys: String, CodingKey { case roomID = "p_room_id" }
}

struct SendMessageParameters: Encodable, Sendable {
    let id: UUID
    let roomID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case roomID = "p_room_id"
        case body = "p_body"
    }
}

struct PresencePayload: Codable, Sendable {
    let userID: UUID
    let state: PresenceState
    let onlineAt: String

    enum CodingKeys: String, CodingKey {
        case state
        case userID = "user_id"
        case onlineAt = "online_at"
    }
}

struct TypingPayload: Codable, Sendable {
    let userID: UUID
    enum CodingKeys: String, CodingKey { case userID = "user_id" }
}

enum SideyBackendError: LocalizedError, Equatable {
    case invalidProfile
    case invalidRoomName
    case invalidInviteCode
    case roomLimitReached
    case memberLimitReached
    case alreadyMember
    case profileRequired
    case noActiveRoom
    case malformedResponse
    case sessionRecoveryFailed
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile: "닉네임은 줄바꿈 없이 2~8자로 입력해줘"
        case .invalidRoomName: "그룹 이름은 줄바꿈 없이 1~20자로 입력해줘"
        case .invalidInviteCode: "초대 코드를 다시 확인해줘"
        case .roomLimitReached: "한 사용자는 그룹을 최대 5개까지 사용할 수 있음"
        case .memberLimitReached: "이 그룹은 이미 5명으로 가득 참"
        case .alreadyMember: "이미 참여 중인 그룹임"
        case .profileRequired: "프로필을 먼저 저장해야 함"
        case .noActiveRoom: "메시지를 보낼 그룹이 없음"
        case .malformedResponse: "서버 응답 형식을 해석하지 못했음"
        case .sessionRecoveryFailed: "기존 로그인 세션을 복구하지 못했음. 새 계정은 만들지 않았으니 다시 로그인하거나 지원을 요청해줘"
        case .remote(let message): message
        }
    }

    static func business(code: String) -> Self {
        switch code {
        case "invalid_invite_code": .invalidInviteCode
        case "room_limit_reached": .roomLimitReached
        case "member_limit_reached": .memberLimitReached
        case "already_a_member": .alreadyMember
        case "profile_required": .profileRequired
        default: .remote(code)
        }
    }
}
