# Windows Google / Kakao login

Windows opens the system browser, then polls the existing proof-bound OAuth flow to establish a native server session. Profile linking uses the same flow. Android and web retain their SDK paths. No desktop client secret is bundled in the app.

Register these exact redirect URLs:
- Existing Google WEB OAuth client: `https://api.dogpoo.net/dogpoo/weaver/api/auth/google/callback`
- Kakao REST API redirect URI: `https://api.dogpoo.net/dogpoo/weaver/api/auth/kakao/callback`

Server `/home/ocaptain/api/api.env`:
- `WEAVER_GOOGLE_CLIENT_SECRET`: secret belonging to the existing WEB client ID.
- `KAKAO_REST_API_KEY`: Kakao REST API key, not native or JavaScript key.
- `KAKAO_CLIENT_SECRET`: enabled REST API client secret.

Restart the API service after configuring the environment. Pull main and rebuild Windows; adding redirect URLs alone cannot enable this feature in an old executable. Distribute the entire Release directory, including data/flutter_assets and DLLs.

Closing an external browser cannot be detected reliably; cancel from Weaver or wait for the existing OAuth timeout. Provider tokens are exchanged and validated on the server. The app receives only its own session. Native credentials use the existing secure session store.

Validation: Windows routing unit test, OAuth cancellation regressions, Google login regressions, static analysis, backend tests. Actual Windows binary and provider interactive login require a Windows device and completed console configuration.
