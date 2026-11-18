# Local storage audit — 2026-11-19

## Storage map

- Workspace JSON: owner/workspace scoped SharedPreferences; active notes, documents, trash, memberships, colors, layout. Version 1 remains unchanged.
- Graph JSON: separate layout snapshot used on restoration. Full content snapshots also contain layouts for sync/export compatibility.
- Previous snapshot / beforeImport: recovery copies, intentionally retained.
- Sync checkpoint: per-item base, cursor and last synchronized snapshot. Offline conflict resolution requires these; not disposable cache.
- Document drafts: scoped JSON including merge base and unsaved text. Never purge as an optimization.
- Photos/audio: binary Hive lazy box (IndexedDB on web), outside workspace JSON. Export deliberately bundles referenced binaries as base64; ordinary local saves do not.

## Changes

1. Full content save passes the captured graph JSON to the same queued storage write. Previously a second writeGraphLayouts task reloaded preferences, decoded the entire content JSON, replaced layouts and encoded the entire content again. The new path writes both snapshots without reparsing the full content and notifies once.
2. Concurrent Inbox persistence requests share a pending drain. Same-event requests capture only the newest state; edits while a write is pending request another pass. Callers await the drain rather than a backlog of intermediate states.
3. Identical document drafts skip writes and change notifications; identical theme writes are skipped. Suspended workspace draft writes still fail.

No schema migration, user-data deletion, backup purge, or omission of default fields. Omitting fields without canonicalizing sync comparisons can create false conflicts or deletion semantics, so JSON field names and payload semantics stay compatible.

## Measurement and limits

Synthetic fixture: 5,000 text memos, 1,852,852 UTF-8 bytes. Median of seven redundant decode/replace/encode runs in Flutter VM test: 32.959ms in the first run. This entire extra pass is removed from combined full saves. Timing varies; it is not measured browser FPS and not a claim about total save latency.

Remaining costs: initial full snapshot encoding, layout-only full snapshot patching, SharedPreferences reload (needed for cross-tab guest-claim safety), sync checkpoint serialization, rendering/rebuilding cards and links. Changing storage to normalized IndexedDB/Hive records requires coordinated sync/export/restore changes and migration; this patch does not pretend to implement it. No access to the user's live browser profile or actual local dataset was available.

Regression coverage: combined snapshot/layout writes, previous backup, no-op writes, owner isolation, draft saved marker, suspended workspace, existing draft/sync/canvas/content/media-backup suites. A legacy storage UI test still looks for the retired label `환경설정`; its persistence/reopen assertions passed before that stale selector failed.
