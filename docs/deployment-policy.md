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
