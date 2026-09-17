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

    func testLocalPresenceUsesRecoveredTransportWhileReconciliationIsPending() {
        let roomID = UUID()
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "pixel_hamster"),
                rooms: [Room(
                    id: roomID,
                    name: "복구 테스트",
                    ownerID: userID,
                    members: [RoomMember(
                        userID: userID,
                        nickname: "나",
                        characterID: "pixel_hamster",
                        presence: .offline
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: userID
        )
        model.connectionState = .connecting
        model.presence = .online

        model.setActiveRoomRealtimeConnected(true)

        XCTAssertTrue(model.activeRoomTransportConnected)
        XCTAssertEqual(model.pixelWorldMembers.first?.presence, .online)
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

    func testPresenceAndTypingArrivingBeforeNewRoomSnapshotAreRetained() {
        let roomID = UUID()
        let friendID = UUID()
        let model = AppModel(preferences: .defaults)

        model.updatePresence(roomID: roomID, userID: friendID, state: .online)
        model.updateTyping(roomID: roomID, userID: friendID, active: true)
        model.apply(
            snapshot: BackendSnapshot(
                profile: nil,
                rooms: [Room(
                    id: roomID,
                    name: "새 그룹",
                    ownerID: friendID,
                    members: [RoomMember(
                        userID: friendID,
                        nickname: "친구",
                        characterID: "pixel_cat",
                        presence: .offline
                    )],
                    inviteCodeHint: "AB••••",
                    inviteVersion: 1
                )]
            ),
            currentUserID: UUID()
        )

        XCTAssertEqual(model.rooms[0].members[0].presence, .typing)
        XCTAssertEqual(model.pixelWorldMembers.first?.presence, .online)
        XCTAssertEqual(model.pixelWorldMembers.first?.isTyping, true)
    }

    func testJoinedRoomIsResolvedAgainstFreshSnapshotForRealtimePublication() {
        let previousRoomID = UUID()
        let joinedRoomID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = previousRoomID
        let model = AppModel(preferences: preferences)
        let previousRoom = Room(
            id: previousRoomID,
            name: "기존 그룹",
            ownerID: UUID(),
            members: [],
            inviteCodeHint: "AB••••",
            inviteVersion: 1
        )
        let joinedRoom = Room(
            id: joinedRoomID,
            name: "참여한 그룹",
            ownerID: UUID(),
            members: [],
            inviteCodeHint: "CD••••",
            inviteVersion: 1
        )
        model.apply(
            snapshot: BackendSnapshot(profile: nil, rooms: [previousRoom]),
            currentUserID: UUID()
        )

        model.preferences.activeRoomID = joinedRoomID

        XCTAssertEqual(model.activeRoom?.id, previousRoomID)
        XCTAssertEqual(
            model.resolvedActiveRoomID(in: [previousRoom, joinedRoom]),
            joinedRoomID
        )
        XCTAssertEqual(model.resolvedActiveRoomID(in: [joinedRoom]), joinedRoomID)
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

    func testConnectionStatusSeparatesTransportFromRecoveryReadiness() {
        XCTAssertFalse(BackendConnectionStatus(
            transportConnected: false,
            recoveryReconciled: true
        ).isReady)
        XCTAssertFalse(BackendConnectionStatus(
            transportConnected: true,
            recoveryReconciled: false
        ).isReady)
        XCTAssertTrue(BackendConnectionStatus(
            transportConnected: true,
            recoveryReconciled: true
        ).isReady)
    }

    func testActiveRoomReconnectDoesNotResetInactiveRoomPresence() {
        let userID = UUID()
        let activeRoomID = UUID()
        let inactiveRoomID = UUID()
        let inactiveFriendID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = activeRoomID
        let model = AppModel(preferences: preferences)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "나", characterID: "pixel_hamster"),
                rooms: [
                    Room(
                        id: activeRoomID,
                        name: "활성",
                        ownerID: userID,
                        members: [RoomMember(
                            userID: userID,
                            nickname: "나",
                            characterID: "pixel_hamster",
                            presence: .online
                        )],
                        inviteCodeHint: "AB••••"
                    ),
                    Room(
                        id: inactiveRoomID,
                        name: "비활성",
                        ownerID: inactiveFriendID,
                        members: [RoomMember(
                            userID: inactiveFriendID,
                            nickname: "친구",
                            characterID: "pixel_cat",
                            presence: .online
                        )],
                        inviteCodeHint: "CD••••"
                    ),
                ]
            ),
            currentUserID: userID
        )

        model.setActiveRoomRealtimeConnected(false)

        XCTAssertEqual(model.rooms[0].members[0].presence, .reconnecting)
        XCTAssertEqual(model.rooms[1].members[0].presence, .online)
    }

    func testProfileDraftSurvivesCharacterResponseAndUnrelatedSnapshot() {
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "확정닉", characterID: "pixel_hamster"),
                rooms: []
            ),
            currentUserID: userID
        )
        model.nickname = "편집중"

        model.apply(profile: Profile(
            id: userID,
            nickname: "확정닉",
            characterID: "pixel_cat"
        ))
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "확정닉", characterID: "pixel_cat"),
                rooms: []
            ),
            currentUserID: userID
        )

        XCTAssertEqual(model.nickname, "편집중")
        XCTAssertEqual(model.confirmedNickname, "확정닉")
        XCTAssertEqual(model.selectedCharacterID, "pixel_cat")
        XCTAssertTrue(model.hasNicknameChanges)
    }

    func testNicknameDirtyStateUsesNormalizedDraftAndValidation() {
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "사이디", characterID: "pixel_hamster"),
                rooms: []
            ),
            currentUserID: userID
        )

        model.nickname = "  사이디  "
        XCTAssertFalse(model.hasNicknameChanges)
        XCTAssertTrue(model.nicknameDraftIsValid)
        model.nickname = "한"
        XCTAssertTrue(model.hasNicknameChanges)
        XCTAssertFalse(model.nicknameDraftIsValid)
    }

    func testCharacterRequestKeepsConfirmedSelectionUntilSuccessAndBlocksDuplicates() {
        let userID = UUID()
        let model = AppModel(preferences: .defaults)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "사이디", characterID: "pixel_hamster"),
                rooms: []
            ),
            currentUserID: userID
        )

        XCTAssertTrue(model.beginCharacterEquipmentRequest(characterID: "pixel_cat"))
        XCTAssertEqual(model.selectedCharacterID, "pixel_hamster")
        XCTAssertEqual(model.pendingCharacterID, "pixel_cat")
        XCTAssertFalse(model.beginCharacterEquipmentRequest(characterID: "pixel_penguin"))

        model.endCharacterEquipmentRequest()
        XCTAssertEqual(model.selectedCharacterID, "pixel_hamster")
        model.apply(profile: Profile(
            id: userID,
            nickname: "사이디",
            characterID: "pixel_cat"
        ))
        XCTAssertEqual(model.selectedCharacterID, "pixel_cat")
    }

    func testProfileApplyChangesIdentityWithoutDiscardingFriendPresence() {
        let roomID = UUID()
        let userID = UUID()
        let friendID = UUID()
        var preferences = AppPreferences.defaults
        preferences.activeRoomID = roomID
        let model = AppModel(preferences: preferences)
        model.apply(
            snapshot: BackendSnapshot(
                profile: Profile(id: userID, nickname: "이전닉", characterID: "pixel_hamster"),
                rooms: [Room(
                    id: roomID,
                    name: "친구들",
                    ownerID: userID,
                    members: [
                        RoomMember(
                            userID: userID,
                            nickname: "이전닉",
                            characterID: "pixel_hamster",
                            presence: .offline
                        ),
                        RoomMember(
                            userID: friendID,
                            nickname: "친구",
                            characterID: "pixel_cat",
                            presence: .offline
                        )
                    ],
                    inviteCodeHint: "AB••••"
                )]
            ),
            currentUserID: userID
        )
        model.connectionState = .online
        model.updatePresence(roomID: roomID, userID: friendID, state: .online)

        model.apply(profile: Profile(
            id: userID,
            nickname: "새닉네임",
            characterID: "pixel_penguin"
        ))

        XCTAssertEqual(model.connectionState, .online)
        XCTAssertEqual(model.nickname, "새닉네임")
        XCTAssertEqual(model.selectedCharacterID, "pixel_penguin")
        XCTAssertEqual(
            model.rooms[0].members.first(where: { $0.userID == userID })?.nickname,
            "새닉네임"
        )
        XCTAssertEqual(
            model.rooms[0].members.first(where: { $0.userID == friendID })?.presence,
            .online
        )
    }

    func testNetworkAvailabilityTransitionsCoalesceDuplicateUpdates() {
        var state = NetworkAvailabilityState()

        XCTAssertEqual(state.update(.available), .initialAvailable)
        XCTAssertEqual(state.update(.available), .unchanged)
        XCTAssertEqual(state.update(.unavailable), .becameUnavailable)
        XCTAssertEqual(state.update(.unavailable), .unchanged)
        XCTAssertEqual(state.update(.available), .becameAvailable)

        var initiallyOfflineState = NetworkAvailabilityState()
        XCTAssertEqual(initiallyOfflineState.update(.unavailable), .becameUnavailable)
        XCTAssertEqual(initiallyOfflineState.update(.available), .becameAvailable)
    }

    func testReconnectRequiresFreshRemotePresenceInsteadOfRestoringStaleOnline() {
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

        model.setActiveRoomRealtimeConnected(false)
        XCTAssertEqual(model.rooms[0].members[0].presence, .reconnecting)
        model.setActiveRoomRealtimeConnected(true)
        XCTAssertEqual(model.rooms[0].members[0].presence, .offline)
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

        model.setActiveRoomRealtimeConnected(false)
        XCTAssertEqual(model.rooms[0].members[0].presence, .reconnecting)
        model.setActiveRoomRealtimeConnected(true)
        XCTAssertEqual(model.rooms[0].members[0].presence, .offline)
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

    func testCharacterThrowCooldownIsGlobalPerActorAtHalfASecond() {
        let actor = UUID()
        var cooldown = CharacterThrowCooldown()

        XCTAssertTrue(cooldown.accept(actorUserID: actor, uptime: 10))
        XCTAssertFalse(cooldown.accept(actorUserID: actor, uptime: 10.499))
        XCTAssertTrue(cooldown.accept(actorUserID: actor, uptime: 10.5))
        XCTAssertTrue(cooldown.accept(actorUserID: UUID(), uptime: 10.5))
        XCTAssertFalse(cooldown.accept(actorUserID: actor, uptime: .infinity))
        XCTAssertEqual(CharacterThrowCooldown.duration, 0.5)
    }

    func testCharacterThrowTargetIgnoresPresenceButRejectsCurrentUser() {
        for presence in PresenceState.allCases {
            XCTAssertTrue(CharacterThrowTargetPolicy.canTarget(PixelWorldMember(
                id: UUID(), nickname: "친구", characterID: "pixel_hamster",
                presence: presence, isTyping: presence == .typing, isCurrentUser: false
            )), "\(presence)")
        }
        XCTAssertFalse(CharacterThrowTargetPolicy.canTarget(PixelWorldMember(
            id: UUID(), nickname: "나", characterID: "pixel_hamster",
            presence: .online, isTyping: false, isCurrentUser: true
        )))
    }


    func testLatestRoomSelectionWinsWithoutApplyingCompletedStaleSwitch() async {
        let roomB = UUID()
        let roomC = UUID()
        let bStarted = expectation(description: "B 전환 시작")
        let cCommitted = expectation(description: "C만 적용")
        let gate = AsyncTestGate()
        let probe = SerialExecutionProbe<UUID>()
        var committedRoomIDs: [UUID] = []

        let pipeline = RoomSwitchPipeline(
            debounce: .milliseconds(5),
            performSwitch: { roomID in
                await probe.begin(roomID)
                if roomID == roomB {
                    bStarted.fulfill()
                    await gate.wait()
                }
                await probe.end()
                return []
            },
            restoreCommittedRoom: {},
            operationChanged: { _ in },
            committed: { roomID, _ in
                committedRoomIDs.append(roomID)
                if roomID == roomC { cCommitted.fulfill() }
            },
            failed: { _, error, _ in
                XCTFail("예상하지 못한 전환 실패: \(error)")
            }
        )

        pipeline.request(roomB)
        await fulfillment(of: [bStarted], timeout: 1)
        pipeline.request(roomC)
        await gate.open()
        await fulfillment(of: [cCommitted], timeout: 1)

        let switchProbe = await probe.snapshot()
        XCTAssertEqual(committedRoomIDs, [roomC])
        XCTAssertEqual(switchProbe.maximumConcurrent, 1)
        XCTAssertEqual(switchProbe.started, [roomB, roomC])
        pipeline.cancel()
    }

}

private actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor SerialExecutionProbe<Value: Sendable & Equatable> {
    private(set) var started: [Value] = []
    private(set) var maximumConcurrent = 0
    private var concurrent = 0

    func begin(_ value: Value) {
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        started.append(value)
    }

    func end() {
        concurrent -= 1
    }

    func snapshot() -> (started: [Value], maximumConcurrent: Int) {
        (started, maximumConcurrent)
    }
}
