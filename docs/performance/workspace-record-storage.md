# Workspace record storage (2026-11-19)

## Persistent layout

`workspace-records-v1` is a Hive database, separate from the binary attachment box. On web it uses IndexedDB; native apps use Hive files in the existing `weaver-media` application directory. No new plugin is required.

- Settings and authentication plumbing continue to use their existing stores.
- Workspace contents, graph layouts, document drafts, sync checkpoints, canvas outbox, offline baselines/recovery, previous snapshots and pre-import recovery are routed out of SharedPreferences.
- Record keys contain the encoded account/workspace namespace, JSON path (including object ID) and content version hash. No cross-account deduplication is performed.
- Memo/document list entries and synchronization item values are individual records. Coordinate maps are split by key.
- List/map indexes larger than 128 entries are paged. The root manifest references pages rather than repeating every memo reference in one large value. Order, empty containers, nulls, IDs and nested JSON-string snapshots round-trip.

## Writes and recovery

New chunks are written and flushed before the manifest commit. Readers continue to see the old manifest until the single commit. Obsolete chunks are removed afterwards; failed garbage collection does not turn a committed save into a reported failure. On startup, orphan chunks from interrupted writes are collected only after validating all committed references.

Normal Inbox saves use `WorkspaceSnapshot.data` / `WorkspaceStorage.writeSnapshot`: capture immutable model data, compare per-record representations, save changed records and index pages. The previous version is copied through records, without assembling/parsing a full JSON snapshot. Identical saves retain the real previous version. Graph lists/maps are copied when captured so edits during pending writes cannot mutate a save in progress.

A small four-entry snapshot cache serves legacy synchronous readers. Sync/export/import APIs still accept and return version-1 JSON. They may assemble a snapshot when needed; the backend wire schema has not changed. Layout-only saves and some synchronization paths still construct or parse full snapshots. Record comparison still visits the captured model: this is not a complete dirty-ID-only synchronization engine, nor a guarantee of better FPS. Hive's normal box keeps records in memory; this is not fully lazy loading of all account data.

## Migration and concurrency

At application initialization, each legacy content key is copied to the record database. All referenced values are read back before removing that legacy key. Invalid JSON or missing records aborts startup with a retry screen; the app must not silently open an empty workspace. Migration is resumable per key, including recovery copies. Attachments remain in their existing box.

New web clients coordinate record operations via Web Locks. A small revision marker in localStorage lets other clients reopen the Hive cache under that lock before their next queued operation. Native Hive owns its file lock. This protects database consistency, not semantic merge of simultaneous edits (existing sync/merge policies still apply). Old-version tabs do not participate: close old tabs before first migration. After migration, old app versions cannot read the new database; use the current version's export before downgrading.

## Verification

Tests cover lossless reconstruction, one-record edits, reordered IDs, paged maps/lists, owner isolation, draft/previous-version semantics, reopen, failed manifest commits, orphan cleanup, malformed migration input, and restart of the existing sync engine. Chromium test exercises actual IndexedDB, Web Locks, migration, reopen and deletion. Existing draft, sync, canvas, local-save and attachment-backup regressions are also run.

Synthetic 5,000-memo edit: changed memo + one index page = 13,603 bytes; root commit index = 4,184 bytes. These are serialized value bytes for one content namespace, excluding database keys, previous-version copy, checkpoints, filesystem overhead and initial migration. The previous unpaged root index alone was 529,988 bytes. This measures write granularity, not end-user frame rate.
