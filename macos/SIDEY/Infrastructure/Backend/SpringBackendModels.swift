import Foundation

struct SpringProfile: Decodable, Sendable {
    let id: UUID
    let nickname: String
    let characterId: String
    let equippedBubbleStyleId: String?
    let equippedThrowableId: String?
    let treeMovementPaused: Bool
    let treeMovementRevision: Int64
    var domain: Profile {
        Profile(id: id, nickname: nickname, characterID: PixelCharacterCatalog.canonicalID(for: characterId),
            equippedBubbleStyleID: equippedBubbleStyleId, equippedThrowableID: equippedThrowableId,
            treeMovementPaused: treeMovementPaused, treeMovementRevision: treeMovementRevision)
    }
}

struct SpringRoom: Decodable, Sendable {
    struct Member: Decodable, Sendable { let userId: UUID; let profile: SpringProfile? }
    let id: UUID
    let name: String
    let ownerId: UUID
    let inviteCodeHint: String
    let inviteVersion: Int
    let members: [Member]
    var domain: Room {
        Room(id: id, name: name, ownerID: ownerId, members: members.map {
            RoomMember(userID: $0.userId, nickname: $0.profile?.nickname ?? "친구",
                characterID: $0.profile?.characterId ?? "pixel_hamster", presence: .offline,
                equippedBubbleStyleID: $0.profile?.equippedBubbleStyleId,
                treeMovementPaused: $0.profile?.treeMovementPaused ?? false,
                treeMovementRevision: $0.profile?.treeMovementRevision)
        }, inviteCodeHint: inviteCodeHint, inviteVersion: inviteVersion)
    }
}
struct SpringCreatedRoom: Decodable, Sendable { let room: SpringRoom; let inviteCode: String }
struct SpringCheckout: Decodable, Sendable { let orderId: UUID; let checkoutUrl: URL }
struct SpringOrder: Decodable, Sendable { let id: UUID; let status: String }

struct SpringProduct: Decodable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let productKind: CommerceProductKind
    let catalogItemId: String
    let characterId: String?
    let entitlementKey: String
    let sortOrder: Int
    let amountKrw: Int
    let currency: String
    let taxInclusive: Bool
    enum CodingKeys: String, CodingKey {
        case id, currency
        case description = "product_description"
        case displayName = "display_name", productKind = "product_kind", catalogItemId = "catalog_item_id"
        case characterId = "character_id", entitlementKey = "entitlement_key", sortOrder = "sort_order"
        case amountKrw = "amount_krw", taxInclusive = "tax_inclusive"
    }
    var domain: CommerceProduct {
        CommerceProduct(id: id, displayName: displayName, description: description, kind: productKind,
            catalogItemID: catalogItemId, characterID: characterId, entitlementKey: entitlementKey,
            sortOrder: sortOrder, amountKRW: amountKrw, currency: currency, taxInclusive: taxInclusive)
    }
}

struct SpringCursor: Codable, Equatable, Sendable {
    let createdAt: String
    let id: UUID
}
struct SpringMessage: Decodable, Sendable {
    let id: UUID
    let roomId: UUID
    let senderId: UUID
    let body: String
    let bubbleStyleId: String?
    let createdAt: String
    var domain: ChatMessage {
        get throws {
            ChatMessage(id: id, roomID: roomId, senderID: senderId, body: body,
                createdAt: try PostgresTimestampDecoder.decode(createdAt), bubbleStyleID: bubbleStyleId)
        }
    }
}
struct SpringMessagePage: Decodable, Sendable {
    let messages: [SpringMessage]
    let nextCursor: SpringCursor?
    var domain: MessageHistoryPage {
        get throws {
            MessageHistoryPage(messages: try messages.map { try $0.domain },
                nextCursor: nextCursor.map { MessageHistoryCursor(rawCreatedAt: $0.createdAt, id: $0.id) })
        }
    }
}
struct SpringSubscribeAck: Decodable, Sendable { let recoveryThrough: SpringCursor? }
struct SpringMessageAck: Decodable, Sendable { let message: SpringMessage }
struct SpringEvent: Decodable, Sendable {
    let type: String
    let code: String?
    let roomId: UUID?
    let userId: UUID?
    let message: SpringMessage?
    let members: [String: String]?
    let active: Bool?
    let eventId: UUID?
    let targetUserId: UUID?
    let sourceCharacterId: String?
    let throwableId: String?
}

/// A bounded view cache, not a durable store. Evicted history remains available in
/// REST. Confirmed cursor only advances after an entire server checkpoint is read.
struct SpringMessageLedger: Sendable {
    private var rows: [UUID: ChatMessage] = [:]
    private(set) var confirmedCursor: SpringCursor?
    private let capacity: Int
    init(capacity: Int = 1_000) { self.capacity = max(1, capacity) }
    var messages: [ChatMessage] {
        rows.values.sorted { a, b in
            a.createdAt == b.createdAt ? a.id.uuidString < b.id.uuidString : a.createdAt < b.createdAt
        }
    }
    mutating func merge(_ value: SpringMessage) throws -> Bool {
        let message = try value.domain
        let inserted = rows.updateValue(message, forKey: message.id) == nil
        if rows.count > capacity {
            for old in messages.prefix(rows.count - capacity) { rows.removeValue(forKey: old.id) }
        }
        return inserted
    }
    mutating func confirmRecovery(through: SpringCursor) { confirmedCursor = through }
    mutating func prune(now: Date = Date()) { rows = rows.filter { $0.value.createdAt > now.addingTimeInterval(-3 * 86_400) } }
}

/// Unknown catalog additions can wait for a client update. Known product identity
/// must match bundled assets; availability and ownership come from separate APIs.
enum SpringCatalog {
    enum ValidationError: Error, Equatable {
        case duplicateProduct(String)
        case mismatchedProduct(String)
    }
    static func validatedProducts(_ products: [SpringProduct]) throws -> [SpringProduct] {
        var seen: Set<String> = []
        return try products.compactMap { product -> SpringProduct? in
            guard let registered = CommerceCatalog.product(id: product.id) else { return nil }
            guard seen.insert(product.id).inserted else { throw ValidationError.duplicateProduct(product.id) }
            guard product.productKind == registered.kind,
                  product.catalogItemId == registered.catalogItemID,
                  product.characterId == registered.characterID,
                  product.entitlementKey == registered.entitlementKey,
                  product.sortOrder == registered.sortOrder,
                  product.characterId.map({ PixelCharacterCatalog.definition(for: $0).id == $0 }) ?? true else {
                throw ValidationError.mismatchedProduct(product.id)
            }
            return product
        }.sorted { $0.sortOrder < $1.sortOrder }
    }
}
