# Live workspace reads and edit locks

The visible signed-in app requests `/workspace/status` every 2 seconds. The
response contains a workspace revision and states of observed edit leases only.
It downloads `/workspace/read` deltas when the revision changes. Hidden,
paused and inactive applications stop polling; failed checks back off to 30s.
One active device makes 30 checks/minute (1,800/hour); 100 devices ~50 requests/s,
1,000 devices ~500/s, excluding changes, authentication refresh and saves. These
are request counts, not measured capacity. Session/permission validation still
uses the database. Large populations should use authenticated event notification
or long polling before scaling to thousands of concurrently active clients.

Quick memo saves and thought/classification mutations sync independently of
manual-save documents and layouts. A document save sends that document; canvas
save sends only its layout scope. Viewing and polling never uploads editor
buffers. JSON key order and equivalent numeric encodings compare equal.

Existing WEAVER_DOCUMENT_LOCK rows also represent `canvas:diagram` and
`canvas:boxes` (all filtered views share the corresponding workspace lock).
Migration 011 adds `shared_editing`. Initially an editing screen owns an
exclusive 120-second lease, renewed every 30 seconds while active. Confirming
unlock permanently opens that resource for every workspace editor, including
the original editor and subsequently opened screens. Closing a screen does not
relock a shared resource. Viewer permissions remain read-only.

Document and canvas saves use last-server-write-wins; stale base revisions do
not reject authorized editor saves. Explicit scoped saves send the full resource
snapshot, including unchanged values. The server tombstones any existing scope
entries absent from that snapshot, so an empty or smaller canvas genuinely
replaces an older larger layout. Other scopes remain unchanged. Transactions
serialize competing saves. A save queued behind a read captures the explicit
snapshot so that the user's already-requested save is not silently discarded.

Server reads use the server version except for actively open document editors
and canvases. While any of those three editors is mounted, automatic status
checks continue for locks, but automatic data reads stop. The editors do not
subscribe to global data refresh notifications. Explicit reads from nested views
preserve active editor resources in the local snapshot; only the manual refresh
button replaces the active resource. Canvas resume does not refetch data. Other item revision conflicts trigger a fresh server read and update
the UI rather than abandoning synchronization. Genuine transport, permissions,
and server errors are still surfaced. Guest source ownership checks remain.

The unlock confirmation has three explicit lines; U+2060 inside each whitespace-
delimited word prevents Korean syllable wrapping while retaining word boundaries.
An unmodified semantics label exposes the original sentences to assistive tools.

2–3 seconds is a foreground target after a successful server save, not a latency
SLA. Network delays, attachment downloads, offline clients and open input dialogs
may delay visible updates. Native apps need a new build for these changes.
