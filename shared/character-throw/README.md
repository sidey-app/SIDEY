# Character throw contract

This directory is the platform-neutral source of truth for SIDEY's transient
character throw interaction.

## Event

```text
CharacterThrowEvent(
  id: UUID,
  roomID: UUID,
  actorUserID: UUID,
  targetUserID: UUID,
  sourceCharacterID: String
)
```

Clients call:

```text
broadcast_character_throw(
  p_room_id: UUID,
  p_realtime_epoch: Int64,
  p_event_id: UUID,
  p_target_user_id: UUID
)
```

The server authenticates the actor, checks the current room epoch and both
memberships, rejects self-targeting, reads `source_character_id` from the
actor's profile, enforces 20 attempts per sender per 10 seconds, and emits a
private `character_throw` Broadcast. Coordinates are never transmitted.

The payload is validated by `character-throw-event.schema.json`. Unknown
schema versions or character IDs must be ignored or rendered with the fallback
declared in `v1/manifest.json`; they must not disconnect a client.

## Assets

`v1/manifest.json` records the user-approved source PNG paths, frame ranges,
character-to-object mapping, fallbacks, and SHA-256 values. These files are
shared sources, not runtime bundle paths. Platform branches copy or transform
them into platform-specific resources without changing their approved pixels.
