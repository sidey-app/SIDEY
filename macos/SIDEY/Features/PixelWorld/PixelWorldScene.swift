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

struct PixelMovementAgent: Equatable, Identifiable, Sendable {
    let id: UUID
    var position: CGPoint
    var velocity: CGVector = .zero
    var target: CGPoint
    var idleRemaining: TimeInterval = 0
}

enum PixelMovementSimulation {
    static let characterRadius: CGFloat = 25
    static let maximumSpeed: CGFloat = 22

    static func step(
        agents: inout [PixelMovementAgent],
        deltaTime rawDeltaTime: TimeInterval,
        bounds: CGRect,
        avoidanceRects: [CGRect],
        stoppedIDs: Set<UUID>
    ) {
        guard !agents.isEmpty, bounds.width.isFinite, bounds.height.isFinite else { return }
        let deltaTime = min(max(rawDeltaTime, 0), 1.0 / 10.0)
        guard deltaTime > 0 else { return }
        let inset = safePlayableBounds(bounds)

        var separation: [UUID: CGVector] = [:]
        for lhsIndex in agents.indices {
            for rhsIndex in agents.indices where rhsIndex > lhsIndex {
                let lhs = agents[lhsIndex]
                let rhs = agents[rhsIndex]
                let dx = lhs.position.x - rhs.position.x
                let dy = lhs.position.y - rhs.position.y
                let distanceSquared = dx * dx + dy * dy
                let desiredDistance = characterRadius * 2
                guard distanceSquared < desiredDistance * desiredDistance else { continue }
                let direction: CGVector
                if distanceSquared > 0.0001 {
                    let inverseDistance = 1 / sqrt(distanceSquared)
                    direction = CGVector(dx: dx * inverseDistance, dy: dy * inverseDistance)
                } else {
                    direction = deterministicDirection(lhs.id, rhs.id)
                }
                let distance = sqrt(max(distanceSquared, 0.0001))
                let strength = max(0, 1 - distance / desiredDistance) * 30
                separation[lhs.id, default: .zero] += direction * strength
                separation[rhs.id, default: .zero] -= direction * strength
            }
        }

        for index in agents.indices {
            var agent = agents[index]
            guard !stoppedIDs.contains(agent.id) else {
                agent.velocity = .zero
                agents[index] = agent
                continue
            }
            if agent.idleRemaining > 0 {
                agent.idleRemaining = max(0, agent.idleRemaining - deltaTime)
                agent.velocity = .zero
                agents[index] = agent
                continue
            }

            let toTarget = CGVector(
                dx: agent.target.x - agent.position.x,
                dy: agent.target.y - agent.position.y
            )
            let targetDistance = toTarget.length
            var acceleration = targetDistance > 2
                ? toTarget.normalized * 32
                : .zero
            acceleration += separation[agent.id, default: .zero]
            for rect in avoidanceRects {
                acceleration += avoidanceForce(position: agent.position, rect: rect)
            }

            agent.velocity += acceleration * CGFloat(deltaTime)
            agent.velocity *= pow(0.82, CGFloat(deltaTime * 30))
            if agent.velocity.length > maximumSpeed {
                agent.velocity = agent.velocity.normalized * maximumSpeed
            }
            agent.position.x += agent.velocity.dx * CGFloat(deltaTime)
            agent.position.y += agent.velocity.dy * CGFloat(deltaTime)
            agent.position = clamped(agent.position, to: inset)

            if !agent.position.x.isFinite || !agent.position.y.isFinite
                || !agent.velocity.dx.isFinite || !agent.velocity.dy.isFinite {
                agent.position = CGPoint(x: inset.midX, y: inset.midY)
                agent.velocity = .zero
            }
            agents[index] = agent
        }
    }

