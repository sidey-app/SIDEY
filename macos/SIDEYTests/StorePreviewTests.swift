import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import SIDEY

@MainActor
final class StorePreviewTests: XCTestCase {
    func testCharacterScenariosUseTheProductCharacterAndOnlineMoka() {
        for product in CommerceCatalog.characterProducts {
            let scenario = StorePreviewScenario.make(product: product)
            XCTAssertEqual(scenario.members.count, 1)
            XCTAssertEqual(scenario.members[0].id, StorePreviewScenario.mokaID)
            XCTAssertEqual(scenario.members[0].nickname, "모카")
            XCTAssertEqual(scenario.members[0].characterID, product.characterID)
            XCTAssertEqual(scenario.members[0].presence, .online)
            XCTAssertFalse(scenario.members[0].isCurrentUser)
            XCTAssertTrue(scenario.bubbles.isEmpty)
            XCTAssertTrue(scenario.fixedTrackFractions.isEmpty)
            XCTAssertNil(scenario.throwSequence)
        }
    }

    func testBubbleScenariosUseTheActualThemeAndPersistentBody() throws {
        for product in CommerceCatalog.cosmeticProducts where product.kind == .bubble {
            let scenario = StorePreviewScenario.make(product: product)
            let member = try XCTUnwrap(scenario.members.first)
            let bubble = try XCTUnwrap(scenario.bubbles.first)
            XCTAssertEqual(member.characterID, PixelCharacterCatalog.pixelHamsterID)
            XCTAssertEqual(member.nickname, "모카")
            XCTAssertEqual(member.presence, .online)
            XCTAssertEqual(bubble.senderID, member.id)
            XCTAssertEqual(bubble.body, "저메추좀 해줘")
            XCTAssertEqual(bubble.bubbleStyleID, product.catalogItemID)
            XCTAssertEqual(PixelBubbleTheme.resolve(bubble.bubbleStyleID).id, product.catalogItemID)
            XCTAssertNil(scenario.throwSequence)
        }
    }

    func testThrowableScenariosFixMembersAndAlternateEverySecond() throws {
        for product in CommerceCatalog.cosmeticProducts where product.kind == .throwable {
            let scenario = StorePreviewScenario.make(product: product)
            XCTAssertEqual(scenario.members.map(\.nickname), ["모카", "두부"])
            XCTAssertEqual(scenario.members.map(\.characterID), ["pixel_hamster", "pixel_cat"])
            XCTAssertTrue(scenario.members.allSatisfy { $0.presence == .online })
            XCTAssertEqual(scenario.fixedTrackFractions[StorePreviewScenario.mokaID], 0.22)
            XCTAssertEqual(scenario.fixedTrackFractions[StorePreviewScenario.dubuID], 0.78)

            let sequence = try XCTUnwrap(scenario.throwSequence)
            XCTAssertEqual(sequence.scheduledOffset(for: 0), 0.35, accuracy: 0.001)
            XCTAssertEqual(sequence.scheduledOffset(for: 1), 1.35, accuracy: 0.001)
            XCTAssertEqual(sequence.scheduledOffset(for: 2), 2.35, accuracy: 0.001)
            let events = (0..<3).map { sequence.event(at: $0) }
            XCTAssertEqual(events.map(\.actorUserID), [
                StorePreviewScenario.mokaID,
                StorePreviewScenario.dubuID,
                StorePreviewScenario.mokaID
            ])
            XCTAssertEqual(events.map(\.targetUserID), [
                StorePreviewScenario.dubuID,
                StorePreviewScenario.mokaID,
                StorePreviewScenario.dubuID
            ])
            XCTAssertTrue(events.allSatisfy { $0.throwableID == product.catalogItemID })
        }
    }

