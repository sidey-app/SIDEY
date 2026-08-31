import XCTest
@testable import SIDEY

@MainActor
final class PixelWorldTests: XCTestCase {
    func testTwentyAgentsStayFiniteAndInsideRegionDuringLongSimulation() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 180)
        let safe = PixelMovementSimulation.safePlayableBounds(bounds)
        var agents = (0..<20).map { index in
            PixelMovementAgent(
                id: UUID(),
                position: CGPoint(x: safe.minX + CGFloat(index) * 10, y: safe.midY),
                target: CGPoint(x: safe.maxX - CGFloat(index) * 9, y: safe.midY + CGFloat(index % 3))
            )
        }

        for _ in 0..<3_000 {
            PixelMovementSimulation.step(
                agents: &agents,
                deltaTime: 1.0 / 30.0,
                bounds: bounds,
                avoidanceRects: [CGRect(x: 380, y: 0, width: 440, height: 76)],
                stoppedIDs: []
            )
        }

        for agent in agents {
            XCTAssertTrue(agent.position.x.isFinite)
            XCTAssertTrue(agent.position.y.isFinite)
            XCTAssertTrue(agent.velocity.dx.isFinite)
            XCTAssertTrue(agent.velocity.dy.isFinite)
            XCTAssertGreaterThanOrEqual(agent.position.x, safe.minX)
            XCTAssertLessThanOrEqual(agent.position.x, safe.maxX)
            XCTAssertGreaterThanOrEqual(agent.position.y, safe.minY)
            XCTAssertLessThanOrEqual(agent.position.y, safe.maxY)
        }
    }

    func testCrowdedRegionAllowsSafeOverlapWithoutNaN() {
        let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
        var agents = (0..<20).map { _ in
            PixelMovementAgent(
                id: UUID(),
                position: CGPoint(x: 24, y: 24),
                target: CGPoint(x: 24, y: 24)
            )
        }

        for _ in 0..<300 {
            PixelMovementSimulation.step(
                agents: &agents,
                deltaTime: 1.0 / 30.0,
                bounds: bounds,
                avoidanceRects: [bounds],
                stoppedIDs: []
            )
        }

        XCTAssertTrue(agents.allSatisfy {
            $0.position.x.isFinite && $0.position.y.isFinite
                && $0.velocity.dx.isFinite && $0.velocity.dy.isFinite
        })
    }

    func testMessageBubbleStopsOnlyItsSender() {
        let stoppedID = UUID()
        let movingID = UUID()
        var agents = [
            PixelMovementAgent(id: stoppedID, position: CGPoint(x: 40, y: 40), target: CGPoint(x: 200, y: 100)),
            PixelMovementAgent(id: movingID, position: CGPoint(x: 80, y: 40), target: CGPoint(x: 240, y: 100))
        ]

        PixelMovementSimulation.step(
            agents: &agents,
            deltaTime: 1,
            bounds: CGRect(x: 0, y: 0, width: 300, height: 180),
            avoidanceRects: [],
            stoppedIDs: [stoppedID]
        )

        XCTAssertEqual(agents.first(where: { $0.id == stoppedID })?.position, CGPoint(x: 40, y: 40))
        XCTAssertNotEqual(agents.first(where: { $0.id == movingID })?.position, CGPoint(x: 80, y: 40))
    }

    func testUUIDDiffKeepsPositionsAcrossPresenceAndSnapshotUpdates() throws {
        let roomID = UUID()
        let members = (0..<20).map { index in
            PixelWorldMember(
                id: UUID(),
                nickname: "친구 \(index)",
                characterID: "pixel_hamster",
                presence: .online,
                isTyping: false,
                isCurrentUser: index == 0
            )
        }
        let scene = PixelWorldScene(size: CGSize(width: 1_000, height: 180))
        scene.apply(roomID: roomID, members: members, bubbles: [], edge: .bottom, installationSeed: 42)
        let initial = Dictionary(uniqueKeysWithValues: scene.agentStates.map { ($0.id, $0.position) })

        let updated = members.enumerated().map { index, member in
            PixelWorldMember(
                id: member.id,
                nickname: member.nickname,
                characterID: member.characterID,
                presence: index.isMultiple(of: 2) ? .away : .online,
                isTyping: index == 3,
                isCurrentUser: member.isCurrentUser
            )
        }
        scene.apply(roomID: roomID, members: updated, bubbles: [], edge: .left, installationSeed: 42)

        XCTAssertEqual(scene.nodeIDs, Set(members.map(\.id)))
        for state in scene.agentStates {
            XCTAssertEqual(state.position, try XCTUnwrap(initial[state.id]))
        }
    }

    func testStableSeedReproducesInitialRoomPlacement() {
        let roomID = UUID()
        let member = PixelWorldMember(
            id: UUID(),
            nickname: "친구",
            characterID: "pixel_hamster",
            presence: .online,
            isTyping: false,
            isCurrentUser: false
        )
        let first = PixelWorldScene(size: CGSize(width: 800, height: 180))
        let second = PixelWorldScene(size: CGSize(width: 800, height: 180))

        first.apply(roomID: roomID, members: [member], bubbles: [], edge: .bottom, installationSeed: 12_345)
        second.apply(roomID: roomID, members: [member], bubbles: [], edge: .bottom, installationSeed: 12_345)

        XCTAssertEqual(first.agentStates.first?.position, second.agentStates.first?.position)
    }

    func testZeroSizedRepresentableSceneSpreadsMembersAfterFirstLayout() {
        let roomID = UUID()
        let members = (0..<20).map { index in
            PixelWorldMember(
                id: UUID(),
                nickname: "친구 \(index)",
                characterID: "pixel_hamster",
                presence: .online,
                isTyping: false,
                isCurrentUser: index == 0
            )
        }
        let scene = PixelWorldScene(size: .zero)
        scene.apply(roomID: roomID, members: members, bubbles: [], edge: .bottom, installationSeed: 99)

        scene.size = CGSize(width: 1_200, height: 180)

        let positions = Set(scene.agentStates.map { "\(Int($0.position.x)),\(Int($0.position.y))" })
        XCTAssertGreaterThan(positions.count, 10)
        let safe = PixelMovementSimulation.safePlayableBounds(scene.frame)
        for agent in scene.agentStates {
            XCTAssertGreaterThanOrEqual(agent.position.x, safe.minX)
            XCTAssertLessThanOrEqual(agent.position.x, safe.maxX)
            XCTAssertGreaterThanOrEqual(agent.position.y, safe.minY)
            XCTAssertLessThanOrEqual(agent.position.y, safe.maxY)
        }
    }
}
