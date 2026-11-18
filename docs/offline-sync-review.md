# Offline return and manual synchronization

Online return replaces stale canvas geometry from server instead of sending it as a new
local operation. Old canvas outbox is cleared only after a successful read; the prior
online/offline snapshots and outbox are retained in the scoped offline-recovery preference.
This is a device-local recovery copy, not server backup or canvas revision history.
Existing overwritten layouts cannot be assumed recoverable without inspecting device copies.

Paid editable owned workspaces expose 동기화 above 휴지통. The page pauses automatic canvas
sends/refresh, reads the current server revision and requires a choice for every difference:
- Local: overwrite that object's differing fields on server, including explicit deletions.
- Server: discard local changes and use server data, without a server write for that choice.
Current online drafts are reviewed before pending offline data when both exist. Canceling an
offline review retains it. Successful offline review updates its baseline to the resulting
server snapshot. Viewport/search preferences are excluded. Geometry is grouped by canvas/object.

Every write uses offlineReconcile, authenticated owner access and the compared workspace
revision under the server workspace lock. Concurrent server changes require a fresh review.
The old automatic offline delta helper also rejects overlapping baseline/local/server edits.

Backoffice account lookup searches both name and email (escaped substring matching), shows
at most five server results in the existing assist overlay under the input, and supports
arrow/Enter selection. Subscription dates end at the final microsecond of the chosen Korean
date; display is yyyy-mm-dd 23:59:59, including 9999-12-31 without year overflow.

## Temporary connection loss in online workspaces

Transport failures (not HTTP 401/403/500) retain the signed-in account's current
workspace cache and persist its last sync baseline. Saves remain local. A
10-second retry timer reads the server after connectivity returns. Distinct item
changes merge automatically; edit/edit and edit/delete collisions open the sync
review page with nonconflicting changes preselected. Dismissing that page keeps
changes locally and pauses background writes until the user reviews them.

The recovery baseline survives application restart. A cached workspace catalog
allows previously used paid workspaces to open offline; an uncached workspace
still needs an initial online load. Uncached attachments also require a connection.
Retries defer while an input draft or canvas gesture is active. Server revision
checks protect reconciliation against changes made after the comparison, and
workspace edit permissions still apply to both owners and invited editors.
