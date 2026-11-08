# Mobile thought attachments

Android/iOS and mobile browsers show location, microphone and gallery controls
beside the quick memo title. Desktop can view the saved attachments and Geolog.
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
  stops capture. The dialog permits replay, re-recording and cancellation.
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
