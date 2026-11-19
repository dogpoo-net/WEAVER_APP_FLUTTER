# Deployment policy

Updated at the user's request on 2026-11-17 (Asia/Seoul).

- Default: build the web app and deploy to DOGPOO nginx at `/home/ocaptain/www/weaver`.
- Reload nginx after deployment using systemctl.
- Do not perform HTTP response probes after deployment (user preference).
- Android APK/AAB and other native app builds require an explicit user request.
- Play Console uploads/releases require an explicit user request; do not automatically run them after frontend changes.
- GitHub Pages deployment requires an explicit user request.
- Push changes directly to `main`; preserve unrelated local changes.

The Android build started for the startup fix was cancelled at the user's request.
The startup fix was deployed to the web; it has not been delivered as an app update.

The web build versions Dart JS, CanvasKit, and the asset bundle separately by content under
`/_immutable/`. Include `deploy/nginx/weaver-cache.conf` in the Weaver nginx
server block when deploying this change. The root and SPA fallback should serve
`/index.html` through the exact index location so the browser revalidates it.
Publish the new immutable files before replacing the bootstrap and index.
Keep previous immutable files available for tabs still running an older build.
Do not overwrite an existing content-addressed file during deployment. Copying
identical bytes again changes the file timestamp and nginx's validation headers.
The immutable location also enables gzip for the generated scripts, WASM and fonts.
The startup font preload and Flutter's asset loader point at the same versioned
asset directory. Asset changes can give that whole directory a new URL.
Merge these directives into an existing immutable location if it is already configured.
