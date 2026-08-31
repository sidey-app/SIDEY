import XCTest
@testable import SIDEY

@MainActor
final class PresenceAndRealtimeTests: XCTestCase {
    func testSystemActivityStateUsesAnyInputAndLiveScreenLockState() {
        XCTAssertEqual(SystemActivityMonitor.anyInputEventType.rawValue, UInt32.max)
        XCTAssertEqual(
            SystemActivityMonitor.state(screenLocked: false, idleSeconds: 299.9, awayThreshold: 300),
            .online
        )
        XCTAssertEqual(
            SystemActivityMonitor.state(screenLocked: false, idleSeconds: 300, awayThreshold: 300),
            .away
        )
        XCTAssertEqual(
            SystemActivityMonitor.state(screenLocked: true, idleSeconds: 0, awayThreshold: 300),
            .away
        )
    }

    func testSystemActivityPollingRecoversWhenUnlockNotificationWasMissed() {
        var screenLocked = true
        var states: [PresenceState] = []
        let monitor = SystemActivityMonitor(
            idleSecondsProvider: { 0 },
            screenLockedProvider: { screenLocked },
            onChange: { states.append($0) }
        )

        monitor.start()
        screenLocked = false
        monitor.refresh()
        monitor.stop()

        XCTAssertEqual(states, [.away, .online])
    }

