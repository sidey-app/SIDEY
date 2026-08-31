import AppKit
import SceneKit
import XCTest
@testable import SIDEY

@MainActor
final class WindowPolicyTests: XCTestCase {
    func testAvatarRendererUsesTheThirtyFPSContract() {
        let view = SCNView()

        AvatarRendererPolicy.apply(to: view)

        XCTAssertEqual(view.preferredFramesPerSecond, 30)
        XCTAssertTrue(view.rendersContinuously)
        XCTAssertEqual(view.antialiasingMode, .none)
        XCTAssertFalse(view.autoenablesDefaultLighting)
        XCTAssertFalse(view.allowsCameraControl)
    }

    func testOverlayPlacementCanCrossToAnAdjacentDisplay() throws {
        let left = OverlayScreenGeometry(
            identifier: "display:left",
            legacySignature: "1440x900@1.000",
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let right = OverlayScreenGeometry(
            identifier: "display:right",
            legacySignature: "2560x1440@2.000",
            visibleFrame: CGRect(x: 1440, y: 0, width: 1280, height: 720)
        )
        let draggedFrame = CGRect(x: 1_620, y: 120, width: 720, height: 360)

        let target = try XCTUnwrap(OverlayPlacement.target(for: draggedFrame, screens: [left, right]))
        let settled = OverlayPlacement.clamped(draggedFrame, to: target.visibleFrame)

        XCTAssertEqual(target.identifier, "display:right")
        XCTAssertEqual(settled.origin.x, draggedFrame.origin.x, accuracy: 0.1)
        XCTAssertEqual(settled.origin.y, draggedFrame.origin.y, accuracy: 0.1)
    }

    func testOverlayPlacementRecognizesMigratedGodotScreenSignature() {
        let primary = OverlayScreenGeometry(
            identifier: "display:primary",
            legacySignature: "1920x1080@1.000",
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040)
        )
        let secondary = OverlayScreenGeometry(
            identifier: "display:secondary",
            legacySignature: "2560x1440@2.000",
            visibleFrame: CGRect(x: 1920, y: 0, width: 1280, height: 720)
        )

        XCTAssertEqual(
            OverlayPlacement.target(
                for: .zero,
                screens: [primary, secondary],
                preferredIdentifier: "2560x1440@2.000"
            )?.identifier,
            "display:secondary"
        )
    }

    func testOnboardingWindowTransitionsToFullSettingsOnGroupPage() {
        var preferences = AppPreferences.defaults
        preferences.onboardingComplete = false
        let model = AppModel(preferences: preferences)
        let settings = SettingsWindowController(model: model)

        XCTAssertEqual(
            settings.contentSize.width,
            SettingsWindowController.onboardingContentSize.width,
            accuracy: 0.1
        )
        XCTAssertEqual(
            settings.contentSize.height,
            SettingsWindowController.onboardingContentSize.height,
            accuracy: 0.1
        )

        model.preferences.onboardingComplete = true
        model.activeSettingsPage = .groups
        settings.transitionFromOnboardingToSettings()

        XCTAssertEqual(model.activeSettingsPage, .groups)
        XCTAssertEqual(
            settings.contentSize.width,
            SettingsWindowController.settingsContentSize.width,
            accuracy: 0.1
        )
        XCTAssertEqual(
            settings.contentSize.height,
            SettingsWindowController.settingsContentSize.height,
            accuracy: 0.1
        )
    }

    func testExistingUserStartsWithFullSettingsSize() {
        var preferences = AppPreferences.defaults
        preferences.onboardingComplete = true
        let settings = SettingsWindowController(model: AppModel(preferences: preferences))

        XCTAssertEqual(
            settings.contentSize.width,
            SettingsWindowController.settingsContentSize.width,
            accuracy: 0.1
        )
        XCTAssertEqual(
            settings.contentSize.height,
            SettingsWindowController.settingsContentSize.height,
            accuracy: 0.1
        )
    }

    func testOverlayGroupMovesWithoutMovingSettingsWindow() {
        let model = AppModel(preferences: .defaults)
        let settings = SettingsWindowController(model: model)
        let group = OverlayWindowGroup(model: model, onOpenSettings: {})
        group.restore(frame: CodableRect(CGRect(x: 100, y: 100, width: 720, height: 360)))

        let settingsOrigin = settings.window?.frame.origin
        group.move(by: CGSize(width: 40, height: 20))

        XCTAssertEqual(settings.window?.level, .normal)
        XCTAssertEqual(settings.window?.frame.origin, settingsOrigin)
        XCTAssertEqual(group.currentFrame.origin.x, 140, accuracy: 0.1)
        XCTAssertEqual(group.currentFrame.origin.y, 80, accuracy: 0.1)
    }