    func testPreviewPulseUsesThreeTimesScaleAndOneSecondCooldownWhileLiveStaysSeven() {
        let member = StorePreviewScenario.make(product: .guineaPig).members[0]
        let live = PixelWorldScene(size: StorePreviewStageLayout.size)
        live.apply(
            roomID: StorePreviewScenario.roomID,
            members: [member],
            bubbles: [],
            edge: .bottom,
            installationSeed: 1,
            characterPulse: CharacterPulseEvent(
                id: UUID(), roomID: StorePreviewScenario.roomID, userID: member.id
            )
        )
        XCTAssertEqual(live.renderedPulsePeakScale(for: member.id), 7)
        XCTAssertFalse(live.playLocalPreviewPulse(memberID: member.id, at: 10))

        let preview = makeScene(for: .guineaPig)
        XCTAssertTrue(preview.playLocalPreviewPulse(memberID: member.id, at: 10))
        XCTAssertEqual(preview.renderedPulsePeakScale(for: member.id), 3)
        XCTAssertFalse(preview.playLocalPreviewPulse(memberID: member.id, at: 10.99))
        XCTAssertTrue(preview.playLocalPreviewPulse(memberID: member.id, at: 11))
        XCTAssertEqual(preview.renderedPulseCount(for: member.id), 2)
        XCTAssertEqual(PixelCharacterPulseStyle.peakScale, 7)
    }

    func testCharacterAndBubblePreviewWalkWhileThrowableMembersStayFixed() throws {
        for product in [CommerceProduct.guineaPig, .bunnyPinkBubble] {
            let scene = makeScene(for: product)
            let initial = try XCTUnwrap(scene.agentStates.first?.trackPosition)
            advance(scene, seconds: 4)
            XCTAssertNotEqual(scene.agentStates.first?.trackPosition, initial, product.id)
        }

        let throwable = StorePreviewScenario.make(product: .bouncyHeart)
        let scene = makeScene(for: .bouncyHeart)
        advance(scene, seconds: 4)
        let positions = Dictionary(uniqueKeysWithValues: scene.agentStates.map { ($0.id, $0.trackPosition) })
        XCTAssertEqual(
            try XCTUnwrap(positions[StorePreviewScenario.mokaID]),
            StorePreviewStageLayout.size.width * 0.22,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(positions[StorePreviewScenario.dubuID]),
            StorePreviewStageLayout.size.width * 0.78,
            accuracy: 0.001
        )
        XCTAssertEqual(Set(positions.keys), Set(throwable.members.map(\.id)))
    }

    func testNormalAndCannonPreviewReuseThrowProjectileImpactHitOrder() throws {
        for product in [CommerceProduct.bouncyHeart, .toyCannon] {
            let scenario = StorePreviewScenario.make(product: product)
            let sequence = try XCTUnwrap(scenario.throwSequence)
            let scene = makeScene(for: product)
            let event = sequence.event(at: 0)
            scene.playLocalPreviewThrow(event)
            XCTAssertEqual(scene.activeProjectileCount, 1)
            scene.update(ProcessInfo.processInfo.systemUptime + 2)
            XCTAssertEqual(scene.activeProjectileCount, 0)
            XCTAssertEqual(scene.previewRenderEvents, [
                .throwStarted(event.actorUserID),
                .projectileReleased(event.actorUserID),
                .impact(event.targetUserID),
                .hit(event.targetUserID)
            ], product.id)
            XCTAssertEqual(scene.renderedThrowCount(for: event.actorUserID), 1)
            XCTAssertEqual(scene.renderedHitCount(for: event.targetUserID), 1)
        }
    }

