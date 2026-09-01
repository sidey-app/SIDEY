import AppKit
import SpriteKit

enum PresenceIndicatorTone: Equatable {
    case green
    case orange
    case red
    case gray

    static func tone(for presence: PresenceState) -> Self {
        switch presence {
        case .online, .typing: .green
        case .away: .orange
        case .offline: .red
        case .reconnecting: .gray
        }
    }

    var color: NSColor {
        switch self {
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        case .gray: .systemGray
        }
    }
}

enum PixelWorldRendererPolicy {
    static let preferredFramesPerSecond = 30

    @MainActor static func apply(to view: SKView) {
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.isAsynchronous = true
    }
}

struct PixelCharacterVisualState: Equatable {
    let motion: PixelCharacterMotion
    let alpha: CGFloat
    let colorBlendFactor: CGFloat
    let showsDozeLabel: Bool
}

enum PixelDozeLabelStyle {
    static let text = "Zzz"
    static let fontSize: CGFloat = 14
    static let outlineWidth: CGFloat = 2
    static let restingAlpha: CGFloat = 0.55
    static let floatingDistance: CGFloat = 3
    static let fillColor = NSColor.systemOrange
    static let outlineColor = NSColor(srgbRed: 0.08, green: 0.07, blue: 0.06, alpha: 0.92)

    static let outlineOffsets: [CGPoint] = (0..<12).map { index in
        let angle = CGFloat(index) * .pi * 2 / 12
        return CGPoint(
            x: cos(angle) * outlineWidth,
            y: sin(angle) * outlineWidth
        )
    }
}

enum PixelCharacterPulseStyle {
    static let peakScale: CGFloat = 7
    static let growDuration: TimeInterval = 0.20
    static let settleDuration: TimeInterval = 0.60
    static let totalDuration = growDuration + settleDuration
}

private struct CharacterPulseKey: Hashable {
    let roomID: UUID
    let userID: UUID
}

