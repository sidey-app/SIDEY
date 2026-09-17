import Foundation

struct BackendSnapshot: Equatable, Sendable {
    var profile: Profile?
    var rooms: [Room]
    var activeEntitlementKeys: Set<String> = []
}

struct BackendReconciliation: Equatable, Sendable {
    let snapshot: BackendSnapshot
    let activeRoomID: UUID?
    let activeMessages: [ChatMessage]
}

struct BackendConnectionStatus: Equatable, Sendable {
    let transportConnected: Bool
    let recoveryReconciled: Bool
    let activeRoomTransportConnected: Bool

    init(
        transportConnected: Bool,
        recoveryReconciled: Bool,
        activeRoomTransportConnected: Bool? = nil
    ) {
        self.transportConnected = transportConnected
        self.recoveryReconciled = recoveryReconciled
        self.activeRoomTransportConnected = activeRoomTransportConnected ?? transportConnected
    }

    var isReady: Bool {
        transportConnected && recoveryReconciled
    }
}

struct MessageHistoryCursor: Equatable, Sendable {
    let rawCreatedAt: String
    let id: UUID
}

struct MessageHistoryPage: Equatable, Sendable {
    let messages: [ChatMessage]
    let nextCursor: MessageHistoryCursor?
}

enum BackendEvent: Sendable {
    case authenticationRequired
    case snapshot(BackendSnapshot)
    case reconciliation(BackendReconciliation)
    case message(ChatMessage)
    case messageDeleted(roomID: UUID, messageID: UUID)
    case messagesInvalidated(roomID: UUID)
    case messagesReplaced(roomID: UUID, messages: [ChatMessage])
    case presence(roomID: UUID, userID: UUID, state: PresenceState)
    case typing(roomID: UUID, userID: UUID, active: Bool)
    case characterPulse(CharacterPulseEvent)
    case characterThrow(CharacterThrowEvent)
    case connection(BackendConnectionStatus)
    case technicalError(String)
}

struct CreatedRoom: Equatable, Sendable {
    let roomID: UUID
    let inviteCode: String
    let storedInKeychain: Bool
}

struct JoinedRoom: Equatable, Sendable {
    let roomID: UUID
    let storedInKeychain: Bool
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

struct DatabaseCommerceEntitlement: Codable, Sendable {
    let entitlementKey: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case entitlementKey = "entitlement_key"
    }
}

enum PostgresTimestampDecoder {
    private static let shape = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$"#
    )

    static func decode(_ value: String) throws -> Date {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let bytes = Array(value.utf8)
        guard shape.firstMatch(in: value, range: range)?.range == range,
              bytes.count >= 20,
              let year = integer(bytes, 0..<4),
              let month = integer(bytes, 5..<7),
              let day = integer(bytes, 8..<10),
              let hour = integer(bytes, 11..<13),
              let minute = integer(bytes, 14..<16),
              let second = integer(bytes, 17..<19)
        else {
            throw SideyBackendError.invalidTimestamp
        }

        var suffixIndex = 19
        var fractionalSeconds = 0.0
        if bytes[suffixIndex] == Character(".").asciiValue! {
            let fractionStart = suffixIndex + 1
            suffixIndex = fractionStart
            while suffixIndex < bytes.count,
                  bytes[suffixIndex] >= Character("0").asciiValue!,
                  bytes[suffixIndex] <= Character("9").asciiValue! {
                suffixIndex += 1
            }
            guard let fraction = integer(bytes, fractionStart..<suffixIndex) else {
                throw SideyBackendError.invalidTimestamp
            }
            fractionalSeconds = Double(fraction)
                / pow(10, Double(suffixIndex - fractionStart))
        }

        let offsetSeconds: TimeInterval
        if bytes[suffixIndex] == Character("Z").asciiValue! {
            offsetSeconds = 0
        } else {
            guard suffixIndex + 6 == bytes.count,
                  let offsetHour = integer(bytes, (suffixIndex + 1)..<(suffixIndex + 3)),
                  let offsetMinute = integer(bytes, (suffixIndex + 4)..<(suffixIndex + 6)),
                  offsetHour <= 23,
                  offsetMinute <= 59
            else {
                throw SideyBackendError.invalidTimestamp
            }
            let direction = bytes[suffixIndex] == Character("+").asciiValue! ? 1.0 : -1.0
            offsetSeconds = direction * TimeInterval((offsetHour * 60 + offsetMinute) * 60)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        guard let wholeSeconds = calendar.date(from: components) else {
            throw SideyBackendError.invalidTimestamp
        }
        let roundTrip = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: wholeSeconds
        )
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day,
              roundTrip.hour == hour,
              roundTrip.minute == minute,
              roundTrip.second == second
        else {
            throw SideyBackendError.invalidTimestamp
        }
        return wholeSeconds.addingTimeInterval(fractionalSeconds - offsetSeconds)
    }

    private static func integer(_ bytes: [UInt8], _ range: Range<Int>) -> Int? {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= bytes.count else {
            return nil
        }
        var result = 0
        for index in range {
            let byte = bytes[index]
            guard byte >= Character("0").asciiValue!,
                  byte <= Character("9").asciiValue!
            else { return nil }
            result = (result * 10) + Int(byte - Character("0").asciiValue!)
        }
        return result
    }
}

enum PostgresTimestampEncoder {
    static func encode(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: value)
    }
}

