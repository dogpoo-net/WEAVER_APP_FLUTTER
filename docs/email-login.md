# Email login

The login screen provides Sign in and Sign up (email, password, password
confirmation). Signup sends a verification link; the account cannot log in until
verification succeeds. Users can request a replacement link from the email form.
Opening the link displays a confirmation button; it does not consume the link
automatically. Existing Google login remains available.

The default endpoint is `https://api.dogpoo.net/dogpoo/weaver/api/auth/`.
`--dart-define=WEAVER_AUTH_URL=https://.../` overrides this public API URL.
No provider secret or SMTP credential belongs in Flutter build configuration.
Deploy the matching DOGPOO_API implementation and migration before this client.

Email sessions are memory-only, expire after 12 hours, and are revoked on logout.
Reloading the page requires a new login. They never use the Google test-login
preference marker. Local workspace data remains device-specific; account isolation
and authenticated cloud backup are separate tasks. The legacy backup API is still
a test implementation and is not secured by adding email login.

Apple/Kakao/Naver buttons are visibly unavailable pending provider registration,
keys and callback configuration. See DOGPOO_API `docs/social-login-setup.md` for
required settings. Existing accounts are not silently linked by matching emails.