    static func safePlayableBounds(_ bounds: CGRect) -> CGRect {
        let horizontalInset = min(characterRadius, max(0, bounds.width / 2))
        let verticalInset = min(characterRadius, max(0, bounds.height / 2))
        return bounds.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    private static func avoidanceForce(position: CGPoint, rect: CGRect) -> CGVector {
        let expanded = rect.insetBy(dx: -characterRadius, dy: -characterRadius)
        guard expanded.contains(position) else {
            let nearest = CGPoint(
                x: min(max(position.x, expanded.minX), expanded.maxX),
                y: min(max(position.y, expanded.minY), expanded.maxY)
            )
            let delta = CGVector(dx: position.x - nearest.x, dy: position.y - nearest.y)
            let influence: CGFloat = 16
            guard delta.length > 0, delta.length < influence else { return .zero }
            return delta.normalized * (1 - delta.length / influence) * 45
        }

        let exits: [(CGFloat, CGVector)] = [
            (position.x - expanded.minX, CGVector(dx: -1, dy: 0)),
            (expanded.maxX - position.x, CGVector(dx: 1, dy: 0)),
            (position.y - expanded.minY, CGVector(dx: 0, dy: -1)),
            (expanded.maxY - position.y, CGVector(dx: 0, dy: 1))
        ]
        return (exits.min(by: { $0.0 < $1.0 })?.1 ?? .zero) * 90
    }

    private static func deterministicDirection(_ lhs: UUID, _ rhs: UUID) -> CGVector {
        let comparison = lhs.uuidString < rhs.uuidString ? 1.0 : -1.0
        return CGVector(dx: comparison, dy: 0)
    }

    private static func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}

final class PixelWorldScene: SKScene {
    private var characterNodes: [UUID: PixelCharacterNode] = [:]
    private var agents: [UUID: PixelMovementAgent] = [:]
    private var members: [UUID: PixelWorldMember] = [:]
    private var activeBubbles: [UUID: ActiveBubble] = [:]
    private var currentRoomID: UUID?
    private var installationSeed: UInt64 = 0
    private var edge: OverlayEdge = .bottom
    private var lastUpdateTime: TimeInterval?

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
        let safeBounds = PixelMovementSimulation.safePlayableBounds(frame)
        let needsInitialLayout = (oldSize.width <= 1 || oldSize.height <= 1)
            && size.width > 1 && size.height > 1
        for id in Array(agents.keys) {
            guard var agent = agents[id] else { continue }
            if needsInitialLayout {
                // NSViewRepresentable may create SKView at zero size and lay it
                // out on the next pass. Re-seed once instead of clamping every
                // new member onto the same corner of the now-valid region.
                agent.position = stablePoint(roomID: currentRoomID, userID: id)
                agent.target = stablePoint(roomID: currentRoomID, userID: id, salt: 1)
            } else {
                agent.position = clamped(agent.position, to: safeBounds)
                agent.target = clamped(agent.target, to: safeBounds)
            }
            agents[id] = agent
            characterNodes[id]?.position = agent.position
        }
    }

