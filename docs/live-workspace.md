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
Lease tokens identify the editing screen, including separate devices of one
account. Leases last 120 seconds and renew every 30 seconds in the foreground.
Status checks detect takeover within the polling interval. Backend save checks
both the actor and token. Releases are conditional on the token, and renewal
cannot reclaim a missing lease. No schema migration is needed.

The confirmation action explicitly takes over the lease, rebases only the
selected resource's server revision, and preserves that screen's local snapshot.
Its next explicit save can therefore replace the saved resource. An older
editor cannot save under the transferred lease. A refresh confirmation replaces
only the chosen resource, retains unrelated drafts, and checks the lease again.
Read-only viewers follow server data. Editors that lose a lease retain their
pending snapshot until explicit refresh or takeover; their drafts are never
silently overwritten. Closing an editor clears local observation even if the
network release fails; the server lease then expires naturally.

2–3 seconds is a foreground target after a successful server save, not a latency
SLA. Network delays, attachment downloads, conflicts, offline clients and open
input dialogs may delay visible updates. iOS background suspension cannot
provide this latency. Native apps need a new build to get this implementation.
