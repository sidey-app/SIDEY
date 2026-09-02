import AppKit
import SwiftUI
import XCTest
@testable import SIDEY

@MainActor
final class SettingsInteractionTests: XCTestCase {
    func testInviteCopySuccessIsVisibleForThreeSeconds() throws {
        var state = InviteCopyFeedbackState()

        let generation = try XCTUnwrap(state.recordResult(true))

        XCTAssertEqual(InviteCopyFeedbackState.confirmationDuration, .seconds(3))
        XCTAssertTrue(state.showsConfirmation)
        state.clear(generation: generation)
        XCTAssertFalse(state.showsConfirmation)
    }

    func testInviteCopyFailureDoesNotShowConfirmation() {
        var state = InviteCopyFeedbackState()

        XCTAssertNil(state.recordResult(false))
        XCTAssertFalse(state.showsConfirmation)
    }

    func testProfileSaveCommitsMarkedHangulBeforeRunningAction() async throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView(frame: window.contentView!.bounds)
        window.contentView = textView
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.setMarkedText(
            "별",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        let actionRan = expectation(description: "프로필 저장 액션 실행")

        PendingTextInputCommitter.commitThen(in: window) {
            XCTAssertFalse(textView.hasMarkedText())
            XCTAssertEqual(textView.string, "별")
            actionRan.fulfill()
        }

        await fulfillment(of: [actionRan], timeout: 1)
    }

    func testRepeatedInviteCopyInvalidatesEarlierResetTimer() throws {
        var state = InviteCopyFeedbackState()

        let firstGeneration = try XCTUnwrap(state.recordResult(true))
        let secondGeneration = try XCTUnwrap(state.recordResult(true))
        state.clear(generation: firstGeneration)

        XCTAssertTrue(state.showsConfirmation)
        state.clear(generation: secondGeneration)
        XCTAssertFalse(state.showsConfirmation)
    }

    func testRemovingRoomRowCancelsInviteCopyFeedback() throws {
        var state = InviteCopyFeedbackState()
        let generation = try XCTUnwrap(state.recordResult(true))

        state.cancel()
        state.clear(generation: generation)

        XCTAssertFalse(state.showsConfirmation)
    }

    func testGroupsUseCompactTwoPersonSymbol() {
        XCTAssertEqual(SettingsPage.groups.systemImage, "person.2")
        XCTAssertNotNil(NSImage(systemSymbolName: SettingsPage.groups.systemImage, accessibilityDescription: nil))
    }

    func testGroupOperationUsesSpecificProgressLabelsAndMutationPolicy() {
        let roomID = UUID()

        XCTAssertEqual(GroupOperation.creating.createButtonTitle, "만드는 중…")
        XCTAssertEqual(GroupOperation.joining.joinButtonTitle, "참여 중…")
        XCTAssertTrue(GroupOperation.switching(roomID).isSwitching(to: roomID))
        XCTAssertTrue(GroupOperation.switching(roomID).allowsRoomSelection)
        XCTAssertTrue(GroupOperation.switching(roomID).blocksMutations)
        XCTAssertFalse(GroupOperation.creating.allowsRoomSelection)
    }

    func testSwitchingGroupCardRendersInLightAndDarkModes() throws {
        let activeRoomID = UUID()
        let targetRoomID = UUID()
        for scheme in [ColorScheme.light, .dark] {
            let data = try renderSettings(
                size: SettingsWindowController.settingsContentSize,
                colorScheme: scheme
            ) { model in
                model.activeSettingsPage = .groups
                model.preferences.activeRoomID = activeRoomID
                model.rooms = [
                    Self.room(id: activeRoomID, name: "현재 그룹"),
                    Self.room(id: targetRoomID, name: "전환 대상")
                ]
                model.groupOperation = .switching(targetRoomID)
            }
            XCTAssertGreaterThan(data.count, 10_000)
        }
    }

    func testTwelveMemberGroupRendersAtCapacity() throws {
        let roomID = UUID()
        let members = (0..<ProductLimits.maximumRoomMembers).map { index in
            RoomMember(
                userID: UUID(),
                nickname: "친구\(index + 1)",
                characterID: "pixel_hamster",
                presence: .online
            )
        }

        let data = try renderSettings(
            size: SettingsWindowController.settingsContentSize,
            colorScheme: .light
        ) { model in
            model.activeSettingsPage = .groups
            model.preferences.activeRoomID = roomID
            model.rooms = [Self.room(id: roomID, name: "가득 찬 그룹", members: members)]
        }

        XCTAssertEqual(members.count, 12)
        XCTAssertGreaterThan(data.count, 10_000)
    }

    func testSettingsRenderAtMinimumAndDefaultSizesInLightAndDarkModes() throws {
        let snapshotSentinel = "/private/tmp/sidey-render-settings-snapshots"
        let configuredOutput = ProcessInfo.processInfo.environment["SIDEY_SETTINGS_SNAPSHOT_DIR"]
        let outputDirectory = configuredOutput
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? (FileManager.default.fileExists(atPath: snapshotSentinel)
                ? URL(fileURLWithPath: "/private/tmp/sidey-settings-alpha6", isDirectory: true)
                : nil)
        if let outputDirectory {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        }

        for (sizeName, size) in [
            ("minimum", CGSize(width: 860, height: 640)),
            ("default", SettingsWindowController.settingsContentSize)
        ] {
            for scheme in [ColorScheme.light, .dark] {
                let data = try renderSettings(size: size, colorScheme: scheme)
                XCTAssertGreaterThan(data.count, 10_000)
                if let outputDirectory {
                    let mode = scheme == .light ? "light" : "dark"
                    try data.write(to: outputDirectory.appending(path: "settings-\(sizeName)-\(mode).png"))

                    let placementData = try renderSettings(
                        size: size,
                        colorScheme: scheme,
                        scrollToBottom: true
                    )
                    XCTAssertGreaterThan(placementData.count, 10_000)
                    try placementData.write(
                        to: outputDirectory.appending(path: "settings-\(sizeName)-\(mode)-placement.png")
                    )
                }
            }
        }
    }

