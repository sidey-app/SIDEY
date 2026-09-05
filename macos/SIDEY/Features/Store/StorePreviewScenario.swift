import Foundation

struct StorePreviewScenario: Equatable, Sendable {
    static let roomID = UUID(uuidString: "83DCA9FA-DFB8-4AEF-B851-9655195D41C1")!
    static let mokaID = UUID(uuidString: "D5F0D9BB-FBDA-4B10-AEF9-A7E2A4CFBD25")!
    static let dubuID = UUID(uuidString: "26E5237A-69A1-4EA7-868E-822C831069B6")!
    static let bubbleBody = "저메추좀 해줘"

    let productID: String
    let members: [PixelWorldMember]
    let bubbles: [ActiveBubble]
    let fixedTrackFractions: [UUID: CGFloat]
    let throwSequence: StorePreviewThrowSequence?

    static func make(product: CommerceProduct) -> Self {
        switch product.kind {
        case .character:
            return Self(
                productID: product.id,
                members: [moka(characterID: product.characterID ?? PixelCharacterCatalog.pixelHamsterID)],
                bubbles: [],
                fixedTrackFractions: [:],
                throwSequence: nil
            )
        case .bubble:
            return Self(
                productID: product.id,
                members: [moka(characterID: PixelCharacterCatalog.pixelHamsterID)],
                bubbles: [ActiveBubble(
                    senderID: mokaID,
                    messageID: UUID(uuidString: "08A6BBCF-45BD-45D6-A373-3056DE9A5CBA")!,
                    body: bubbleBody,
                    expiresAt: .distantFuture,
                    bubbleStyleID: product.catalogItemID
                )],
                fixedTrackFractions: [:],
                throwSequence: nil
            )
        case .throwable:
            let members = [
                moka(characterID: PixelCharacterCatalog.pixelHamsterID),
                PixelWorldMember(
                    id: dubuID,
                    nickname: "두부",
                    characterID: "pixel_cat",
                    presence: .online,
                    isTyping: false,
                    isCurrentUser: false
                )
            ]
            return Self(
                productID: product.id,
                members: members,
                bubbles: [],
                fixedTrackFractions: [mokaID: 0.22, dubuID: 0.78],
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
