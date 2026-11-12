# Account profiles

The main avatar and Settings account header open the profile page. Profiles belong
to the authenticated account, independent of the selected workspace. Names and
custom photos persist on the server. Provider photos are read only from verified
OAuth responses; custom photos take priority. Failed/missing images fall back to
one of six bundled doodles, randomly assigned once per account in the database.

Original generated artwork was split into `assets/branding/profile/face_0.png`
through `face_5.png` (smile, neutral, side-eye, crying, angry, tired). Deploy the
same six files to `/home/ocaptain/resource/profile/images/default/`. User uploads
are stored under `/home/ocaptain/resource/profile/images/<account UUID>/` and are
read through the authenticated profile API, not a public directory listing.

Profile photos accept PNG/JPEG up to 2 MiB and 4096×4096. The server crops to a
centered square and re-encodes at 512×512, stripping original metadata.

Password changes require an eight-digit email code, valid for ten minutes and
five attempts, with a minimum one-minute resend interval. Completion revokes all
sessions. Tests mock email delivery. Apply DOGPOO_API migration 010 before release.
Existing social-linked accounts have no reliable historical password-capability
flag; a successful email/password login enables their password-change option.
Social-only accounts do not expose that option.

Social photos for existing accounts become available on their next provider
login/link. No stored provider access tokens are retained for background fetching.

# Fresh browsing and deletion

Startup, overview entry, tab selection, document/thought opening, and returning
to an active main/overview screen request incremental server changes. Unrelated
local edits are merged; conflicts preserve the local draft and show a warning.
There is no continuous background polling. Offline browsing retains cached data.

Thought deletion and permanent trash deletion sync immediately. Box deletion
shows the selected boxes and a second irreversible-deletion warning. Unclassified
is a system box and cannot be deleted. Included thoughts and their unused media
are deleted, while document prose that quotes a thought remains independent.
Folder deletion removes the folder tree and moves its contents to unclassified;
no documents, thoughts, or boxes are destroyed. Folder metadata and deletion
requests do not upload unsaved document text or canvas placement.