final class PixelWorldScene: SKScene {
    private var characterNodes: [UUID: PixelCharacterNode] = [:]
    private var agents: [UUID: PixelMovementAgent] = [:]
    private var members: [UUID: PixelWorldMember] = [:]
    private var activeBubbles: [UUID: ActiveBubble] = [:]
    private var lastPulseEventIDs: [CharacterPulseKey: UUID] = [:]
    private var currentRoomID: UUID?
    private var installationSeed: UInt64 = 0
    private var edge: OverlayEdge = .bottom
    private var activityFrame: CGRect?
    private var composerVisible = false
    private var lastUpdateTime: TimeInterval?
    private var lastHotspotReportTime: TimeInterval = 0
    private var lastHotspotFrame: CGRect?
    private var onCurrentUserFrameChanged: ((CGRect?) -> Void)?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        let geometry = trackGeometry
        let needsInitialLayout = (oldSize.width <= 1 || oldSize.height <= 1)
            && size.width > 1 && size.height > 1
        for id in Array(agents.keys) {
            guard var agent = agents[id] else { continue }
            if needsInitialLayout {
                agent.trackPosition = stableTrackPosition(roomID: currentRoomID, userID: id)
                agent.target = stableTrackPosition(roomID: currentRoomID, userID: id, salt: 1)
            } else {
                agent.trackPosition = geometry.clamped(agent.trackPosition)
                agent.target = geometry.clamped(agent.target)
            }
            agents[id] = agent
            characterNodes[id]?.position = geometry.point(for: agent.trackPosition)
        }
        reportCurrentUserFrame(force: true)
    }

    func apply(
        roomID: UUID?,
        members requestedMembers: [PixelWorldMember],
        bubbles: [ActiveBubble],
        edge: OverlayEdge,
        activityFrame: CGRect? = nil,
        installationSeed: UInt64,
        composerVisible: Bool = false,
        characterPulse: CharacterPulseEvent? = nil,
        onCurrentUserFrameChanged: ((CGRect?) -> Void)? = nil
    ) {
        self.onCurrentUserFrameChanged = onCurrentUserFrameChanged
        let roomChanged = roomID != currentRoomID
        currentRoomID = roomID
        self.installationSeed = installationSeed
        self.edge = edge
        let activityFrameChanged = self.activityFrame != activityFrame
        self.activityFrame = activityFrame
        self.composerVisible = composerVisible
        if roomChanged {
            characterNodes.values.forEach { $0.removeFromParent() }
            characterNodes.removeAll()
            agents.removeAll()
            lastHotspotFrame = nil
        }

        let requestedByID = Dictionary(uniqueKeysWithValues: requestedMembers.map { ($0.id, $0) })
        let removedIDs = Set(characterNodes.keys).subtracting(requestedByID.keys)
        for id in removedIDs {
            characterNodes.removeValue(forKey: id)?.removeFromParent()
            agents.removeValue(forKey: id)
        }

        members = requestedByID
        activeBubbles = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.senderID, $0) })
        let geometry = trackGeometry
        for member in requestedMembers {
            let node: PixelCharacterNode
            if let existing = characterNodes[member.id] {
                node = existing
            } else {
                node = PixelCharacterNode(memberID: member.id, characterID: member.characterID)
                characterNodes[member.id] = node
                addChild(node)
                let initial = stableTrackPosition(roomID: roomID, userID: member.id)
                let target = stableTrackPosition(roomID: roomID, userID: member.id, salt: 1)
                agents[member.id] = PixelMovementAgent(
                    id: member.id,
                    trackPosition: initial,
                    target: target,
                    idleRemaining: stableUnit(roomID: roomID, userID: member.id, salt: 2) * 1.5
                )
                node.position = geometry.point(for: initial)
            }
            let tangent = agents[member.id]?.trackPosition ?? geometry.trackRange.lowerBound
            node.apply(
                member: member,
                bubble: activeBubbles[member.id],
                edge: edge,
                tangentPosition: tangent,
                tangentLength: geometry.tangentLength
            )
        }
        if activityFrameChanged {
            let geometry = trackGeometry
            for id in Array(agents.keys) {
                guard var agent = agents[id] else { continue }
                agent.trackPosition = geometry.clamped(agent.trackPosition)
                agent.target = geometry.clamped(agent.target)
                agents[id] = agent
                characterNodes[id]?.position = geometry.point(for: agent.trackPosition)
            }
        }
        if let characterPulse,
           characterPulse.roomID == roomID,
           let node = characterNodes[characterPulse.userID] {
            let key = CharacterPulseKey(roomID: characterPulse.roomID, userID: characterPulse.userID)
            if lastPulseEventIDs[key] != characterPulse.id {
                lastPulseEventIDs[key] = characterPulse.id
                node.playPulse()
            }
        }
        reportCurrentUserFrame(force: true)
    }

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = lastUpdateTime.map { currentTime - $0 } ?? (1.0 / 30.0)
        lastUpdateTime = currentTime
        let stoppedIDs = PixelMovementPolicy.stoppedMemberIDs(in: members.values)
        let geometry = trackGeometry
        var orderedAgents = agents.values.sorted { $0.id.uuidString < $1.id.uuidString }
        PixelMovementSimulation.step(
            agents: &orderedAgents,
            deltaTime: deltaTime,
            geometry: geometry,
            avoidanceRects: composerAvoidanceRects,
            stoppedIDs: stoppedIDs,
            messageBubbleTangentRanges: messageBubbleTangentRanges
        )

        for var agent in orderedAgents {
            guard let node = characterNodes[agent.id], let member = members[agent.id] else { continue }
            if !stoppedIDs.contains(agent.id), abs(agent.trackPosition - agent.target) < 3 {
                agent.idleRemaining = 0.8 + stableUnit(
                    roomID: currentRoomID,
                    userID: agent.id,
                    salt: UInt64(currentTime.rounded(.down)) &+ 17
                ) * 2.2
                agent.target = randomTarget(for: agent.id, time: currentTime)
            }
            agents[agent.id] = agent
            node.position = geometry.point(for: agent.trackPosition)
            let moving = abs(agent.velocity) > 2 && agent.idleRemaining <= 0 && !stoppedIDs.contains(agent.id)
            node.updateMotion(member: member, moving: moving)
            node.updatePresentationLayout(
                tangentPosition: agent.trackPosition,
                tangentLength: geometry.tangentLength,
                edge: edge
            )
        }
        if currentTime - lastHotspotReportTime >= 1.0 / 15.0 {
            lastHotspotReportTime = currentTime
            reportCurrentUserFrame(force: false)
        }
    }

    var nodeIDs: Set<UUID> { Set(characterNodes.keys) }
    var agentStates: [PixelMovementAgent] { agents.values.sorted { $0.id.uuidString < $1.id.uuidString } }
    var trackGeometry: EdgeTrackGeometry {
        EdgeTrackGeometry(bounds: effectiveActivityFrame, edge: edge)
    }
    var messageBubbleTangentRanges: [UUID: ClosedRange<CGFloat>] {
        let geometry = trackGeometry
        return activeBubbles.reduce(into: [:]) { ranges, entry in
            guard let agent = agents[entry.key], members[entry.key] != nil else { return }
            let layout = PixelBubbleLayout.make(
                text: entry.value.body,
                isTyping: false,
                tangentPosition: agent.trackPosition,
                tangentLength: geometry.tangentLength,
                edge: edge
            )
            ranges[entry.key] = layout.bodyTangentRange(
                at: agent.trackPosition,
                edge: edge
            )
        }
    }

    func renderedCharacterID(for memberID: UUID) -> String? {
        characterNodes[memberID]?.characterID
    }

    func renderedBubbleBody(for memberID: UUID) -> String? {
        characterNodes[memberID]?.bubbleBody
    }

    func renderedBubbleIsTyping(for memberID: UUID) -> Bool {
        characterNodes[memberID]?.bubbleIsTyping ?? false
    }

    func renderedVisualState(for memberID: UUID) -> PixelCharacterVisualState? {
        characterNodes[memberID]?.visualState
    }

    func renderedDozeText(for memberID: UUID) -> String? {
        characterNodes[memberID]?.dozeText
    }

    func hasRenderedDozeActions(for memberID: UUID) -> Bool {
        characterNodes[memberID]?.hasDozeActions ?? false
    }

    func renderedPulseCount(for memberID: UUID) -> Int {
        characterNodes[memberID]?.pulsePlayCount ?? 0
    }

    private var composerAvoidanceRects: [CGRect] {
        PixelWorldAvoidanceLayout.composerRects(
            activityFrame: effectiveActivityFrame,
            edge: edge,
            composerVisible: composerVisible
        )
    }

    private var effectiveActivityFrame: CGRect {
        guard let activityFrame,
              activityFrame.width > 0,
              activityFrame.height > 0
        else { return frame }
        return activityFrame
    }

    private func stableTrackPosition(roomID: UUID?, userID: UUID, salt: UInt64 = 0) -> CGFloat {
        let range = trackGeometry.trackRange
        return range.lowerBound + (range.upperBound - range.lowerBound)
            * stableUnit(roomID: roomID, userID: userID, salt: salt)
    }

    private func randomTarget(for userID: UUID, time: TimeInterval) -> CGFloat {
        stableTrackPosition(
            roomID: currentRoomID,
            userID: userID,
            salt: UInt64(max(0, time * 10)) &+ 0xD1B54A32D192ED03
        )
    }

    private func stableUnit(roomID: UUID?, userID: UUID, salt: UInt64) -> CGFloat {
        var hash = installationSeed ^ salt ^ 0xcbf29ce484222325
        for byte in uuidBytes(roomID) + uuidBytes(userID) {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        hash ^= hash >> 30
        hash &*= 0xbf58476d1ce4e5b9
        hash ^= hash >> 27
        hash &*= 0x94d049bb133111eb
        hash ^= hash >> 31
        return CGFloat(hash & 0x00FF_FFFF) / CGFloat(0x0100_0000)
    }

    private func uuidBytes(_ id: UUID?) -> [UInt8] {
        guard var value = id?.uuid else { return Array(repeating: 0, count: 16) }
        return withUnsafeBytes(of: &value) { Array($0) }
    }

    private func reportCurrentUserFrame(force: Bool) {
        guard let member = members.values.first(where: \.isCurrentUser),
              let node = characterNodes[member.id]
        else {
            if lastHotspotFrame != nil || force {
                lastHotspotFrame = nil
                onCurrentUserFrameChanged?(nil)
            }
            return
        }
        let frame = CGRect(
            x: node.position.x - EdgeTrackGeometry.hotspotPointSize / 2,
            y: node.position.y - EdgeTrackGeometry.hotspotPointSize / 2,
            width: EdgeTrackGeometry.hotspotPointSize,
            height: EdgeTrackGeometry.hotspotPointSize
        )
        let moved = lastHotspotFrame.map {
            hypot($0.midX - frame.midX, $0.midY - frame.midY) >= 1
        } ?? true
        guard force || moved else { return }
        lastHotspotFrame = frame
        onCurrentUserFrameChanged?(frame)
    }
}

