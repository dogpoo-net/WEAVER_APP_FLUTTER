# Android release and Play Console

Server build environment: `/home/ocaptain/build/android`.
`build.sh both` builds ARM64 APK and multi-ABI AAB with the configured upload key.
Source snapshots must be refreshed separately; this command does not pull Git.

## Signing

Keep `key.properties` and `DogPoo.jks` in the build environment root, outside Git,
owned by ocaptain with mode 600. The launcher mounts these read-only under
`/signing` in its temporary build namespace. It supplies
`WEAVER_ANDROID_KEY_PROPERTIES` and `WEAVER_ANDROID_KEYSTORE` to Gradle.
Local development can instead use ignored `android/key.properties`; a relative
`storeFile` is resolved relative to that properties file. Required keys:
`storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Java properties escaping
rules apply to passwords and Windows paths. Release builds fail without signing
configuration; debug builds continue using their normal debug key.

The key must match the app's registered upload certificate. The JKS is not a
Play API credential. Back it up independently and never commit passwords or keys.

## Play API setup (once)

1. Create the app in Play Console. For a new app, perform its first AAB upload
   manually and complete applicable app/account declarations.
2. Enable Google Play Android Developer API in a Google Cloud project.
3. Create a service account and invite its email in Play Console Users and
   permissions. Grant access to this app and the permissions needed to view app
   information and release to testing tracks. Production release permission is
   unnecessary for this tool.
4. Save the service-account JSON outside the repository with mode 600.
5. Install `tool/play-requirements.txt` in a Python 3.10+ virtual environment.

```bash
python3 -m venv /path/to/play-venv
/path/to/play-venv/bin/pip install -r tool/play-requirements.txt
/path/to/play-venv/bin/python tool/upload_play.py \
  --credentials /secure/path/play-service-account.json \
  --aab /path/to/weaver-release.aab
# After validation, save the internal-testing draft:
/path/to/play-venv/bin/python tool/upload_play.py \
  --credentials /secure/path/play-service-account.json \
  --aab /path/to/weaver-release.aab --commit
```

Default mode uploads into a temporary edit, validates, and discards it.
`--commit` saves an **internal-testing draft**, not a production release or a
rollout to testers. Existing published releases are retained. An existing draft
causes an error rather than being overwritten. Finish rollout in Play Console.
Every subsequent uploaded build requires a fresh, increasing versionCode;
use Flutter `--build-number N` or increment the `+N` in `pubspec.yaml` before
building. Do not blindly retry a commit timeout: inspect Play Console first,
because the commit might already have succeeded.
