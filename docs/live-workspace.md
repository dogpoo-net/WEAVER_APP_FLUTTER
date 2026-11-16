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

## SSE notifications (2026-11-16)

Workspace changes now use an authenticated streaming POST (`workspace/events`).
The standard HTTP/SSE protocol also supports the planned Cloudflare Workers
migration; no Spring-specific SDK or URL credentials are used. Browser fetch
streams cookies/proof headers; native HTTP streams use the existing bearer token.

One connection per mounted workspace receives `ready`/`change` invalidations and
`ping` heartbeats. Healthy connections disable the old three-second status polling.
Events coalesce for 200ms, then use existing status/delta reads. Notes on the home
screen and thought tab, canvas layouts and comment counts share this mechanism.
Local pending canvas edits and manual document save/three-way merge remain intact.
An open editor or modal defers refresh; the pending invalidation is retried locally
without querying until it is safe to apply.

Backgrounding closes the stream. Resume/reconnect reconciles revisions; a 45s
silent-stream watchdog, exponential reconnect with jitter, and 15s disconnected-only
fallback polling cover failures. Canvas upload still waits 750ms after activity.
There is no claim of guaranteed subsecond delivery on an offline/backgrounded device.

Tests cover chunked SSE parsing, reconnect/idle timeout, cancellation, no idle
polling, home/thought changes and deferred editor refresh. Server fan-out currently
uses a single-process test implementation; migrate that service to Durable Objects
before distributing the API across Workers instances.

## Stable overview refresh and grid preferences (2026-11-16)

Overview delta reads no longer replace the mounted tab with a loading Scaffold or
increment the canvas identity. Search, scroll and zoom remain mounted during a
refresh. Clicking the already-selected tab does not initiate another read.
Visible but unfocused windows (`inactive`) continue applying SSE invalidations;
only hidden/paused states suspend the connection. Focus alone does not reload the
page. Actual resume still reconciles missed revisions through the existing stream.

Thought and photo grid column counts are independently persisted in device-local
preferences, with synchronous in-session cache and display-only viewport clamping.
Tests cover refresh without disposal, search/scroll/zoom preservation, independent
column preferences across tab recreation/cold cache, and live badge updates while
inactive without a subsequent click.

The older all_thoughts_test/thought_views_test suites had five failures on both the
previous deployed c3818bf checkout and this change (missing asynchronous preference
setup/initial UI). Those unchanged baseline failures are not counted as passing
validation for this update.