enum PixelNameplateLayout {
    static let verticalPosition: CGFloat = 32
    static let statusDotRadius: CGFloat = 3
    static let spacing: CGFloat = 5
    static let horizontalPadding: CGFloat = 4
    static let verticalPadding: CGFloat = 2
    static let cornerRadius: CGFloat = 6
    static let backgroundColor = NSColor(srgbRed: 0.02, green: 0.025, blue: 0.035, alpha: 0.62)

    static func statusDotPosition(nicknameFrame: CGRect) -> CGPoint {
        CGPoint(
            x: nicknameFrame.minX - spacing - statusDotRadius,
            y: verticalPosition
        )
    }

    static func backgroundFrame(nicknameFrame: CGRect) -> CGRect {
        nicknameFrame.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }
}

private final class PixelCharacterNode: SKNode {
    private static let animationKey = "pixel-character-motion"
    private static let pulseAnimationKey = "pixel-character-pulse"
    private static let dozeMotionKey = "pixel-character-doze-motion"
    private let memberID: UUID
    private let presentation = SKNode()
    private let spritePulseAnchor = SKNode()
    private let sprite = SKSpriteNode()
    private let nameplateBackground = SKShapeNode()
    private let nickname = SKLabelNode(fontNamed: "AppleSDGothicNeo-SemiBold")
    private let statusDot = SKShapeNode(circleOfRadius: PixelNameplateLayout.statusDotRadius)
    private let dozeEffect = SKNode()
    private let dozeLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private var bubbleNode: PixelBubbleNode?
    private var currentMotion: PixelCharacterMotion?
    private var currentBubbleKey: String?
    private(set) var characterID: String
    private(set) var pulsePlayCount = 0

