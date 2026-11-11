# Login, guest mode and persistent device sessions

Email signup collects name, email, password and confirmation. Verification is
required before email login. The login page also provides Google, Kakao, Naver,
GitHub and GitLab. Apple is hidden. Provider buttons share width, height, spacing
and border geometry; Google web uses the official rendered button.

The API defaults to `https://api.dogpoo.net/dogpoo/weaver/api/auth/` and can be
changed using the public `WEAVER_AUTH_URL` build define. Never put provider client
secrets in Flutter defines or source. Kakao native/JavaScript identifiers are
public SDK configuration; changing a native key also requires matching Android
and iOS callback-scheme registration.

## Sessions

Web uses HttpOnly + Secure + SameSite=Strict API cookies and a tab proof held in
sessionStorage. Reload preserves login. A normally closed tab loses its proof;
a new tab cannot restore that cookie alone. Browser tab restoration/duplication
can restore/copy sessionStorage, so absolute close-event logout cannot be promised.
Closing a tab cannot reliably notify the server; explicit logout revokes it.
Production cookie login requires the configured HTTPS same-site frontend/API.

Installed apps keep only the refresh credential and pending rotation request ID
in OS secure storage. Access tokens stay in memory and expire in 30 minutes;
refresh sessions expire after 90 idle days or 365 absolute days. App exit/reboot
and 30 days of non-use retain login. A lost refresh response is retried using the
same stored request ID, so rotation does not unnecessarily break restart login.
Network errors preserve credentials; server rejection removes them. Restoring
login requires network access; local data remains available through guest mode.

Settings has device logout and confirmed all-device logout. Logout success means
server revocation succeeded; an offline failure is shown instead of pretending
that remote sessions were revoked. Local workspace content is retained.

Windows: Credential Manager-backed encrypted storage. Android: Keystore-backed
storage, excluded from backup/device transfer. iOS: device-only Keychain after
first unlock, iCloud synchronization disabled. The Windows runner is included;
use `flutter build windows --release` on Windows with the C++ build tools. Native
OS storage, signing and deep links still require testing on actual target devices.

## Social accounts

Kakao uses the official Flutter SDK on web, Android and iOS. Its temporary provider
tokens are held in memory and discarded after server validation. The SDK does not
support Windows, so its button is disabled there. Naver/GitHub/GitLab use a server
OAuth flow and the external system browser on native platforms, including Windows;
web uses a popup. The original client alone can complete the one-use flow.

Names are shown alongside email in settings. Provider subject ID determines the
account. Matching emails do not silently merge accounts: log in with the existing
method and use the appropriate account-link action in settings. Only verified
provider emails are accepted where the provider supplies verification status.
Naver requires the agreed account email and name from its authenticated user API.
GitHub/GitLab request identity scopes only, not repository access.

## Guest and legacy behavior

Guest mode survives reload and never gets a server session. Cloud controls and
workspace transfer handlers reject guests. Settings → 로그인 / 회원가입 preserves
saved local content; unsaved quick memos must be saved before switching. Successful
login does not automatically upload or replace content. Use 데이터 저장하기 with its
existing overwrite confirmation to upload manually.

The existing Google remembered-login marker and legacy email-address-only test
backup API retain their prior test behavior. They are not made authenticated server
APIs by these changes. The new session policy applies to email and the newly added
server-backed social providers. See DOGPOO_API `docs/session-policy.md` for backend
migrations, settings, limits and tests.
