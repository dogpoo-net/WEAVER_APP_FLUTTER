# Cloudflare Pages

Create a **Pages** project connected to `dogpoo-net/WEAVER_APP_FLUTTER`:

- Production branch: `main`
- Framework preset: None
- Root directory: repository root (leave blank)
- Build command: `bash scripts/build-cloudflare.sh`
- Build output directory: `build/web`

The build script installs the pinned Flutter 3.47.9 SDK, verifies its Git revision,
resolves the existing lockfile and builds for `/`. Flutter need not be preinstalled.
GitHub and Flutter's artifact/package download endpoints must be accessible.
The SDK is installed outside the checkout; an existing matching SDK can be selected
with `WEAVER_FLUTTER_ROOT`. Do not set that override in Cloudflare to a local Codex path.

Optionally set the public OAuth application identifier `GOOGLE_WEB_CLIENT_ID` in
Cloudflare's build variables. Without it the app uses its repository default.
Register the Pages/custom-domain origin with the OAuth application separately.
Never put client secrets in Flutter build variables; web assets are public.

Pages Git integration handles production and preview deployments. Do not enter
`wrangler deploy` or `wrangler versions upload` for this Pages project.
The API Worker will be a separate project when backend code is implemented.

GitHub Pages deployment is manual (`workflow_dispatch`) and does not run on push.
