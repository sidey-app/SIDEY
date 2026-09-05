import Foundation

struct StorePreviewScenario: Equatable, Sendable {
    static let roomID = UUID(uuidString: "83DCA9FA-DFB8-4AEF-B851-9655195D41C1")!
    static let mokaID = UUID(uuidString: "D5F0D9BB-FBDA-4B10-AEF9-A7E2A4CFBD25")!
    static let dubuID = UUID(uuidString: "26E5237A-69A1-4EA7-868E-822C831069B6")!
    let productID: String
    let members: [PixelWorldMember]
    let bubbles: [ActiveBubble]
    let fixedTrackFractions: [UUID: CGFloat]
    let bubbleSequence: StorePreviewBubbleSequence?
    let throwSequence: StorePreviewThrowSequence?

    static func make(product: CommerceProduct) -> Self {
        switch product.kind {
        case .character:
            return Self(
                productID: product.id,
                members: [moka(characterID: product.characterID ?? PixelCharacterCatalog.pixelHamsterID)],
                bubbles: [],
                fixedTrackFractions: [:],
                bubbleSequence: nil,
                throwSequence: nil
            )
        case .bubble:
            let sequence = StorePreviewBubbleSequence(
                leftMemberID: mokaID,
                rightMemberID: dubuID,
                bubbleStyleID: product.catalogItemID
            )
            return Self(
                productID: product.id,
                members: [
                    moka(characterID: PixelCharacterCatalog.pixelHamsterID),
                    dubu(characterID: "pixel_cat")
                ],
                bubbles: [sequence.bubble(at: 0)],
                fixedTrackFractions: [:],
                bubbleSequence: sequence,
                throwSequence: nil
            )
        case .throwable:
            let members = [
                moka(characterID: PixelCharacterCatalog.pixelHamsterID),
                dubu(characterID: "pixel_cat")
            ]
            return Self(
                productID: product.id,
                members: members,
                bubbles: [],
                fixedTrackFractions: [mokaID: 0.22, dubuID: 0.78],
                bubbleSequence: nil,
                throwSequence: StorePreviewThrowSequence(
                    roomID: roomID,
                    leftMemberID: mokaID,
                    rightMemberID: dubuID,
                    throwableID: product.catalogItemID
                )
            )
        }
    }

    private static func moka(characterID: String) -> PixelWorldMember {
        PixelWorldMember(
            id: mokaID,
            nickname: "모카",
            characterID: characterID,
            presence: .online,
            isTyping: false,
            isCurrentUser: false
        )
    }

    private static func dubu(characterID: String) -> PixelWorldMember {
        PixelWorldMember(
            id: dubuID,
            nickname: "두부",
            characterID: characterID,
            presence: .online,
            isTyping: false,
            isCurrentUser: false
        )
    }
}

struct StorePreviewBubbleSequence: Equatable, Sendable {
    static let interval: TimeInterval = 2
    static let leftBody = "저메추좀 해줘"
    static let rightBody = "곱도리탕 어때?"
    private static let leftMessageID = UUID(uuidString: "08A6BBCF-45BD-45D6-A373-3056DE9A5CBA")!
    private static let rightMessageID = UUID(uuidString: "87793D0B-A870-4D96-930D-BE1465A1BB92")!

    let leftMemberID: UUID
    let rightMemberID: UUID
    let bubbleStyleID: String

    func scheduledOffset(for index: Int) -> TimeInterval {
        Double(max(0, index)) * Self.interval
    }

    func bubble(at index: Int) -> ActiveBubble {
        let usesLeftMember = index.isMultiple(of: 2)
        return ActiveBubble(
            senderID: usesLeftMember ? leftMemberID : rightMemberID,
            messageID: usesLeftMember ? Self.leftMessageID : Self.rightMessageID,
            body: usesLeftMember ? Self.leftBody : Self.rightBody,
            expiresAt: .distantFuture,
            bubbleStyleID: bubbleStyleID
        )
    }
}

struct StorePreviewThrowSequence: Equatable, Sendable {
    static let firstDelay: TimeInterval = 0.35
    static let repeatInterval: TimeInterval = 1

    let roomID: UUID
    let leftMemberID: UUID
    let rightMemberID: UUID
    let throwableID: String

    func scheduledOffset(for index: Int) -> TimeInterval {
        Self.firstDelay + Double(max(0, index)) * Self.repeatInterval
    }

    func event(at index: Int, id: UUID = UUID()) -> CharacterThrowEvent {
        let throwsLeftToRight = index.isMultiple(of: 2)
        let actorID = throwsLeftToRight ? leftMemberID : rightMemberID
        let targetID = throwsLeftToRight ? rightMemberID : leftMemberID
        let sourceCharacterID = throwsLeftToRight
            ? PixelCharacterCatalog.pixelHamsterID
            : "pixel_cat"
        return CharacterThrowEvent(
            id: id,
            roomID: roomID,
            actorUserID: actorID,
            targetUserID: targetID,
            sourceCharacterID: sourceCharacterID,
            throwableID: throwableID
        )
    }
}