    func testPlaybackCoordinatorCancelsThrowTaskAndDetachesScene() throws {
        let scenario = StorePreviewScenario.make(product: .bouncyHeart)
        let view = StorePreviewSKView(frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size))
        let scene = makeScene(for: .bouncyHeart)
        view.presentScene(scene)
        let coordinator = StorePreviewPlaybackCoordinator()

        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertTrue(coordinator.hasActiveThrowTask)
        scene.playLocalPreviewThrow(try XCTUnwrap(scenario.throwSequence).event(at: 0))
        XCTAssertEqual(scene.activeProjectileCount, 1)
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: false)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        XCTAssertEqual(scene.activeProjectileCount, 0)
        coordinator.configure(view: view, scene: scene, scenario: scenario, isPlaying: true)
        XCTAssertTrue(coordinator.hasActiveThrowTask)
        coordinator.stop(detachingScene: true)
        XCTAssertFalse(coordinator.hasActiveThrowTask)
        XCTAssertNil(view.scene)
        XCTAssertTrue(view.isPaused)
    }

    func testStageLayoutLeavesRoomForPlatformAndThreeTimesPulse() {
        XCTAssertEqual(StorePreviewStageLayout.size, CGSize(width: 540, height: 280))
        XCTAssertEqual(StorePreviewStageLayout.platformHeight, 24)
        XCTAssertEqual(StorePreviewStageLayout.platformPixelSize, 4)
        XCTAssertGreaterThanOrEqual(
            StorePreviewStageLayout.size.height - StorePreviewStageLayout.platformHeight,
            EdgeTrackGeometry.characterPointSize * 3
        )
    }

    func testStageRendersOneSpriteKitViewForProductsInLightAndDarkModes() throws {
        for product in [
            CommerceProduct.guineaPig,
            .bunnyPinkBubble,
            .bouncyHeart,
            .toyCannon
        ] {
            for scheme in [ColorScheme.light, .dark] {
                let root = StorePreviewStage(product: product)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 540, height: 320)
                let hostingView = NSHostingView(rootView: root)
                hostingView.frame = CGRect(x: 0, y: 0, width: 540, height: 320)
                let window = NSWindow(
                    contentRect: hostingView.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hostingView
                hostingView.layoutSubtreeIfNeeded()
                hostingView.displayIfNeeded()

                XCTAssertEqual(descendants(of: SKView.self, in: hostingView).count, 1)
                let bitmap = try XCTUnwrap(
                    hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
                )
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(data.count, 5_000, "\(product.id) \(scheme)")
            }
        }
    }

    func testProductionLockedStoreDoesNotCreatePreviewScene() {
        var preferences = AppPreferences.defaults
        preferences.onboardingComplete = true
        let model = AppModel(
            preferences: preferences,
            commerceProducts: CommerceCatalog.products
        )
        let hostingView = NSHostingView(rootView: StoreView(
            model: model,
            actions: .empty,
            availability: .comingSoon
        ))
        hostingView.frame = CGRect(x: 0, y: 0, width: 1_000, height: 760)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        XCTAssertTrue(descendants(of: SKView.self, in: hostingView).isEmpty)
    }

    func testRepeatedPreviewTeardownReleasesSceneAndView() {
        weak var releasedScene: PixelWorldScene?
        weak var releasedView: StorePreviewSKView?
        let scenario = StorePreviewScenario.make(product: .bouncyHeart)

        for _ in 0..<20 {
            autoreleasepool {
                let view = StorePreviewSKView(
                    frame: CGRect(origin: .zero, size: StorePreviewStageLayout.size)
                )
                let scene = makeScene(for: .bouncyHeart)
                let coordinator = StorePreviewPlaybackCoordinator()
                view.presentScene(scene)
                coordinator.configure(
                    view: view,
                    scene: scene,
                    scenario: scenario,
                    isPlaying: true
                )
                coordinator.stop(detachingScene: true)
                releasedScene = scene
                releasedView = view
            }
            XCTAssertNil(releasedScene)
            XCTAssertNil(releasedView)
        }
    }

    private func makeScene(for product: CommerceProduct) -> PixelWorldScene {
        let scenario = StorePreviewScenario.make(product: product)
        let scene = PixelWorldScene(
            size: StorePreviewStageLayout.size,
            renderingConfiguration: .storePreview(
                fixedTrackFractions: scenario.fixedTrackFractions
            )
        )
        scene.apply(
            roomID: StorePreviewScenario.roomID,
            members: scenario.members,
            bubbles: scenario.bubbles,
            edge: .bottom,
            activityFrame: CGRect(
                x: 0,
                y: StorePreviewStageLayout.platformHeight,
                width: StorePreviewStageLayout.size.width,
                height: StorePreviewStageLayout.size.height - StorePreviewStageLayout.platformHeight
            ),
            installationSeed: 0x51_DE_59
        )
        return scene
    }

    private func advance(_ scene: PixelWorldScene, seconds: TimeInterval) {
        let start = ProcessInfo.processInfo.systemUptime
        let ticks = Int(seconds * 30)
        for tick in 0...ticks {
            scene.update(start + Double(tick) / 30)
        }
    }

    private func descendants<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        root.subviews.flatMap { subview -> [T] in
            let current = (subview as? T).map { [$0] } ?? []
            return current + descendants(of: type, in: subview)
        }
    }
}
