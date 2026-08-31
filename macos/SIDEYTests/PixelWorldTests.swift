import AppKit
import SpriteKit
import XCTest
@testable import SIDEY

@MainActor
final class PixelWorldTests: XCTestCase {
    func testStatusDotKeepsFivePointGapFromMeasuredNicknameFrame() {
        let shortFrame = CGRect(x: -12, y: 26, width: 24, height: 12)
        let longFrame = CGRect(x: -44, y: 26, width: 88, height: 12)
        let shortDot = PixelNameplateLayout.statusDotPosition(nicknameFrame: shortFrame)
        let longDot = PixelNameplateLayout.statusDotPosition(nicknameFrame: longFrame)

        XCTAssertEqual(
            shortDot.x + PixelNameplateLayout.statusDotRadius + PixelNameplateLayout.spacing,
            shortFrame.minX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            longDot.x + PixelNameplateLayout.statusDotRadius + PixelNameplateLayout.spacing,
            longFrame.minX,
            accuracy: 0.001
        )
        XCTAssertLessThan(longDot.x, shortDot.x)
    }

    func testNameplateBackgroundAddsPaddingWithoutCoveringStatusDot() {
        let nicknameFrame = CGRect(x: -24, y: 26, width: 48, height: 12)
        let background = PixelNameplateLayout.backgroundFrame(nicknameFrame: nicknameFrame)
        let dot = PixelNameplateLayout.statusDotPosition(nicknameFrame: nicknameFrame)

        XCTAssertEqual(background.minX, nicknameFrame.minX - PixelNameplateLayout.horizontalPadding)
        XCTAssertEqual(background.maxX, nicknameFrame.maxX + PixelNameplateLayout.horizontalPadding)
        XCTAssertEqual(background.minY, nicknameFrame.minY - PixelNameplateLayout.verticalPadding)
        XCTAssertEqual(background.maxY, nicknameFrame.maxY + PixelNameplateLayout.verticalPadding)
        XCTAssertLessThanOrEqual(
            dot.x + PixelNameplateLayout.statusDotRadius,
            background.minX
        )
        XCTAssertEqual(PixelNameplateLayout.backgroundColor.alphaComponent, 0.62, accuracy: 0.001)
    }

    func testTwentyAgentsStayFiniteAndOnEveryEdgeTrackDuringLongSimulation() {
        for edge in OverlayEdge.allCases {
            let bounds = edge.isHorizontal
                ? CGRect(x: 0, y: 0, width: 1_200, height: 240)
                : CGRect(x: 0, y: 0, width: 240, height: 1_200)
            let geometry = EdgeTrackGeometry(bounds: bounds, edge: edge)
            let range = geometry.trackRange
            var agents = (0..<20).map { index in
                PixelMovementAgent(
                    id: UUID(),
                    trackPosition: range.lowerBound + CGFloat(index) * 10,
                    target: range.upperBound - CGFloat(index) * 9
                )
            }

            for _ in 0..<3_000 {
                PixelMovementSimulation.step(
                    agents: &agents,
                    deltaTime: 1.0 / 30.0,
                    geometry: geometry,
                    avoidanceRects: edge == .bottom
                        ? [CGRect(x: 380, y: 0, width: 440, height: 76)]
                        : [],
                    stoppedIDs: []
                )
            }

            for agent in agents {
                XCTAssertTrue(agent.trackPosition.isFinite)
                XCTAssertTrue(agent.velocity.isFinite)
                XCTAssertTrue(range.contains(agent.trackPosition))
                let point = geometry.point(for: agent.trackPosition)
                switch edge {
                case .bottom:
                    XCTAssertEqual(point.y, bounds.minY + EdgeTrackGeometry.footInset, accuracy: 0.001)
                case .top:
                    XCTAssertEqual(point.y, bounds.maxY - EdgeTrackGeometry.footInset, accuracy: 0.001)
                case .left:
                    XCTAssertEqual(point.x, bounds.minX + EdgeTrackGeometry.footInset, accuracy: 0.001)
                case .right:
                    XCTAssertEqual(point.x, bounds.maxX - EdgeTrackGeometry.footInset, accuracy: 0.001)
                }
            }
        }
    }

    func testAllEdgeFootPointsTouchTheScreenBoundary() {
        for edge in OverlayEdge.allCases {
            let bounds = edge.isHorizontal
                ? CGRect(x: 0, y: 0, width: 800, height: 240)
                : CGRect(x: 0, y: 0, width: 240, height: 800)
            let geometry = EdgeTrackGeometry(bounds: bounds, edge: edge)
            let foot = geometry.footPoint(for: geometry.trackRange.lowerBound)
            switch edge {
            case .bottom: XCTAssertEqual(foot.y, bounds.minY, accuracy: 0.001)
            case .top: XCTAssertEqual(foot.y, bounds.maxY, accuracy: 0.001)
            case .left: XCTAssertEqual(foot.x, bounds.minX, accuracy: 0.001)
            case .right: XCTAssertEqual(foot.x, bounds.maxX, accuracy: 0.001)
            }
        }
    }