enum SideyBackendError: LocalizedError, Equatable {
    case invalidProfile
    case invalidRoomName
    case invalidInviteCode
    case inviteRateLimited
    case roomLimitReached
    case memberLimitReached
    case alreadyMember
    case profileRequired
    case ownerRequired
    case memberNotFound
    case membershipRequired
    case ownerCannotRemoveSelf
    case noActiveRoom
    case malformedResponse
    case invalidTimestamp
    case sessionRecoveryFailed
    case realtimeUnavailable
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile: "닉네임은 줄바꿈 없이 2~8자로 입력해 주세요."
        case .invalidRoomName: "그룹 이름은 줄바꿈 없이 1~20자로 입력해 주세요."
        case .invalidInviteCode: "초대 코드를 다시 확인해 주세요."
        case .inviteRateLimited: "초대 코드 시도가 너무 많습니다. 10분 뒤 다시 시도해 주세요."
        case .roomLimitReached: "한 사용자는 그룹을 최대 5개까지 사용할 수 있습니다."
        case .memberLimitReached: "이 그룹은 이미 \(ProductLimits.maximumRoomMembers)명으로 가득 찼습니다."
        case .alreadyMember: "이미 참여 중인 그룹입니다."
        case .profileRequired: "프로필을 먼저 저장해 주세요."
        case .ownerRequired: "방장만 이 작업을 할 수 있습니다."
        case .memberNotFound: "내보낼 멤버를 찾지 못했습니다."
        case .membershipRequired: "이 그룹의 멤버만 이 작업을 할 수 있습니다."
        case .ownerCannotRemoveSelf: "방장 본인은 내보낼 수 없습니다."
        case .noActiveRoom: "메시지를 보낼 그룹이 없습니다."
        case .malformedResponse: "서버 응답 형식을 해석하지 못했습니다."
        case .invalidTimestamp: "서버 메시지 시각을 해석하지 못했습니다."
        case .sessionRecoveryFailed: "기존 로그인 세션을 복구하지 못했습니다. 새 계정은 만들지 않았으니 다시 로그인하거나 지원을 요청해 주세요."
        case .realtimeUnavailable: "실시간 연결이 준비되지 않았습니다."
        case .remote(let message): Self.remoteDescription(message)
        }
    }

    private static func remoteDescription(_ code: String) -> String {
        switch code {
        case "invalid_message": return "메시지는 200자·3줄 이하로 입력해 주세요."
        case "message_rate_limited", "rate_limited", "transient_rate_limited": return "요청이 너무 빠릅니다. 잠시 뒤 다시 시도해 주세요."
        case "message_id_conflict": return "이미 전송한 메시지와 내용이 다릅니다. 전송 내역을 확인해 주세요."
        case "database_unavailable", "internal_error", "server_restarting": return "서버 연결이 잠시 불안정합니다. 잠시 뒤 다시 시도해 주세요."
        case "session_changed": return "로그인 상태가 변경되었습니다. 현재 계정에서 다시 시도해 주세요."
        case "identity_proof_mismatch": return "현재 계정과 다른 로그인 계정입니다. 연결된 계정으로 다시 인증해 주세요."
        case "identity_already_linked", "provider_already_linked": return "다른 SIDEY 계정에 연결된 로그인 계정입니다."
        case "last_identity", "last_identity_required", "last_provider_identity": return "마지막 로그인 수단은 해제할 수 없습니다. 다른 계정을 먼저 연결해 주세요."
        case "identity_not_linked", "identity_missing": return "이 로그인 수단은 현재 계정에 연결되어 있지 않습니다."
        case "auth_challenge_invalid", "invalid_provider_proof", "provider_identity_rejected", "nonce_mismatch": return "로그인 확인이 만료되었거나 올바르지 않습니다. 다시 로그인해 주세요."
        case "apple_reauthentication_required": return "계정을 삭제하려면 Apple로 다시 인증해 주세요."
        case "google_not_configured", "apple_not_configured", "identity_verifier_unconfigured", "provider_unavailable", "provider_verification_unavailable": return "로그인 제공업체에 연결하지 못했습니다. 잠시 뒤 다시 시도해 주세요."
        case "tree_revision_conflict", "revision_conflict": return "다른 기기에서 설정이 변경되었습니다. 최신 상태를 확인한 뒤 다시 시도해 주세요."
        case "entitlement_required", "cosmetic_not_owned", "character_not_owned": return "보유한 상품만 사용할 수 있습니다. 구매 상태를 새로 확인해 주세요."
        case "room_missing": return "그룹이 삭제되었거나 더 이상 접근할 수 없습니다."
        case "message_missing": return "메시지를 찾을 수 없습니다. 보관 기간이 지났을 수 있습니다."
        case "order_missing": return "주문을 찾을 수 없습니다. 구매 내역을 확인해 주세요."
        case "payment_provider_unavailable", "portone_unconfigured", "apple_verifier_unconfigured": return "결제 확인 서비스에 연결하지 못했습니다. 잠시 뒤 다시 시도해 주세요."
        default:
            return code.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") })
                ? "요청을 완료하지 못했습니다. 잠시 뒤 다시 시도해 주세요." : code
        }
    }

    static func business(code: String) -> Self {
        switch code {
        case "invalid_invite_code": .invalidInviteCode
        case "invite_rate_limited": .inviteRateLimited
        case "room_limit_reached": .roomLimitReached
        case "member_limit_reached": .memberLimitReached
        case "already_a_member": .alreadyMember
        case "profile_required": .profileRequired
        case "owner_required": .ownerRequired
        case "member_not_found": .memberNotFound
        case "membership_required": .membershipRequired
        case "owner_must_leave": .ownerCannotRemoveSelf
        case "invalid_room_name": .invalidRoomName
        default: .remote(code)
        }
    }

}
