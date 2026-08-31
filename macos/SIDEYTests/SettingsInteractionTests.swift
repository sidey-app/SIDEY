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

    private func renderSettings(
        size: CGSize,
        colorScheme: ColorScheme,
        scrollToBottom: Bool = false
    ) throws -> Data {
        var preferences = AppPreferences.defaults
        preferences.onboardingComplete = true
        preferences.overlayRegion.screenIdentifier = "display:main"
        let model = AppModel(preferences: preferences)
        model.activeSettingsPage = .app
        model.availableScreens = [
            OverlayScreenOption(id: "display:main", name: "내장 디스플레이"),
            OverlayScreenOption(id: "display:secondary", name: "보조 디스플레이")
        ]

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
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { view in
            let match = (view as? T).map { [$0] } ?? []
            return match + view.descendants(of: type)
        }
    }
}