    func testSoloRoomUsesEffectiveLocalPresenceInsteadOfOfflineSnapshot() {
        let roomID = UUID()
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "minty_pup"),
                rooms: [Room(
                    id: roomID,
                    name: "혼자 테스트",
                    ownerID: userID,
                    members: [RoomMember(
                        userID: userID,
                        nickname: "나",
                        characterID: "minty_pup",
                        presence: .offline
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: userID
        )

        model.connectionState = .online
        model.presence = .online
        XCTAssertEqual(model.pixelWorldMembers.first?.presence, .online)

        model.presence = .away
        XCTAssertEqual(model.pixelWorldMembers.first?.presence, .away)

        model.connectionState = .connecting
        XCTAssertEqual(model.pixelWorldMembers.first?.presence, .reconnecting)
    }

    func testOfflinePresenceUsesRedIndicatorWhileReconnectRemainsGray() {
        XCTAssertEqual(PresenceIndicatorTone.tone(for: .offline), .red)
        XCTAssertEqual(PresenceIndicatorTone.tone(for: .reconnecting), .gray)
    }

    func testTypingStopRestoresAwayPresence() {
        let roomID = UUID()
        let friendID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: nil,
                rooms: [Room(
                    id: roomID,
                    name: "친구들",
                    ownerID: friendID,
                    members: [RoomMember(
                        userID: friendID,
                        nickname: "친구",
                        characterID: "minty_pup",
                        presence: .away
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: UUID()
        )

        model.updateTyping(roomID: roomID, userID: friendID, active: true)
        XCTAssertEqual(model.rooms[0].members[0].presence, .typing)
        model.updateTyping(roomID: roomID, userID: friendID, active: false)
        XCTAssertEqual(model.rooms[0].members[0].presence, .away)
    }

    func testTypingKeepsBaseMotionAndUsesSeparateFlag() {
        let roomID = UUID()
        let friendID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        model.apply(
            snapshot: BackendSnapshot(
                profile: nil,
                rooms: [Room(
                    id: roomID,
                    name: "친구들",
                    ownerID: friendID,
                    members: [RoomMember(
                        userID: friendID,
                        nickname: "친구",
                        characterID: "minty_pup",
                        presence: .online
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: UUID()
        )

        model.updateTyping(roomID: roomID, userID: friendID, active: true)

        XCTAssertEqual(model.pixelWorldMembers.first?.presence, .online)
        XCTAssertEqual(model.pixelWorldMembers.first?.isTyping, true)
        XCTAssertEqual(model.pixelWorldMembers.first?.characterID, "pixel_hamster")
    }

    func testOfflineMembersCanBeFilteredWithoutRemovingOnlineMembers() {
        let roomID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: nil,
                rooms: [Room(
                    id: roomID,
                    name: "친구들",
                    ownerID: UUID(),
                    members: [
                        RoomMember(userID: UUID(), nickname: "온라인", characterID: "pixel_hamster", presence: .online),
                        RoomMember(userID: UUID(), nickname: "오프라인", characterID: "pixel_hamster", presence: .offline)
                    ],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: UUID()
        )

        XCTAssertEqual(model.pixelWorldMembers.count, 2)
        model.preferences.showOfflineMembers = false
        XCTAssertEqual(model.pixelWorldMembers.map(\.nickname), ["온라인"])
    }

    func testCurrentUserRemainsVisibleWhenOfflineMembersAreHidden() {
        let userID = UUID()
        let roomID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "pixel_cat"),
                rooms: [Room(
                    id: roomID,
                    name: "친구들",
                    ownerID: userID,
                    members: [RoomMember(
                        userID: userID,
                        nickname: "나",
                        characterID: "pixel_cat",
                        presence: .offline
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: userID
        )
        model.preferences.showOfflineMembers = false
        model.connectionState = .idle

        XCTAssertEqual(model.pixelWorldMembers.count, 1)
        XCTAssertTrue(model.pixelWorldMembers[0].isCurrentUser)
        XCTAssertEqual(model.pixelWorldMembers[0].characterID, "pixel_cat")
        XCTAssertEqual(model.selectedCharacterID, "pixel_cat")
        XCTAssertEqual(model.preferences.selectedCharacterID, "pixel_cat")
    }

    func testRealtimePlanCapsRoomsAndSwitchesActiveRoom() {
        let rooms = (0..<6).map { _ in UUID() }
        let existing = Set([rooms[0], UUID()])
        let plan = RealtimeRoomPlan.make(existing: existing, requested: rooms, activeRoomID: rooms[4])

        XCTAssertEqual(plan.desired.count, 5)
        XCTAssertEqual(plan.activeRoomID, rooms[4])
        XCTAssertTrue(plan.removals.isSubset(of: existing))
        XCTAssertFalse(plan.desired.contains(rooms[5]))
    }

    func testRealtimeConnectionRequiresEveryDesiredRoomAndRecoversAfterResubscribe() {
        let firstRoomID = UUID()
        let secondRoomID = UUID()
        var tracker = RealtimeConnectionTracker()

        tracker.replaceDesiredRoomIDs([firstRoomID, secondRoomID])
        XCTAssertFalse(tracker.isConnected)

        tracker.setSubscribed(true, roomID: firstRoomID)
        XCTAssertFalse(tracker.isConnected)
        tracker.setSubscribed(true, roomID: secondRoomID)
        XCTAssertTrue(tracker.isConnected)

        tracker.setSubscribed(false, roomID: firstRoomID)
        XCTAssertFalse(tracker.isConnected)
        tracker.setSubscribed(true, roomID: firstRoomID)
        XCTAssertTrue(tracker.isConnected)

        tracker.replaceDesiredRoomIDs([secondRoomID])
        XCTAssertTrue(tracker.isConnected)
    }

    func testRealtimeRecoveryBackoffStartsAtEightSecondsAndCapsAtThirty() {
        XCTAssertEqual(RealtimeRecoveryPolicy.watchdogInterval, 5)
        XCTAssertEqual(RealtimeRecoveryPolicy.delay(forAttempt: 1), 8)
        XCTAssertEqual(RealtimeRecoveryPolicy.delay(forAttempt: 2), 16)
        XCTAssertEqual(RealtimeRecoveryPolicy.delay(forAttempt: 3), 30)
        XCTAssertEqual(RealtimeRecoveryPolicy.delay(forAttempt: 20), 30)
        XCTAssertEqual(RealtimeRecoveryPolicy.delay(forAttempt: 0), 8)
    }

    func testActiveRoomSwitchPublishesOfflineToPreviousRoomAndLocalStateToNewRoom() {
        let previousRoomID = UUID()
        let nextRoomID = UUID()

        XCTAssertEqual(
            PresencePublicationPlan.state(
                for: previousRoomID,
                activeRoomID: nextRoomID,
                localPresence: .away
            ),
            .offline
        )
        XCTAssertEqual(
            PresencePublicationPlan.state(
                for: nextRoomID,
                activeRoomID: nextRoomID,
                localPresence: .away
            ),
            .away
        )
    }

    func testPresenceStateReplacementDoesNotEndOfflineWhenJoinAndLeaveShareAUser() {
        let updatedUserID = UUID()
        let departedUserID = UUID()

        let updates = PresenceChangePlan.updates(
            joined: [updatedUserID: .away],
            left: [updatedUserID, departedUserID]
        )

        XCTAssertEqual(
            updates.first(where: { $0.userID == updatedUserID })?.state,
            .away
        )
        XCTAssertEqual(
            updates.first(where: { $0.userID == departedUserID })?.state,
            .offline
        )
        XCTAssertEqual(updates.filter { $0.userID == updatedUserID }.count, 1)
    }

    func testReconnectStateRestoresLastPresence() {
        let roomID = UUID()
        let friendID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: nil,
                rooms: [Room(
                    id: roomID,
                    name: "친구들",
                    ownerID: friendID,
                    members: [RoomMember(
                        userID: friendID,
                        nickname: "친구",
                        characterID: "minty_pup",
                        presence: .online
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: UUID()
        )

        model.setRealtimeConnected(false)
        XCTAssertEqual(model.rooms[0].members[0].presence, .reconnecting)
        model.setRealtimeConnected(true)
        XCTAssertEqual(model.rooms[0].members[0].presence, .online)
    }

    func testBroadcastTypingLeaseDoesNotRemainStuckAcrossReconnect() {
        let roomID = UUID()
        let friendID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: nil,
                rooms: [Room(
                    id: roomID,
                    name: "친구들",
                    ownerID: friendID,
                    members: [RoomMember(
                        userID: friendID,
                        nickname: "친구",
                        characterID: "minty_pup",
                        presence: .away
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: UUID()
        )

        model.updateTyping(roomID: roomID, userID: friendID, active: true)
        XCTAssertEqual(model.rooms[0].members[0].presence, .typing)

        model.setRealtimeConnected(false)
        XCTAssertEqual(model.rooms[0].members[0].presence, .reconnecting)
        model.setRealtimeConnected(true)
        XCTAssertEqual(model.rooms[0].members[0].presence, .away)
    }

    func testTypingLeaseStartsOnceAndDoesNotRestartForEveryKeystroke() {
        let roomID = UUID()
        var lease = TypingLease()

        XCTAssertEqual(lease.update(active: true, roomID: roomID), [.start(roomID)])
        XCTAssertEqual(lease.update(active: true, roomID: roomID), [])
        XCTAssertEqual(lease.update(active: true, roomID: roomID), [])
        XCTAssertEqual(lease.update(active: false, roomID: roomID), [.stop(roomID)])
        XCTAssertEqual(lease.update(active: false, roomID: roomID), [])
    }

    func testTypingLeaseStopsPreviousRoomBeforeStartingAnother() {
        let previousRoomID = UUID()
        let nextRoomID = UUID()
        var lease = TypingLease()

        XCTAssertEqual(lease.update(active: true, roomID: previousRoomID), [.start(previousRoomID)])
        XCTAssertEqual(
            lease.update(active: true, roomID: nextRoomID),
            [.stop(previousRoomID), .start(nextRoomID)]
        )
    }

    func testCharacterPulseCooldownAllowsOneEventPerMemberEverySecond() {
        let roomID = UUID()
        let userID = UUID()
        var cooldown = CharacterPulseCooldown()

        XCTAssertTrue(cooldown.accept(roomID: roomID, userID: userID, uptime: 100))
        XCTAssertFalse(cooldown.accept(roomID: roomID, userID: userID, uptime: 100.999))
        XCTAssertTrue(cooldown.accept(roomID: roomID, userID: userID, uptime: 101))
        XCTAssertTrue(cooldown.accept(roomID: roomID, userID: UUID(), uptime: 101))
        XCTAssertFalse(cooldown.accept(roomID: roomID, userID: userID, uptime: .infinity))
        XCTAssertEqual(CharacterPulseCooldown.duration, 1)
    }
}
