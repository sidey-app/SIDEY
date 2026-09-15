# SIDEY Repository Instructions

## Project context

SIDEY is a macOS/Windows desktop overlay ambient messenger for private groups of up to twelve close friends. Each on-screen 2D pixel animal represents a real friend and shows presence, typing, and short text messages.

Read these files before product or implementation work:

1. `docs/DECISIONS.md` — authoritative confirmed decisions and open questions
2. `docs/PRODUCT_SPEC.md` — detailed product scope and technical direction

Before editing public landing, store, policy, or checkout pages under `website/`, read `.agents/skills/sidey-public-web/SKILL.md`.

If the documents conflict, confirmed decisions in `docs/DECISIONS.md` win.

## Backend ownership

Backend implementation lives in the private [sidey-app/sidey-backend](https://github.com/sidey-app/sidey-backend) repository. Supabase migrations, RLS, Edge Functions, App Store verification, database tests, operational metrics and backend deployment tools must be changed and verified in a current checkout of that repository under its own `AGENTS.md` and CI. Do not recreate backend implementation here or deploy from historical SIDEY copies.

Keep native Supabase clients, the public website and client-facing product contracts here. The canonical product and asset definitions remain `assets/v1/commerce-catalog.json` and `assets/v1/manifest.json`; backend catalog updates use a reviewed public commit snapshot with recorded provenance. This repository generates only public web and native mirrors. See [docs/BACKEND.md](docs/BACKEND.md) for repository boundaries and catalog handoff. Repository migration does not itself deploy backend changes or remove previously public Git history.

## Work lifecycle

Before creating a commit, use [.agents/skills/sidey-commit/SKILL.md](.agents/skills/sidey-commit/SKILL.md). Write commit subjects as `type(scope): 한국어 설명`, using the skill's distribution scopes; descriptions and optional bodies must be in Korean.

Use [.agents/skills/sidey-workflow/SKILL.md](.agents/skills/sidey-workflow/SKILL.md) and `scripts/workflow.py` for task start, resume, integration and app opening. Default completion includes reviewed PR integration and refreshing the primary main checkout; app-affecting changes also require build/run provenance verification. Public releases, store uploads and production deployments remain separate.

Codex-assisted new commits must include `Co-authored-by: codex <codex@openai.com>` while preserving the human Git author. Install the repository hook once per clone with `python3 scripts/setup_codex_attribution.py`; it also covers linked worktrees. See the commit skill for attribution exceptions and verification. Do not rewrite existing history to add attribution.

## Automatic parallel agent work

- The coordinating agent must proactively create subagents when independent work can run alongside its own useful work and the expected time savings or verification benefit outweigh creation and coordination costs. This is an explicit instruction to delegate qualifying SIDEY work; do not wait for the user to request parallel agents or ask for confirmation each time.
- Use the minimum useful number of agents within the environment's available limits. Independent features, separate investigations, and verification that does not depend on unfinished changes are suitable candidates. Handle small edits, overlapping file changes, and dependent steps directly or sequentially.
- Follow the user's explicit request for solo or sequential work. If delegation is unavailable or capacity is exhausted, continue feasible work directly. All agents remain within the authorized task, platform boundaries, and the environment's permissions.
- Use [sidey-workflow](.agents/skills/sidey-workflow/SKILL.md#parallel-work-coordination) for file ownership, worktree selection, verification, and integration. Briefly explain the reason for parallel work and the assignments when starting it. The coordinating agent owns the final review and completion report.

## Branch and platform isolation

- Use `macos/<topic>` for macOS implementation, `windows/<topic>` for Windows implementation, and `shared/<topic>` for shared documentation, website, client protocol, or repository-wide work.
- Treat `main` as an integration and release branch. Do not implement features directly on `main`.
- Before editing, verify the current branch and working tree. Before committing or pushing, inspect every changed path relative to the branch base.
- A `macos/*` branch must not edit, move, delete, format, generate, build, test, or release Windows implementation files. This includes `windows/**` and Windows-specific workflows, installers, assets, and documentation.
- A `windows/*` branch must not edit, move, delete, format, generate, build, test, or release macOS implementation files. This includes `macos/**` and macOS-specific scripts, workflows, packages, assets, and documentation.
- Shared changes belong on `shared/*`. Do not mix new shared-file edits into a platform implementation commit. Land the shared change independently, then merge or cherry-pick that reviewed commit into the platform branch that needs it.
- If a platform task reveals work needed on the other platform, record a follow-up instead of implementing it on the current branch.
- Do not switch or clean a dirty worktree owned by another task or agent. Create an isolated worktree on the correctly prefixed branch.
- macOS remains the reference implementation. Windows follows through its own branch without rewriting or opportunistically modifying macOS code.

## Non-negotiable rules

- The product name is `SIDEY`. Do not call it `같이온` or `같이ON` in product copy, code, package identifiers, or new documentation.
- Do not expand the MVP without an explicit product decision. In particular, do not add mobile/web clients, public discovery, groups over twelve, media/file transfer, calls, AI companions, or user-uploaded avatars.
- Keep the working macOS client native in SwiftUI/AppKit/SpriteKit and build the Windows client natively in C#/.NET/WinUI 3 with Win32 platform services. Do not reintroduce Godot.
- Build Windows on the shared `PixelCharacterCatalog` renderer with all five current characters from the first functional build. Validate the same renderer in an internal one-character hamster mode before promotion; do not create a hamster-only product implementation or expose that mode in Release builds. The existing macOS five-character client remains untouched while Windows validation runs.
- Treat Postgres as the source of truth for messages. Presence is for connection/activity state; Broadcast is for transient events such as typing.
- Enforce room membership, the twelve-member limit, and the five-room-per-user limit on the server. Client-only validation is insufficient. Nicknames and character choices may be duplicated.
- Apply Supabase RLS to user and room data. Never store invite codes in plaintext.
- Do not claim end-to-end encryption unless E2EE has actually been designed, implemented, and verified.
- Never collect screen contents, active application lists, keys typed in other applications, mouse coordinates, file contents, microphone audio, or camera video.
- The only global activity signals in scope are elapsed time since last system input and screen lock state. Typing status comes only from the SIDEY input field.
- Default overlay mode passes pointer input through to applications behind it. Interaction must be an explicit mode.
- Do not promise that the overlay appears above secure OS screens, DRM applications, elevated applications, or every exclusive-fullscreen game.

## Engineering priorities

Prefer correctness, long-running stability, low resource usage, privacy, and cross-platform behavior over visual polish or feature count. Keep pixel assets at 24×24 logical pixels with ten deterministic frames, integer nearest-neighbor scaling, no real-time shadows, and 30 FPS by default.

When a product decision is made, update `docs/DECISIONS.md` in the same change. When behavior or scope changes, update `docs/PRODUCT_SPEC.md` as well.