    func testCrowdedTrackAllowsSafeOverlapWithoutNaN() {
        let geometry = EdgeTrackGeometry(
            bounds: CGRect(x: 0, y: 0, width: 48, height: 240),
            edge: .bottom
        )
        var agents = (0..<20).map { _ in
            PixelMovementAgent(id: UUID(), trackPosition: 24, target: 24)
        }

        for _ in 0..<300 {
            PixelMovementSimulation.step(
                agents: &agents,
                deltaTime: 1.0 / 30.0,
                geometry: geometry,
                avoidanceRects: [geometry.bounds],
                stoppedIDs: []
            )
        }

        XCTAssertTrue(agents.allSatisfy { $0.trackPosition.isFinite && $0.velocity.isFinite })
    }

    func testOverlappingHeadOnAgentsAccelerateThroughInsteadOfSlowing() {
        let geometry = EdgeTrackGeometry(
            bounds: CGRect(x: 0, y: 0, width: 320, height: 240),
            edge: .bottom
        )
        var agents = [
            PixelMovementAgent(id: UUID(), trackPosition: 120, velocity: 8, target: 280),
            PixelMovementAgent(id: UUID(), trackPosition: 160, velocity: -8, target: 40)
        ]

        PixelMovementSimulation.step(
            agents: &agents,
            deltaTime: 1.0 / 30.0,
            geometry: geometry,
            avoidanceRects: [],
            stoppedIDs: []
        )

        XCTAssertGreaterThan(agents[0].velocity, 8)
        XCTAssertLessThan(agents[1].velocity, -8)
        XCTAssertGreaterThan(agents[0].trackPosition, 120)
        XCTAssertLessThan(agents[1].trackPosition, 160)
    }

    func testOverlapEndsIdleSoCharactersDoNotRemainStacked() {
        let geometry = EdgeTrackGeometry(
            bounds: CGRect(x: 0, y: 0, width: 320, height: 240),
            edge: .bottom
        )
        var agents = [
            PixelMovementAgent(id: UUID(), trackPosition: 140, target: 280, idleRemaining: 1),
            PixelMovementAgent(id: UUID(), trackPosition: 145, target: 40, idleRemaining: 1)
        ]

        PixelMovementSimulation.step(
            agents: &agents,
            deltaTime: 1.0 / 30.0,
            geometry: geometry,
            avoidanceRects: [],
            stoppedIDs: []
        )

        XCTAssertTrue(agents.allSatisfy { $0.idleRemaining == 0 })
        XCTAssertNotEqual(agents[0].trackPosition, 140)
        XCTAssertNotEqual(agents[1].trackPosition, 145)
    }

    func testMessageBubbleDoesNotStopAnOnlineSender() {
        let movingID = UUID()
        let awayID = UUID()
        let members = [
            PixelWorldMember(
                id: movingID, nickname: "온라인", characterID: "pixel_hamster",
                presence: .online, isTyping: false, isCurrentUser: true
            ),
            PixelWorldMember(
                id: awayID, nickname: "자리 비움", characterID: "pixel_cat",
                presence: .away, isTyping: false, isCurrentUser: false
            )
        ]
        let stoppedIDs = PixelMovementPolicy.stoppedMemberIDs(in: members)
        XCTAssertFalse(stoppedIDs.contains(movingID))
        XCTAssertTrue(stoppedIDs.contains(awayID))

        var agents = [PixelMovementAgent(id: movingID, trackPosition: 40, target: 200)]

        PixelMovementSimulation.step(
            agents: &agents,
            deltaTime: 1,
            geometry: EdgeTrackGeometry(
                bounds: CGRect(x: 0, y: 0, width: 300, height: 240),
                edge: .bottom
            ),
            avoidanceRects: [],
            stoppedIDs: stoppedIDs
        )

        XCTAssertNotEqual(agents.first?.trackPosition, 40)
    }