    func apply(
        roomID: UUID?,
        members requestedMembers: [PixelWorldMember],
        bubbles: [ActiveBubble],
        edge: OverlayEdge,
        installationSeed: UInt64
    ) {
        let roomChanged = roomID != currentRoomID
        currentRoomID = roomID
        self.installationSeed = installationSeed
        self.edge = edge
        if roomChanged {
            characterNodes.values.forEach { $0.removeFromParent() }
            characterNodes.removeAll()
            agents.removeAll()
        }

        let requestedByID = Dictionary(uniqueKeysWithValues: requestedMembers.map { ($0.id, $0) })
        let removedIDs = Set(characterNodes.keys).subtracting(requestedByID.keys)
        for id in removedIDs {
            characterNodes.removeValue(forKey: id)?.removeFromParent()
            agents.removeValue(forKey: id)
        }

        members = requestedByID
        activeBubbles = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.senderID, $0) })
        for member in requestedMembers {
            let node: PixelCharacterNode
            if let existing = characterNodes[member.id] {
                node = existing
            } else {
                node = PixelCharacterNode(memberID: member.id)
                characterNodes[member.id] = node
                addChild(node)
                let initial = stablePoint(roomID: roomID, userID: member.id)
                let target = stablePoint(roomID: roomID, userID: member.id, salt: 1)
                agents[member.id] = PixelMovementAgent(
                    id: member.id,
                    position: initial,
                    target: target,
                    idleRemaining: stableUnit(roomID: roomID, userID: member.id, salt: 2) * 1.5
                )
                node.position = initial
            }
            node.apply(
                member: member,
                bubble: activeBubbles[member.id],
                presentationRotation: edge.presentationRotation
            )
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = lastUpdateTime.map { currentTime - $0 } ?? (1.0 / 30.0)
        lastUpdateTime = currentTime
        let stoppedIDs = Set(members.values.compactMap { member -> UUID? in
            if activeBubbles[member.id] != nil { return member.id }
            switch member.presence {
            case .away, .offline, .reconnecting: return member.id
            case .online, .typing: return nil
            }
        })
        var orderedAgents = agents.values.sorted { $0.id.uuidString < $1.id.uuidString }
        PixelMovementSimulation.step(
            agents: &orderedAgents,
            deltaTime: deltaTime,
            bounds: frame,
            avoidanceRects: composerAvoidanceRects,
            stoppedIDs: stoppedIDs
        )

        for var agent in orderedAgents {
            if !stoppedIDs.contains(agent.id), agent.position.distance(to: agent.target) < 3 {
                agent.idleRemaining = 0.8 + stableUnit(
                    roomID: currentRoomID,
                    userID: agent.id,
                    salt: UInt64(currentTime.rounded(.down)) &+ 17
                ) * 2.2
                agent.target = randomTarget(for: agent.id, time: currentTime)
            }
            agents[agent.id] = agent
            guard let node = characterNodes[agent.id], let member = members[agent.id] else { continue }
            node.position = agent.position
            let moving = agent.velocity.length > 2 && agent.idleRemaining <= 0 && !stoppedIDs.contains(agent.id)
            node.updateMotion(member: member, moving: moving, hasMessageBubble: activeBubbles[agent.id] != nil)
        }
    }

    var nodeIDs: Set<UUID> { Set(characterNodes.keys) }
    var agentStates: [PixelMovementAgent] { agents.values.sorted { $0.id.uuidString < $1.id.uuidString } }

    private var composerAvoidanceRects: [CGRect] {
        guard edge == .bottom else { return [] }
        return [CGRect(x: size.width / 2 - 220, y: 0, width: 440, height: 76).intersection(frame)]
            .filter { !$0.isNull && !$0.isEmpty }
    }

    private func stablePoint(roomID: UUID?, userID: UUID, salt: UInt64 = 0) -> CGPoint {
        let safe = PixelMovementSimulation.safePlayableBounds(frame)
        let x = stableUnit(roomID: roomID, userID: userID, salt: salt)
        let y = stableUnit(roomID: roomID, userID: userID, salt: salt &+ 0x9E3779B97F4A7C15)
        return CGPoint(x: safe.minX + safe.width * x, y: safe.minY + safe.height * y)
    }

    private func randomTarget(for userID: UUID, time: TimeInterval) -> CGPoint {
        stablePoint(
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

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}

private final class PixelCharacterNode: SKNode {
    private static let animationKey = "pixel-hamster-motion"
    private let memberID: UUID
    private let presentation = SKNode()
    private let sprite = SKSpriteNode(texture: PixelHamsterTextures.shared.idle[0])
    private let nickname = SKLabelNode(fontNamed: "SFProRounded-Semibold")
    private let statusDot = SKShapeNode(circleOfRadius: 3)
    private var bubbleNode: SKNode?
    private var currentMotion: PixelHamsterMotion?

    init(memberID: UUID) {
        self.memberID = memberID
        super.init()
        addChild(presentation)
        sprite.size = CGSize(width: 48, height: 48)
        sprite.texture?.filteringMode = .nearest
        presentation.addChild(sprite)

        nickname.fontSize = 11
        nickname.fontColor = .white
        nickname.verticalAlignmentMode = .center
        nickname.horizontalAlignmentMode = .center
        nickname.position = CGPoint(x: 0, y: -32)
        presentation.addChild(nickname)

        statusDot.strokeColor = .clear
        statusDot.position = CGPoint(x: -30, y: -32)
        presentation.addChild(statusDot)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(member: PixelWorldMember, bubble: ActiveBubble?, presentationRotation: CGFloat) {
        presentation.zRotation = presentationRotation
        nickname.text = member.isCurrentUser ? "\(member.nickname) · 나" : member.nickname
        statusDot.fillColor = PresenceIndicatorTone.tone(for: member.presence).color
        updateBubble(body: bubble?.body ?? (member.isTyping ? "…" : nil), isTyping: bubble == nil && member.isTyping)
        updateMotion(member: member, moving: false, hasMessageBubble: bubble != nil)
    }

    func updateMotion(member: PixelWorldMember, moving: Bool, hasMessageBubble: Bool) {
        let requested: PixelHamsterMotion
        switch member.presence {
        case .away, .offline:
            requested = .sleep
        case .reconnecting:
            requested = .stopped
        case .online, .typing:
            requested = hasMessageBubble ? .idle : (moving ? .walk : .idle)
        }
        guard requested != currentMotion else { return }
        currentMotion = requested
        sprite.removeAction(forKey: Self.animationKey)
        let textures: [SKTexture]
        let duration: TimeInterval
        switch requested {
        case .idle:
            textures = PixelHamsterTextures.shared.idle
            duration = 0.55
        case .walk:
            textures = PixelHamsterTextures.shared.walk
            duration = 0.16
        case .sleep:
            textures = PixelHamsterTextures.shared.sleep
            duration = 0.7
        case .stopped:
            sprite.texture = PixelHamsterTextures.shared.idle[0]
            return
        }
        textures.forEach { $0.filteringMode = .nearest }
        sprite.run(.repeatForever(.animate(with: textures, timePerFrame: duration)), withKey: Self.animationKey)
    }

    private func updateBubble(body: String?, isTyping: Bool) {
        bubbleNode?.removeFromParent()
        bubbleNode = nil
        guard let body else { return }

        let lineCount = max(1, min(8, Int(ceil(Double(body.count) / 18.0))))
        let size = CGSize(width: isTyping ? 42 : 164, height: CGFloat(22 + lineCount * 14))
        let background = SKShapeNode(rectOf: size, cornerRadius: 9)
        background.fillColor = NSColor.white.withAlphaComponent(0.94)
        background.strokeColor = NSColor.black.withAlphaComponent(0.12)
        background.lineWidth = 1
        background.position = CGPoint(x: 0, y: 50 + size.height / 2)
        background.zPosition = 20

        let label = SKLabelNode(fontNamed: "SFProText-Medium")
        label.text = body
        label.fontSize = isTyping ? 16 : 11
        label.fontColor = .labelColor
        label.numberOfLines = lineCount
        label.preferredMaxLayoutWidth = size.width - 16
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        background.addChild(label)
        presentation.addChild(background)
        bubbleNode = background
    }
}

private enum PixelHamsterMotion {
    case idle
    case walk
    case sleep
    case stopped
}

enum PixelHamsterAsset {
    static let frameCount = 8
    static let framePixelSize = CGSize(width: 24, height: 24)

    static func url(bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: "pixel_hamster",
            withExtension: "png",
            subdirectory: "Characters/PixelHamster"
        ) ?? bundle.url(forResource: "pixel_hamster", withExtension: "png")
    }
}

private struct PixelHamsterTextures {
    // SpriteKit scene and node mutation is main-thread confined by SKView.
    @MainActor static let shared = PixelHamsterTextures()

    let idle: [SKTexture]
    let walk: [SKTexture]
    let sleep: [SKTexture]

    init(bundle: Bundle = .main) {
        let sheet: SKTexture
        if let url = PixelHamsterAsset.url(bundle: bundle), let image = NSImage(contentsOf: url) {
            sheet = SKTexture(image: image)
        } else {
            sheet = SKTexture(image: Self.fallbackImage())
        }
        sheet.filteringMode = .nearest
        let frames = (0..<PixelHamsterAsset.frameCount).map { index -> SKTexture in
            let texture = SKTexture(
                rect: CGRect(
                    x: CGFloat(index) / CGFloat(PixelHamsterAsset.frameCount),
                    y: 0,
                    width: 1 / CGFloat(PixelHamsterAsset.frameCount),
                    height: 1
                ),
                in: sheet
            )
            texture.filteringMode = .nearest
            return texture
        }
        idle = Array(frames[0...1])
        walk = Array(frames[2...5])
        sleep = Array(frames[6...7])
    }

    private static func fallbackImage() -> NSImage {
        let image = NSImage(size: CGSize(width: 192, height: 24))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: CGRect(x: 4, y: 4, width: 16, height: 16)).fill()
        image.unlockFocus()
        return image
    }
}

private extension CGVector {
    static func += (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs + rhs
    }

    static func -= (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs - rhs
    }

    static func *= (lhs: inout CGVector, rhs: CGFloat) {
        lhs = lhs * rhs
    }

    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
    }

    static prefix func - (value: CGVector) -> CGVector {
        CGVector(dx: -value.dx, dy: -value.dy)
    }

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }

    var length: CGFloat { sqrt(dx * dx + dy * dy) }

    var normalized: CGVector {
        let length = length
        guard length > 0.0001 else { return .zero }
        return self * (1 / length)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