    func testClosingSettingsDoesNotHideAvatar() {
        let model = AppModel(preferences: .defaults)
        let settings = SettingsWindowController(model: model)
        let group = OverlayWindowGroup(model: model, onOpenSettings: {})

        group.setVisible(true)
        settings.show()
        settings.close()

        XCTAssertTrue(group.avatarIsVisible)
        XCTAssertFalse(settings.window?.isVisible ?? true)
    }

    func testOrderingOutSettingsDoesNotHideAvatar() {
        let model = AppModel(preferences: .defaults)
        let settings = SettingsWindowController(model: model)
        let group = OverlayWindowGroup(model: model, onOpenSettings: {})

        group.setVisible(true)
        settings.show()
        settings.window?.orderOut(nil)

        XCTAssertTrue(group.avatarIsVisible)
        XCTAssertFalse(settings.window?.isVisible ?? true)
    }

    func testWindowLevelsAndDefaultClickThroughAreIndependent() {
        let model = AppModel(preferences: .defaults)
        let settings = SettingsWindowController(model: model)
        let group = OverlayWindowGroup(model: model, onOpenSettings: {})

        group.setVisible(true)

        XCTAssertEqual(settings.window?.level, .normal)
        XCTAssertEqual(group.avatarLevel, .floating)
        XCTAssertEqual(group.interactionLevel, .floating)
        XCTAssertFalse(group.avatarCanHide)
        XCTAssertTrue(group.avatarIgnoresMouseEvents)
        XCTAssertFalse(group.interactionIgnoresMouseEvents, "잠금·입력 패널은 명시적으로 클릭을 받아야 함")
        XCTAssertTrue(group.interactionIsVisible, "잠금과 채팅 입력은 잠금 모드에서도 항상 보여야 함")
        XCTAssertFalse(group.interactionIsKeyWindow, "상시 입력 패널이 표시만으로 키보드 포커스를 빼앗으면 안 됨")
        XCTAssertEqual(group.interactionSize.width, 400, accuracy: 0.1)
        XCTAssertEqual(group.interactionSize.height, 56, accuracy: 0.1)
        XCTAssertEqual(
            group.avatarSize.height,
            OverlayWindowGroup.defaultSize.height + AvatarOverlayLayout.topWindowExtension,
            accuracy: 0.1
        )
        XCTAssertTrue(group.avatarIsRendering)
        XCTAssertTrue(group.avatarCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(group.avatarCollectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(group.interactionCollectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(settings.window?.childWindows?.isEmpty ?? false, "설정과 오버레이를 child-window로 연결하면 안 됨")
    }

    func testBubbleAnchorMovesWithProjectedCharacterHead() {
        let smallCharacterHeadTop: CGFloat = 52
        let largeCharacterHeadTop: CGFloat = 14

        XCTAssertGreaterThan(
            AvatarOverlayLayout.bubbleBottom(for: smallCharacterHeadTop),
            AvatarOverlayLayout.bubbleBottom(for: largeCharacterHeadTop)
        )
    }

    func testMintyPupScaleMovesTheRealProjectedHeadAndBubbleTogether() throws {
        let scene = try MintyPupScene.makeScene(motion: .onlineIdle)
        let view = SCNView(frame: CGRect(
            x: 0,
            y: 0,
            width: AvatarOverlayLayout.contentWidth,
            height: AvatarOverlayLayout.sceneHeight
        ))
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(
            withName: MintyPupScene.cameraName,
            recursively: false
        )
        let root = try XCTUnwrap(scene.rootNode.childNode(
            withName: MintyPupScene.modelRootName,
            recursively: false
        ))

        root.scale = SCNVector3(1, 1, 1)
        let smallHeadTop = try XCTUnwrap(AvatarOverlayLayout.projectedHeadTop(of: root, in: view))
        root.scale = SCNVector3(4.0 / 3.0, 4.0 / 3.0, 4.0 / 3.0)
        let largeHeadTop = try XCTUnwrap(AvatarOverlayLayout.projectedHeadTop(of: root, in: view))

        XCTAssertLessThan(largeHeadTop, smallHeadTop)
        XCTAssertLessThan(
            AvatarOverlayLayout.bubbleBottom(for: largeHeadTop),
            AvatarOverlayLayout.bubbleBottom(for: smallHeadTop)
        )
    }

    func testExplicitEditingModeOwnsInteractionVisibility() {
        let model = AppModel(preferences: .defaults)
        var historyOpenCount = 0
        let group = OverlayWindowGroup(
            model: model,
            onOpenSettings: {},
            onHistoryOpened: { historyOpenCount += 1 }
        )
        group.setVisible(true)

        group.setMode(.editing)
        XCTAssertTrue(group.avatarIsVisible)
        XCTAssertTrue(group.interactionIsVisible)
        XCTAssertEqual(group.interactionSize.width, 580, accuracy: 0.1)
        XCTAssertEqual(group.interactionSize.height, 56, accuracy: 0.1)
        group.toggleHistory()
        XCTAssertTrue(group.historyIsVisible)
        XCTAssertFalse(group.historyIgnoresMouseEvents, "최근 기록 패널은 명시적으로 클릭을 받아야 함")
        XCTAssertEqual(historyOpenCount, 1)

        group.setMode(.locked)
        XCTAssertTrue(group.avatarIsVisible)
        XCTAssertTrue(group.interactionIsVisible)
        XCTAssertEqual(group.interactionSize.width, 400, accuracy: 0.1)
        XCTAssertFalse(group.historyIsVisible)
    }

    func testInteractiveMoveUsesTranslationFromStableDragOrigin() {
        let model = AppModel(preferences: .defaults)
        let group = OverlayWindowGroup(model: model, onOpenSettings: {})
        group.restore(frame: CodableRect(CGRect(x: 100, y: 100, width: 720, height: 360)))

        group.beginInteractiveMove()
        group.updateInteractiveMove(translation: CGSize(width: 20, height: 10))
        group.updateInteractiveMove(translation: CGSize(width: 40, height: 20))
        group.endInteractiveMove()

        XCTAssertEqual(group.currentFrame.origin.x, 140, accuracy: 0.1)
        XCTAssertEqual(group.currentFrame.origin.y, 80, accuracy: 0.1)
    }

    func testHidingOverlayDoesNotCloseSettings() {
        let model = AppModel(preferences: .defaults)
        let settings = SettingsWindowController(model: model)
        let group = OverlayWindowGroup(model: model, onOpenSettings: {})

        settings.show()
        group.setVisible(false)

        XCTAssertTrue(settings.window?.isVisible ?? false)
        XCTAssertFalse(group.avatarIsVisible)
        XCTAssertFalse(group.avatarIsRendering, "숨긴 오버레이는 3D 렌더러를 유지하면 안 됨")
    }

    func testStatusMenuContainsNativeOverlayControlsAndRoomUnreadCounts() throws {
        let activeRoomID = UUID()
        let otherRoomID = UUID()
        let rooms = [
            Room(id: activeRoomID, name: "작업방", ownerID: UUID(), members: [], inviteCodeHint: "AAAA", inviteVersion: 1),
            Room(id: otherRoomID, name: "친구방", ownerID: UUID(), members: [], inviteCodeHint: "BBBB", inviteVersion: 1)
        ]
        let controller = StatusItemController(
            onToggleOverlay: {},
            onToggleInteraction: {},
            onOpenSettings: {},
            onQuit: {}
        )
        controller.update(
            overlayVisible: true,
            overlayMode: .locked,
            rooms: rooms,
            activeRoomID: activeRoomID,
            unreadCounts: [otherRoomID: 3],
            quietModeEnabled: true,
            launchAtLogin: true
        )

        let menu = controller.makeMenu()
        XCTAssertNotNil(menu.item(withTitle: "메시지 작성…"))
        XCTAssertNotNil(menu.item(withTitle: "오버레이 잠금 해제"))
        XCTAssertNotNil(menu.item(withTitle: "오버레이 위치 초기화"))
        XCTAssertNotNil(menu.item(withTitle: "그룹 설정…"))
        XCTAssertEqual(menu.item(withTitle: "조용히 모드")?.state, .on)
        XCTAssertEqual(menu.item(withTitle: "로그인 시 자동 실행")?.state, .on)
        let groups = try XCTUnwrap(menu.item(withTitle: "활성 그룹")?.submenu)
        XCTAssertEqual(groups.item(withTitle: "작업방")?.state, .on)
        XCTAssertNotNil(groups.item(withTitle: "친구방 (3)"))
    }
}