    var bubbleBody: String? { bubbleNode?.body }
    var bubbleIsTyping: Bool { bubbleNode?.isTyping ?? false }
    var dozeText: String? { dozeLabel.text }
    var hasDozeActions: Bool {
        dozeEffect.action(forKey: Self.dozeMotionKey) != nil
    }
    var visualState: PixelCharacterVisualState? {
        currentMotion.map {
            PixelCharacterVisualState(
                motion: $0,
                alpha: sprite.alpha,
                colorBlendFactor: sprite.colorBlendFactor,
                showsDozeLabel: !dozeEffect.isHidden
            )
        }
    }

    init(memberID: UUID, characterID: String) {
        self.memberID = memberID
        self.characterID = PixelCharacterCatalog.canonicalID(for: characterID)
        super.init()
        addChild(presentation)
        sprite.size = CGSize(width: 48, height: 48)
        sprite.texture = PixelCharacterTextureStore.shared.textures(for: self.characterID).idle[0]
        sprite.texture?.filteringMode = .nearest
        spritePulseAnchor.position = CGPoint(x: 0, y: -EdgeTrackGeometry.footInset)
        sprite.position = CGPoint(x: 0, y: EdgeTrackGeometry.footInset)
        presentation.addChild(spritePulseAnchor)
        spritePulseAnchor.addChild(sprite)

        nameplateBackground.fillColor = PixelNameplateLayout.backgroundColor
        nameplateBackground.strokeColor = .clear
        nameplateBackground.zPosition = 11
        presentation.addChild(nameplateBackground)

        nickname.fontSize = 11
        nickname.fontColor = .white
        nickname.verticalAlignmentMode = .center
        nickname.horizontalAlignmentMode = .center
        nickname.position = CGPoint(x: 0, y: PixelNameplateLayout.verticalPosition)
        nickname.zPosition = 12
        presentation.addChild(nickname)

        statusDot.strokeColor = .clear
        statusDot.position = PixelNameplateLayout.statusDotPosition(nicknameFrame: nickname.frame)
        statusDot.zPosition = 12
        presentation.addChild(statusDot)

        dozeEffect.position = CGPoint(x: 26, y: 20)
        dozeEffect.zPosition = 14
        dozeEffect.isHidden = true
        for offset in PixelDozeLabelStyle.outlineOffsets {
            let outline = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
            outline.text = PixelDozeLabelStyle.text
            outline.fontSize = PixelDozeLabelStyle.fontSize
            outline.fontColor = PixelDozeLabelStyle.outlineColor
            outline.position = offset
            outline.zPosition = 0
            dozeEffect.addChild(outline)
        }
        dozeLabel.text = PixelDozeLabelStyle.text
        dozeLabel.fontSize = PixelDozeLabelStyle.fontSize
        dozeLabel.fontColor = PixelDozeLabelStyle.fillColor
        dozeLabel.zPosition = 1
        dozeEffect.addChild(dozeLabel)
        presentation.addChild(dozeEffect)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        member: PixelWorldMember,
        bubble: ActiveBubble?,
        edge: OverlayEdge,
        tangentPosition: CGFloat,
        tangentLength: CGFloat
    ) {
        let canonicalID = PixelCharacterCatalog.canonicalID(for: member.characterID)
        if canonicalID != characterID {
            characterID = canonicalID
            currentMotion = nil
            sprite.removeAction(forKey: Self.animationKey)
        }
        presentation.zRotation = edge.presentationRotation
        nickname.text = member.isCurrentUser ? "\(member.nickname) · 나" : member.nickname
        let backgroundFrame = PixelNameplateLayout.backgroundFrame(nicknameFrame: nickname.frame)
        let backgroundPath = CGMutablePath()
        backgroundPath.addRoundedRect(
            in: backgroundFrame,
            cornerWidth: PixelNameplateLayout.cornerRadius,
            cornerHeight: PixelNameplateLayout.cornerRadius
        )
        nameplateBackground.path = backgroundPath
        statusDot.position = PixelNameplateLayout.statusDotPosition(nicknameFrame: nickname.frame)
        statusDot.fillColor = PresenceIndicatorTone.tone(for: member.presence).color
        updateBubble(
            bubble: bubble,
            isTyping: bubble == nil && member.isTyping,
            tangentPosition: tangentPosition,
            tangentLength: tangentLength,
            edge: edge
        )
        updateMotion(member: member, moving: false)
    }

