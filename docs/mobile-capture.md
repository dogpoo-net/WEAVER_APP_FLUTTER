# Mobile thought attachments

Android/iOS and mobile browsers show location, microphone and gallery controls
beside the quick memo title. Location uses a selected icon toggle; gallery choices
open beside the photo icon (the subsequent OS picker controls its own placement). Desktop can view the saved attachments and Geolog.
An attachment alone can save a thought. Empty text gets a local timestamp and
attachment kinds (사진, 음성, 위치); tags and links alone still cannot save.
Thoughts show small attachment indicators; details provide audio playback, photo
zoom and a recorded-location map.

- Location is opt-in for each draft. Request foreground permission only, capture
  a single high-accuracy position with a 20-second timeout, and store accuracy
  and capture time alongside coordinates. No background tracking.
- Voice recording starts only after pressing Start in the dialog. Mono 16-kHz
  signed 16-bit PCM is capped at 60 seconds by both timer and byte count, then
  wrapped in WAV. Leaving the foreground or receiving an audio interruption
  stops capture. The dialog permits replay, re-recording and cancellation, including tapping
  outside while recording. Cancelling releases the recorder; unsaved capture
  bytes never enter persistent storage. Native replay uses an owned temporary
  directory removed when its player closes.
- Up to five photos per thought. The picker requests a maximum 2048-pixel image
  and 85% quality; a returned file over 10 MiB is rejected. Gallery access only;
  no camera permission is requested.
- Attachments remain in memory until Save. Binary files are stored through Hive
  in IndexedDB on web and application documents on Android/iOS. Only IDs and
  small metadata enter the existing JSON/settings snapshot. A JSON snapshot by
  itself is therefore not a portable media backup. No upload service is used.
- Removing a draft attachment does not delete an existing thought's attachment.
  Deleting a thought deletes its binary attachments, and full reset clears them.
- Geolog uses OpenStreetMap standard tiles, visible attribution and no API key.
  It needs internet connectivity and a production-appropriate tile service if
  traffic grows. No bulk tile downloads. Co-located thoughts share a marker.
  Box and tag filters constrain the mapped thoughts. The map itself never
  requests the viewer's location.
- Mobile web microphone/geolocation require HTTPS or localhost. Denied
  permissions produce messages without discarding the memo draft.

## Real-device checks

Test Android/iOS permission grant and denial, location services disabled,
approximate coordinates, phone/audio interruption, background/foreground,
60-second auto-stop, cancellation, repeated recording, five photos and a sixth
attempt, narrow screen/keyboard, playback/photo zoom after process restart,
low-storage failure, deletion/reset and offline map errors. Native permissions
and recording require a device; CI tests do not exercise physical GPS/microphone.

## Regional map tiles and empty geolog

Geolog and location previews share `RegionalTileProvider`. Zoom levels below 7
use the global OSM raster tiles. At zoom 7+, tiles whose centers fall inside
33–38.7° N, 124.5–132° E use
`https://tiles.osm.kr/hot/{z}/{x}/{y}.png`; other tiles use the global source.
This is an approximate regional split, not a country polygon or a guarantee of
security-facility masking. At low zoom Korea is included in global tiles. There
is no global fallback for failed Korean tile requests. Verified on 2026-11-11: the provider homepage documents `/hot/`, zoom 7–20,
viewer bounds 32–44° N / 123–132.5° E, and free commercial/noncommercial use.
Seoul (z16), Jeju/Dokdo/Pyongyang (z14), and a Korean overview (z7) returned
HTTP 200, 256×256 PNGs and `Access-Control-Allow-Origin: *`. Global world (z2)
and Paris (z12) tiles passed the same checks. Seoul and Dokdo samples were
visually inspected. The viewer bounds are not a guarantee of complete coverage.
The provider describes military-feature removal and publishes non-military OSM
extracts; this does not establish removal of every security facility or legal
compliance. The app still uses its narrower South Korea selection rectangle.
Sources: https://tiles.osm.kr/ and https://tiles.osm.kr/download/.
OSM public tile usage policy still applies; this is not an offline tile cache.

An empty geolog shows a noninteractive, blurred world map centered on 20° N, 0° E
with the existing notice at the top and readable attribution at the bottom.
It does not request the user's location. Nonempty results retain interactive
markers and the recorded-location camera.
