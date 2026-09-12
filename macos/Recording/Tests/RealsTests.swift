#if DEBUG
import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import SideyReals

@MainActor
final class RealsTests: XCTestCase {
    func testUnavailablePreferencesKeepEditorUsableWithoutClaimingAutosave() throws {
        let editor = RealsEditor(defaults: nil)
        defer { editor.shutdown() }
        XCTAssertEqual(editor.project.lines.map(\.body), RealsProject.example.lines.map(\.body))
        XCTAssertTrue(editor.project.issues.isEmpty)
        editor.project.title = "저장소 없이 편집"
        editor.flush()
        XCTAssertEqual(editor.fileStatus, "자동 저장 불가 · 설정을 파일로 저장해주세요")
        XCTAssertEqual(try RealsProject.decode(editor.project.encoded()).title, "저장소 없이 편집")
    }

    func testRoundTripIncludesPeopleDialogueAndActions() throws {
        var project = RealsProject.example
        project.actions = [RealsAction(actorID: project.participants[0].id, targetID: project.participants[1].id,
                                       start: 10, end: 15, interval: 0.5)]
        let decoded = try RealsProject.decode(project.encoded())
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(RealsTimeline(project: decoded).actionEvents.count, 11)
    }

    func testImportUsesNumbersAndNamesAndPreservesColons() throws {
        var project = RealsProject.example
        project.participants[0].nickname = "토리"
        let imported = try project.importing("유저1: 하나\n\n2: 시간: 10시\n토리: 셋")
        XCTAssertEqual(imported.map(\.body), ["하나", "시간: 10시", "셋"])
        XCTAssertEqual(imported.map(\.speakerID), [project.participants[0].id, project.participants[1].id, project.participants[0].id])
        XCTAssertTrue(imported.allSatisfy { $0.interval == nil })
        XCTAssertThrowsError(try project.importing("유저4: 없는 사람"))
        XCTAssertThrowsError(try project.importing("유저1:"))
        XCTAssertThrowsError(try project.importing("형식 없는 대사"))
        project.participants[1].nickname = "토리"
        XCTAssertThrowsError(try project.importing("토리: 누구?"))
    }

    func testIntervalsAndLastActionDetermineDuration() {
        var project = RealsProject.example
        let id = project.participants[0].id
        project.lines = [RealsLine(speakerID: id, body: "1"), RealsLine(speakerID: id, body: "2", interval: 4),
                         RealsLine(speakerID: id, body: "3", interval: 100)]
        project.defaultInterval = 2
        project.endingHold = 3
        project.actions = [RealsAction(kind: .pulse, actorID: id, start: 10, end: 12, interval: 1)]
        let timeline = RealsTimeline(project: project)
        XCTAssertEqual(timeline.events.map(\.second), [0, 2, 6])
        XCTAssertEqual(timeline.actionEvents.map(\.second), [10, 11, 12])
        XCTAssertEqual(timeline.duration, 15)
        XCTAssertEqual(timeline.presentation(at: 6).bubbles.map(\.body), ["2", "3"])
        XCTAssertTrue(timeline.presentation(at: 20).bubbles.isEmpty)
    }

    func testInvalidReferencesTimingAndOverlappingActionsAreRejected() throws {
        var project = RealsProject.example
        let id = project.participants[0].id
        project.actions = [RealsAction(actorID: id, targetID: id)]
        XCTAssertThrowsError(try project.validated())
        project.actions = [RealsAction(kind: .pulse, actorID: id, start: 1, end: 3, interval: 0.5)]
        XCTAssertThrowsError(try project.validated())
        project.actions = [RealsAction(kind: .pulse, actorID: id, start: 1, end: 2),
                           RealsAction(kind: .pulse, actorID: id, start: 1.5, end: 1.5)]
        XCTAssertThrowsError(try project.validated())
        project.actions = [RealsAction(kind: .pulse, actorID: id, start: 0, end: 3600)]
        XCTAssertThrowsError(try project.validated())
        project.actions = []
        project.lines[0].speakerID = UUID()
        XCTAssertThrowsError(try project.validated())
        project.lines = []
        project.defaultInterval = .nan
        XCTAssertThrowsError(try project.validated())
    }

    func testSingleActionIncludesExactStartAndEndWithoutOvershooting() {
        var project = RealsProject.example
        let id = project.participants[0].id
        project.actions = [RealsAction(kind: .pulse, actorID: id, start: 2, end: 2),
                           RealsAction(kind: .pulse, actorID: id, start: 5, end: 7.5, interval: 1)]
        XCTAssertEqual(RealsTimeline(project: project).actionEvents.map(\.second), [2, 5, 6, 7])
    }

    func testPlayerPausesActionsAndRestartsWithoutDuplicates() throws {
        var project = RealsProject.example
        project.countdown = 0
        project.actions = [RealsAction(kind: .pulse, actorID: project.participants[0].id, start: 0, end: 1)]
        let player = RealsPlayer()
        defer { player.stop() }
        try player.start(project)
        XCTAssertEqual(player.performed, 1)
        XCTAssertEqual(player.scene?.renderedPulseCount(for: project.participants[0].id), 1)
        player.pauseOrResume()
        player.advance(by: 2)
        XCTAssertEqual(player.elapsed, 0)
        XCTAssertEqual(player.performed, 1)
        player.pauseOrResume()
        player.advance(by: 1)
        XCTAssertEqual(player.performed, 2)
        try player.start(project)
        XCTAssertEqual(player.performed, 1)
        XCTAssertEqual(player.scene?.renderedPulseCount(for: project.participants[0].id), 1)
        player.stop()
        XCTAssertNil(player.scene)
        XCTAssertFalse(player.overlayVisible)
    }

    func testThrowUsesPlaybackClockAndHitsAfterResuming() throws {
        var project = RealsProject.example
        project.countdown = 0
        project.actions = [RealsAction(actorID: project.participants[0].id, targetID: project.participants[1].id)]
        let player = RealsPlayer()
        defer { player.stop() }
        try player.start(project)
        let scene = try XCTUnwrap(player.scene)
        XCTAssertEqual(scene.activeProjectileCount, 1)
        scene.update(50_000)
        XCTAssertEqual(scene.activeProjectileCount, 1, "Renderer uptime must not expire a virtual-time projectile")
        player.pauseOrResume()
        player.advance(by: 10)
        XCTAssertEqual(player.elapsed, 0)
        player.pauseOrResume()
        player.advance(by: 1.3)
        scene.update(60_000)
        XCTAssertEqual(scene.renderedHitCount(for: project.participants[1].id), 1)
    }

    func testReferencedPersonCannotBeDeletedAndUnfinishedDraftIsRestored() {
        let name = "app.sidey.reals.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let editor = RealsEditor(defaults: defaults)
        let id = editor.project.participants[0].id
        editor.removeParticipant(id)
        XCTAssertEqual(editor.project.participants.count, 3)
        XCTAssertNotNil(editor.error)
        editor.addLine()
        editor.flush()
        let restored = RealsEditor(defaults: defaults)
        XCTAssertEqual(restored.project.lines.last?.body, "")
        XCTAssertEqual(restored.project.lines.count, 21)
        editor.shutdown()
        restored.shutdown()
    }
    func testEditorRendersInItsOwnWindow() async throws {
        let name = "app.sidey.reals.visual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let editor = RealsEditor(defaults: defaults)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 800),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: RealsEditorView(editor: editor))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { editor.shutdown(); window.close() }
        try await Task.sleep(for: .milliseconds(500))
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = "sidey-reals-editor"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(bitmap.pixelsWide, 1000)
    }

}
#endif