    func testResponsiveSquareStoreGridRendersLongAndIndependentCardStates() throws {
        let products = [
            CommerceProduct(
                id: "fixture_store_first",
                displayName: "첫 번째 테스트 캐릭터",
                description: "최소 크기에서도 설명이 자연스럽게 여러 줄로 이어지고 아래 버튼을 밀어내거나 잘라내지 않는지 확인하는 긴 상품 설명입니다.",
                characterID: "pixel_hamster",
                entitlementKey: "character:fixture_store_first",
                amountKRW: 990,
                currency: "KRW",
                taxInclusive: true
            ),
            CommerceProduct(
                id: "fixture_store_second",
                displayName: "두 번째 테스트 캐릭터",
                description: "두 번째 카드의 상태가 첫 번째 카드와 독립적으로 표시되는지 확인합니다.",
                characterID: "pixel_cat",
                entitlementKey: "character:fixture_store_second",
                amountKRW: 1_900,
                currency: "KRW",
                taxInclusive: true
            )
        ]
        let snapshotSentinel = "/private/tmp/sidey-store-snapshots"
        let configuredOutput = ProcessInfo.processInfo.environment["SIDEY_STORE_SNAPSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? (FileManager.default.fileExists(atPath: snapshotSentinel)
                ? URL(fileURLWithPath: snapshotSentinel, isDirectory: true)
                : nil)
        if let configuredOutput {
            try FileManager.default.createDirectory(
                at: configuredOutput,
                withIntermediateDirectories: true
            )
        }

        for (scenario, configureState) in [
            (
                "owned-error",
                { (model: AppModel) in
                    model.apply(commerceState: CommerceState(
                        product: products[0],
                        googleConnected: true,
                        entitlementStatus: "active",
                        latestOrderStatus: "approved"
                    ))
                    model.setCommercePurchaseState(
                        .error("두 번째 상품만 상태를 불러오지 못했습니다. 다른 상품은 그대로 사용할 수 있습니다."),
                        productID: products[1].id
                    )
                }
            ),
            (
                "loading-confirming",
                { (model: AppModel) in
                    model.apply(commerceState: CommerceState(
                        product: products[0],
                        googleConnected: true,
                        entitlementStatus: nil,
                        latestOrderStatus: nil
                    ))
                    model.setCommerceWorking(true, productID: products[0].id)
                    model.setCommercePurchaseState(.confirming, productID: products[1].id)
                }
            )
        ] {
            for (sizeName, size) in [
                ("minimum", CGSize(width: 860, height: 640)),
                ("default", SettingsWindowController.settingsContentSize)
            ] {
                for scheme in [ColorScheme.light, .dark] {
                    let data = try renderSettings(
                        size: size,
                        colorScheme: scheme,
                        commerceProducts: products
                    ) { model in
                        model.activeSettingsPage = .store
                        configureState(model)
                    }
                    XCTAssertGreaterThan(data.count, 10_000)
                    if let configuredOutput {
                        let mode = scheme == .light ? "light" : "dark"
                        try data.write(
                            to: configuredOutput.appending(
                                path: "store-\(scenario)-\(sizeName)-\(mode).png"
                            )
                        )
                    }
                }
            }
        }
    }

    private func renderSettings(
        size: CGSize,
        colorScheme: ColorScheme,
        scrollToBottom: Bool = false,
        commerceProducts: [CommerceProduct] = CommerceCatalog.products,
        configure: (AppModel) -> Void = { _ in }
    ) throws -> Data {
        var preferences = AppPreferences.defaults
        preferences.onboardingComplete = true
        preferences.overlayRegion.screenIdentifier = "display:main"
        let model = AppModel(preferences: preferences, commerceProducts: commerceProducts)
        model.activeSettingsPage = .app
        model.availableScreens = [
            OverlayScreenOption(id: "display:main", name: "내장 디스플레이"),
            OverlayScreenOption(id: "display:secondary", name: "보조 디스플레이")
        ]
        configure(model)

        let root = SettingsRootView(model: model, actions: .empty)
            .environment(\.colorScheme, colorScheme)
            .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        if scrollToBottom,
           let scrollView = hostingView.descendants(of: NSScrollView.self)
               .filter({ ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height })
               .max(by: {
                   ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
               }),
           let documentView = scrollView.documentView {
            scrollView.contentView.scroll(
                to: NSPoint(
                    x: 0,
                    y: max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
                )
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
        }

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private static func room(id: UUID, name: String, members: [RoomMember] = []) -> Room {
        Room(
            id: id,
            name: name,
            ownerID: UUID(),
            members: members,
            inviteCodeHint: "••••-••AA",
            inviteVersion: 1
        )
    }
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { view in
            let match = (view as? T).map { [$0] } ?? []
            return match + view.descendants(of: type)
        }
    }
}
