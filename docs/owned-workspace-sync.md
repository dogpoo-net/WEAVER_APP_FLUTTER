# Owned workspaces and incremental synchronization

Guest generations and authenticated account caches use distinct immutable local
namespaces. Legacy unlabelled data is quarantined unless the old guest flag proves
it is guest data. Do not promote a remembered Google marker to authentication.
Google ID tokens are exchanged for verified server sessions.

A guest source is sealed before its first network claim. A durable target-account
intent and server-side unique claim protect retries and response loss. New guest
entry uses a different generation. The source is cleared only after server commit
and a successful account-local write/checkpoint. Unsynchronized account data stays
in its account namespace after logout/expiry; confirmed synchronized caches can be
cleared. No account-to-account import/export UI is provided.

Cloud requests use authenticated session identity, never a caller-provided email.
The legacy public email-address backup routes return 410. Existing server backups
are migrated on authenticated access, using that account's verified email.

Text, document, folder, box and individual layout coordinates are separate items.
Changes carry a base revision; same-item conflicts return 409 instead of overwrite.
Photos/audio upload separately before referencing items. Save requests return only
acknowledged changes. Remote changes are read when opening the workspace or when
explicitly reloading; active editors are not overwritten in the background.

Quick memo saves sync immediately. Documents and both canvas views sync only on
Save/Ctrl+S (Cmd+S also supported). There is no 10-second automatic network timer.
Local persistence remains active. Failed network saves keep local data and show an
error rather than success. Other-device conflicts require an explicit choice to
reload server data; local recovery is retained until that confirmation.

Media bytes live under /home/ocaptain/resource/{image,audio}/<account UUID>/ with
hashed filenames. DB records relative paths, media type, size and SHA-256. Reads
require authenticated workspace membership. The server's current 64 MiB workspace cap includes content, media and document history;
paid tiers and billing are not implemented by this migration.

Measured from three existing server backup samples (not current unsaved browser
state): diagram layout 1193–3382 bytes, box canvas 860–3050 bytes, all per-box
layouts 3907–17457 bytes. A one-position delta request example is 186 UTF-8 bytes,
excluding HTTP/TLS and response overhead. At 1000 concurrently dragging users and
one release per 5 seconds: 200 requests/second and ~37.2 KB/second of delta request
bodies. This is a traffic calculation, not a measured server throughput claim.


Shared workspaces use the owner's user UUID as workspace ID. Every read, write,
media and history route checks membership. A workspace row lock serializes member
changes, seat reservations and writes. Free workspaces have two editor seats,
including their owner; unexpired pending editor invitations reserve the second
seat. Viewers use no editor seat. Only owners manage invitations and roles.
Invites expire after seven days, require the invited verified email on acceptance,
and can be revoked. Joining never removes one's personal workspace. Each joined
workspace has a separate account-local namespace. Viewer UI exposes no editing.

Document history starts at legacy migration/import or the first server save.
Every changed body version records server-authenticated actor, UTC timestamp,
before/after content and line/offset diff. Add/remove counts use Unicode code
points (including markup and whitespace), so emoji surrogate pairs count once.
Unchanged bodies and rejected stale writes create no extra version. History is
paged in batches of 50 and readable by workspace members. Historical restoration
and realtime collaboration are not included. Internal project identifiers and
serialized keys remain compatible; only displayed terminology changes to 문서.

Rollout: apply 007 and 008 additive migrations, deploy backend before frontend.
Old email-only backup routes intentionally return 410 after this rollout. Retain
legacy backup rows for recovery. No production HTTP smoke checks are performed
when the user has requested deployment without response validation.

Existing document editors obtain an exclusive 120-second lease, renewed every
30 seconds and released on close. Another editor sees read-only content. Losing
the lease blocks saves without discarding the current input. Forced tab closure
recovers after lease expiry. Lease acquisition is authorized and serialized with
saves; actor plus per-editor token must match. Optimistic revisions still protect
stale content after a lease is transferred. Lease renewal does not save content.