    func playPulse() {
        pulsePlayCount += 1
        spritePulseAnchor.removeAction(forKey: Self.pulseAnimationKey)
        spritePulseAnchor.setScale(1)

        let grow = SKAction.scale(to: PixelCharacterPulseStyle.peakScale, duration: PixelCharacterPulseStyle.growDuration)
        grow.timingMode = .easeOut
        let settle = SKAction.scale(to: 1, duration: PixelCharacterPulseStyle.settleDuration)
        settle.timingMode = .easeInEaseOut
        spritePulseAnchor.run(.sequence([grow, settle]), withKey: Self.pulseAnimationKey)
    }

    func updateMotion(member: PixelWorldMember, moving: Bool) {
        let requested: PixelCharacterMotion
        switch member.presence {
        case .away:
            requested = .doze
        case .offline:
            requested = .offline
        case .reconnecting:
            requested = .stopped
        case .online, .typing:
            requested = moving ? .walk : .idle
        }

        sprite.alpha = member.presence == .offline ? 0.75 : 1
        sprite.color = .systemGray
        sprite.colorBlendFactor = member.presence == .offline ? 0.58 : 0
        setDozeVisible(member.presence == .away)

        guard requested != currentMotion else { return }
        currentMotion = requested
        sprite.removeAction(forKey: Self.animationKey)
        let set = PixelCharacterTextureStore.shared.textures(for: characterID)
        let textures: [SKTexture]
        let duration: TimeInterval
        switch requested {
        case .idle:
            textures = set.idle
            duration = 0.55
        case .walk:
            textures = set.walk
            duration = 0.16
        case .doze:
            textures = set.doze
            duration = 0.8
        case .offline:
            textures = set.offline
            duration = 1.2
        case .stopped:
            sprite.texture = set.idle[0]
            return
        }
        textures.forEach { $0.filteringMode = .nearest }
        sprite.run(.repeatForever(.animate(with: textures, timePerFrame: duration)), withKey: Self.animationKey)
    }

