# Overview library

The 전체 보기 screen has horizontally scrollable tabs in this order: documents,
thoughts, diagram, memo boxes, photos, audio, geolog. Tab content mounts on demand;
attachment thumbnails load lazily at bounded decode resolution. Attachment taps
open their owning thought, preserving the existing photo/audio/location detail UI.
The photo tab currently covers supported photo attachments; video capture and
playback are not part of this change.

Documents filter by title/body and sort by most recent known modification time.
Opening a document shows its formatted read view. The edit action opens the editor
and obtains a lease only then. Desktop reference-panel toggles sit at the right
edge; mobile retains the stacked bottom controls.

Item author and server modification time come from authenticated server metadata
(migration 009). The original author is retained when another editor saves. Legacy
items without recorded authors/times show that information as unavailable rather
than guessing. Attachment creation dates are the owning thought's recorded time.
Locally saved document changes retain an optional updatedAt field in version-1
snapshots; existing serialized document identifiers remain unchanged.

Workspace selection is a modal launched from the first settings row, followed by
invitation management. Reset precedes the logout section; logout and all-device
logout sit between dividers immediately above licenses. Advanced sync actions are
under 동기화 관리. Server reload still asks before replacing unsynchronized local
edits. These operations are restricted to the active workspace, not cross-account
import/export.

Theme selection is shared across routes via ThemeControls. The settings title row
contains the theme action and X close action; the main toolbar theme action and
settings footer close button are removed. Palette changes keep the active dialog
and document/draft state intact.