    func testUUIDDiffAndCharacterSwapKeepTrackPosition() throws {
        let roomID = UUID()
        let memberID = UUID()
        let member = PixelWorldMember(
            id: memberID,
            nickname: "친구",
            characterID: "pixel_hamster",
            presence: .online,
            isTyping: false,
            isCurrentUser: true
        )
        let scene = PixelWorldScene(size: CGSize(width: 1_000, height: 240))
        scene.apply(roomID: roomID, members: [member], bubbles: [], edge: .bottom, installationSeed: 42)
        let initial = try XCTUnwrap(scene.agentStates.first?.trackPosition)

        let updated = PixelWorldMember(
            id: memberID,
            nickname: "친구",
            characterID: "pixel_cat",
            presence: .away,
            isTyping: false,
            isCurrentUser: true
        )
        scene.apply(roomID: roomID, members: [updated], bubbles: [], edge: .left, installationSeed: 42)

        XCTAssertEqual(scene.nodeIDs, [memberID])
        XCTAssertEqual(scene.agentStates.first?.trackPosition, initial)
        XCTAssertEqual(scene.renderedCharacterID(for: memberID), "pixel_cat")
    }

    func testStableSeedReproducesInitialRoomPlacement() {
        let roomID = UUID()
        let member = makeMember()
        let first = PixelWorldScene(size: CGSize(width: 800, height: 240))
        let second = PixelWorldScene(size: CGSize(width: 800, height: 240))

        first.apply(roomID: roomID, members: [member], bubbles: [], edge: .bottom, installationSeed: 12_345)
        second.apply(roomID: roomID, members: [member], bubbles: [], edge: .bottom, installationSeed: 12_345)

        XCTAssertEqual(first.agentStates.first?.trackPosition, second.agentStates.first?.trackPosition)
    }

    func testBubbleLayoutKeepsShortLongAndThreeLineMessagesInsideCanvas() {
        let messages = [
            "가",
            String(repeating: "긴메시지", count: 50),
            "첫 줄\n둘째 줄\n셋째 줄"
        ]
        for edge in OverlayEdge.allCases {
            let bounds = edge.isHorizontal
                ? CGRect(x: 0, y: 0, width: 720, height: 240)
                : CGRect(x: 0, y: 0, width: 240, height: 720)
            let geometry = EdgeTrackGeometry(bounds: bounds, edge: edge)
            for tangent in [geometry.trackRange.lowerBound, geometry.trackRange.upperBound] {
                for message in messages {
                    let layout = PixelBubbleLayout.make(
                        text: message,
                        isTyping: false,
                        tangentPosition: tangent,
                        tangentLength: geometry.tangentLength,
                        edge: edge
                    )
                    let worldFrame = geometry.worldFrame(for: layout.totalFrame, at: tangent)
                    XCTAssertTrue(
                        bounds.insetBy(dx: -0.5, dy: -0.5).contains(worldFrame),
                        "\(edge) \(tangent) \(message.count): \(worldFrame)"
                    )
                    XCTAssertLessThanOrEqual(layout.size.width, 220)
                }
            }
        }
    }

    func testBubbleUsesExplicitDarkInkOnLightBackground() throws {
        let text = PixelBubbleStyle.textColor.usingColorSpace(.sRGB) ?? PixelBubbleStyle.textColor
        let background = PixelBubbleStyle.backgroundColor.usingColorSpace(.sRGB)
            ?? PixelBubbleStyle.backgroundColor
        XCTAssertLessThan(text.redComponent, 0.2)
        XCTAssertLessThan(text.greenComponent, 0.2)
        XCTAssertLessThan(text.blueComponent, 0.2)
        XCTAssertGreaterThan(background.redComponent, 0.9)
        XCTAssertGreaterThan(background.greenComponent, 0.9)
        XCTAssertGreaterThan(background.blueComponent, 0.9)

        let layout = PixelBubbleLayout.make(
            text: "ㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎ",
            isTyping: false,
            tangentPosition: 200,
            tangentLength: 720,
            edge: .bottom
        )
        let node = PixelBubbleNode(body: "ㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎ", isTyping: false, layout: layout)
        let label = try XCTUnwrap(node.children.compactMap { $0 as? SKLabelNode }.first)
        XCTAssertEqual(label.fontColor, PixelBubbleStyle.textColor)
    }