    func updatePresentationLayout(tangentPosition: CGFloat, tangentLength: CGFloat, edge: OverlayEdge) {
        guard let bubbleNode else { return }
        bubbleNode.apply(layout: PixelBubbleLayout.make(
            text: bubbleNode.body,
            isTyping: bubbleNode.isTyping,
            tangentPosition: tangentPosition,
            tangentLength: tangentLength,
            edge: edge
        ))
    }

    private func updateBubble(
        bubble: ActiveBubble?,
        isTyping: Bool,
        tangentPosition: CGFloat,
        tangentLength: CGFloat,
        edge: OverlayEdge
    ) {
        let body = bubble?.body ?? (isTyping ? "." : nil)
        let key = bubble.map { "message:\($0.messageID.uuidString)" } ?? (isTyping ? "typing" : nil)
        guard let body, let key else {
            bubbleNode?.removeFromParent()
            bubbleNode = nil
            currentBubbleKey = nil
            return
        }

        let layout = PixelBubbleLayout.make(
            text: body,
            isTyping: isTyping,
            tangentPosition: tangentPosition,
            tangentLength: tangentLength,
            edge: edge
        )
        if currentBubbleKey != key {
            bubbleNode?.removeFromParent()
            let node: PixelBubbleNode = isTyping
                ? TypingIndicatorNode(layout: layout)
                : MessageBubbleNode(body: body, layout: layout)
            presentation.addChild(node)
            bubbleNode = node
            currentBubbleKey = key
        } else {
            bubbleNode?.apply(layout: layout)
        }
    }

    private func setDozeVisible(_ visible: Bool) {
        guard dozeEffect.isHidden == visible else { return }
        dozeEffect.isHidden = !visible
        dozeEffect.removeAllActions()
        dozeEffect.position = CGPoint(x: 26, y: 20)
        guard visible else { return }
        dozeEffect.alpha = PixelDozeLabelStyle.restingAlpha
        dozeEffect.run(.repeatForever(.sequence([
            .group([
                .fadeAlpha(to: 1, duration: 0.5),
                .moveBy(x: 0, y: PixelDozeLabelStyle.floatingDistance, duration: 0.5)
            ]),
            .group([
                .fadeAlpha(to: PixelDozeLabelStyle.restingAlpha, duration: 0.5),
                .moveBy(x: 0, y: -PixelDozeLabelStyle.floatingDistance, duration: 0.5)
            ])
        ])), withKey: Self.dozeMotionKey)
    }
}

enum PixelCharacterMotion {
    case idle
    case walk
    case doze
    case offline
    case stopped
}

enum PixelBubbleStyle {
    static let backgroundColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
    static let textColor = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    static let borderColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.16)
}

class PixelBubbleNode: SKNode {
    let body: String
    let isTyping: Bool
    fileprivate let background = SKShapeNode()
    fileprivate let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Medium")
    private var lastLayout: PixelBubbleLayout?