    func testTypingDotsMessagePriorityAndTypingReturn() {
        XCTAssertEqual(TypingIndicatorNode.sequenceFrames, [".", "..", "..."])
        XCTAssertEqual(TypingIndicatorNode.frameInterval, 0.35, accuracy: 0.001)

        let roomID = UUID()
        let member = PixelWorldMember(
            id: UUID(), nickname: "친구", characterID: "pixel_rabbit",
            presence: .online, isTyping: true, isCurrentUser: false
        )
        let scene = PixelWorldScene(size: CGSize(width: 720, height: 240))
        scene.apply(roomID: roomID, members: [member], bubbles: [], edge: .bottom, installationSeed: 1)
        XCTAssertTrue(scene.renderedBubbleIsTyping(for: member.id))
        XCTAssertEqual(scene.renderedBubbleBody(for: member.id), ".")

        let message = ActiveBubble(
            senderID: member.id,
            messageID: UUID(),
            body: "도착",
            expiresAt: .now.addingTimeInterval(10)
        )
        scene.apply(roomID: roomID, members: [member], bubbles: [message], edge: .bottom, installationSeed: 1)
        XCTAssertFalse(scene.renderedBubbleIsTyping(for: member.id))
        XCTAssertEqual(scene.renderedBubbleBody(for: member.id), "도착")

        scene.apply(roomID: roomID, members: [member], bubbles: [], edge: .bottom, installationSeed: 1)
        XCTAssertTrue(scene.renderedBubbleIsTyping(for: member.id))
    }

    func testCharacterPulsePlaysOncePerBroadcastEvent() {
        let roomID = UUID()
        let member = makeMember(isCurrentUser: true)
        let scene = PixelWorldScene(size: CGSize(width: 720, height: 240))
        let first = CharacterPulseEvent(id: UUID(), roomID: roomID, userID: member.id)

        scene.apply(
            roomID: roomID, members: [member], bubbles: [], edge: .bottom,
            installationSeed: 1, characterPulse: first
        )
        XCTAssertEqual(scene.renderedPulseCount(for: member.id), 1)

        scene.apply(
            roomID: roomID, members: [member], bubbles: [], edge: .bottom,
            installationSeed: 1, characterPulse: first
        )
        XCTAssertEqual(scene.renderedPulseCount(for: member.id), 1)

        scene.apply(
            roomID: roomID, members: [member], bubbles: [], edge: .bottom,
            installationSeed: 1,
            characterPulse: CharacterPulseEvent(id: UUID(), roomID: roomID, userID: member.id)
        )
        XCTAssertEqual(scene.renderedPulseCount(for: member.id), 2)
        XCTAssertEqual(PixelCharacterPulseStyle.peakScale, 4)
        XCTAssertEqual(PixelCharacterPulseStyle.totalDuration, 0.56, accuracy: 0.001)
    }

    func testAwayOfflineAndReconnectHaveDistinctVisualStates() throws {
        let scene = PixelWorldScene(size: CGSize(width: 720, height: 240))
        let roomID = UUID()
        let memberID = UUID()

        func apply(_ presence: PresenceState) -> PixelCharacterVisualState? {
            scene.apply(
                roomID: roomID,
                members: [PixelWorldMember(
                    id: memberID, nickname: "친구", characterID: "pixel_penguin",
                    presence: presence, isTyping: false, isCurrentUser: false
                )],
                bubbles: [], edge: .bottom, installationSeed: 2
            )
            return scene.renderedVisualState(for: memberID)
        }

        let away = try XCTUnwrap(apply(.away))
        XCTAssertEqual(away.motion, .doze)
        XCTAssertEqual(away.alpha, 1)
        XCTAssertEqual(away.colorBlendFactor, 0)
        XCTAssertTrue(away.showsDozeLabel)

        let offline = try XCTUnwrap(apply(.offline))
        XCTAssertEqual(offline.motion, .offline)
        XCTAssertEqual(offline.alpha, 0.75, accuracy: 0.001)
        XCTAssertGreaterThan(offline.colorBlendFactor, 0.5)
        XCTAssertFalse(offline.showsDozeLabel)

        let reconnecting = try XCTUnwrap(apply(.reconnecting))
        XCTAssertEqual(reconnecting.motion, .stopped)
        XCTAssertFalse(reconnecting.showsDozeLabel)
    }

    func testCurrentUserFrameCallbackUsesOnlyThe52PointHotspot() throws {
        let member = makeMember(isCurrentUser: true)
        var reported: CGRect?
        let scene = PixelWorldScene(size: CGSize(width: 720, height: 240))
        scene.apply(
            roomID: UUID(), members: [member], bubbles: [], edge: .bottom,
            installationSeed: 1, onCurrentUserFrameChanged: { reported = $0 }
        )
        XCTAssertEqual(try XCTUnwrap(reported).size, CGSize(width: 52, height: 52))

        scene.apply(
            roomID: nil, members: [], bubbles: [], edge: .bottom,
            installationSeed: 1, onCurrentUserFrameChanged: { reported = $0 }
        )
        XCTAssertNil(reported)
    }

    private func makeMember(isCurrentUser: Bool = false) -> PixelWorldMember {
        PixelWorldMember(
            id: UUID(), nickname: "친구", characterID: "pixel_hamster",
            presence: .online, isTyping: false, isCurrentUser: isCurrentUser
        )
    }
}