    init(body: String, isTyping: Bool, layout: PixelBubbleLayout) {
        self.body = body
        self.isTyping = isTyping
        super.init()
        zPosition = 20
        background.fillColor = PixelBubbleStyle.backgroundColor
        background.strokeColor = PixelBubbleStyle.borderColor
        background.lineWidth = 1
        addChild(background)

        label.text = body
        label.fontSize = isTyping ? 16 : 10.5
        // SpriteKit resolves dynamic AppKit colors against the scene's dark
        // appearance, not against this white bubble. Use an explicit ink color
        // so Korean text stays readable in both system appearances.
        label.fontColor = PixelBubbleStyle.textColor
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        addChild(label)
        apply(layout: layout)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(layout: PixelBubbleLayout) {
        guard layout != lastLayout else { return }
        lastLayout = layout
        position = CGPoint(x: layout.localCenterX, y: 52 + layout.size.height / 2)
        label.preferredMaxLayoutWidth = max(8, layout.size.width - 16)
        let rect = CGRect(
            x: -layout.size.width / 2,
            y: -layout.size.height / 2,
            width: layout.size.width,
            height: layout.size.height
        )
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: 9, cornerHeight: 9)
        let halfBase: CGFloat = 6
        let baseCenter = min(max(layout.tailTipX, rect.minX + 10), rect.maxX - 10)
        path.move(to: CGPoint(x: baseCenter - halfBase, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: layout.tailTipX, y: rect.minY - 8))
        path.addLine(to: CGPoint(x: baseCenter + halfBase, y: rect.minY + 1))
        path.closeSubpath()
        background.path = path
    }
}

private final class MessageBubbleNode: PixelBubbleNode {
    init(body: String, layout: PixelBubbleLayout) {
        super.init(body: body, isTyping: false, layout: layout)
        label.text = body
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class TypingIndicatorNode: PixelBubbleNode {
    static let sequenceFrames = [".", "..", "..."]
    static let frameInterval: TimeInterval = 0.35

    init(layout: PixelBubbleLayout) {
        super.init(body: ".", isTyping: true, layout: layout)
        let sequence = SKAction.sequence([
            .run { [weak self] in self?.label.text = Self.sequenceFrames[0] }, .wait(forDuration: Self.frameInterval),
            .run { [weak self] in self?.label.text = Self.sequenceFrames[1] }, .wait(forDuration: Self.frameInterval),
            .run { [weak self] in self?.label.text = Self.sequenceFrames[2] }, .wait(forDuration: Self.frameInterval)
        ])
        run(.repeatForever(sequence), withKey: "typing-dots")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct PixelCharacterTextures {
    let idle: [SKTexture]
    let walk: [SKTexture]
    let doze: [SKTexture]
    let offline: [SKTexture]
}

@MainActor
private final class PixelCharacterTextureStore {
    static let shared = PixelCharacterTextureStore()
    private var cache: [String: PixelCharacterTextures] = [:]

    func textures(for storedID: String, bundle: Bundle = .main) -> PixelCharacterTextures {
        let definition = PixelCharacterCatalog.definition(for: storedID)
        if let cached = cache[definition.id] { return cached }
        let sheet: SKTexture
        if let url = definition.assetURL(bundle: bundle), let image = NSImage(contentsOf: url) {
            sheet = SKTexture(image: image)
        } else {
            sheet = SKTexture(image: fallbackImage())
        }
        sheet.filteringMode = .nearest
        let frames = (0..<PixelCharacterCatalog.frameCount).map { index -> SKTexture in
            let texture = SKTexture(
                rect: CGRect(
                    x: CGFloat(index) / CGFloat(PixelCharacterCatalog.frameCount),
                    y: 0,
                    width: 1 / CGFloat(PixelCharacterCatalog.frameCount),
                    height: 1
                ),
                in: sheet
            )
            texture.filteringMode = .nearest
            return texture
        }
        let contract = definition.frames
        let result = PixelCharacterTextures(
            idle: Array(frames[contract.idle]),
            walk: Array(frames[contract.walk]),
            doze: Array(frames[contract.doze]),
            offline: Array(frames[contract.offline])
        )
        cache[definition.id] = result
        return result
    }

    private func fallbackImage() -> NSImage {
        let image = NSImage(size: PixelCharacterCatalog.sheetPixelSize)
        image.lockFocus()
        NSColor.systemOrange.setFill()
        for frame in 0..<PixelCharacterCatalog.frameCount {
            NSBezierPath(rect: CGRect(x: CGFloat(frame * 24 + 4), y: 3, width: 16, height: 17)).fill()
        }
        image.unlockFocus()
        return image
    }
}
