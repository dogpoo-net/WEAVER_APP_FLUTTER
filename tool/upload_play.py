#!/usr/bin/env python3
"""Upload a signed AAB to an internal-testing draft; validate-only by default."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.parse import quote

API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'
UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications'


def checked(response):
    if not response.ok:
        # Do not print request headers, credentials, or raw server bodies.
        raise RuntimeError('Play API HTTP %s. Check API enablement, app permissions, '
                           'first manual upload, signing certificate and versionCode.' % response.status_code)
    return response.json() if response.content else {}


def upload(session, package, bundle, commit=False):
    app = API + '/' + quote(package, safe='')
    edit = checked(session.post(app + '/edits', json={}, timeout=60))['id']
    base = app + '/edits/' + edit
    committed = False
    try:
        track = checked(session.get(base + '/tracks/internal', timeout=60))
        releases = track.get('releases', [])
        if any(item.get('status') == 'draft' for item in releases):
            raise RuntimeError('An internal-test draft already exists. Resolve it in Play Console first; it was not overwritten.')
        existing = checked(session.get(base + '/bundles', timeout=60)).get('bundles', [])
        with bundle.open('rb') as data:
            result = checked(session.post(
                UPLOAD + '/' + quote(package, safe='') + '/edits/' + edit + '/bundles',
                params={'uploadType': 'media'}, data=data,
                headers={'Content-Type': 'application/octet-stream'}, timeout=(60, 1200)))
        version = str(result['versionCode'])
        if any(str(item['versionCode']) == version for item in existing):
            raise RuntimeError('versionCode already exists. Rebuild with a higher --build-number.')
        # Preserve previously published releases. Never promote to production.
        releases = releases + [{'name': 'WEAVER ' + version, 'versionCodes': [version], 'status': 'draft'}]
        checked(session.put(base + '/tracks/internal', json={'track': 'internal', 'releases': releases}, timeout=60))
        checked(session.post(base + ':validate', timeout=60))
        if commit:
            checked(session.post(base + ':commit', timeout=60))
            committed = True
            print('Committed internal-testing DRAFT, versionCode=' + version)
        else:
            print('Validated internal-testing draft, versionCode=' + version + '; edit will be discarded.')
        return version
    finally:
        if not committed:
            response = session.delete(base, timeout=60)
            if not response.ok and response.status_code != 404:
                print('Warning: edit cleanup failed; check Play Console before retrying.', file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--aab', required=True, type=Path)
    parser.add_argument('--credentials', type=Path, default=os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'))
    parser.add_argument('--package', default='net.dogpoo.weaver')
    parser.add_argument('--commit', action='store_true', help='Save internal-testing draft (does not release to testers).')
    args = parser.parse_args()
    if not args.aab.is_file() or args.aab.suffix != '.aab':
        parser.error('--aab must be an existing signed .aab file')
    if not args.credentials or not args.credentials.is_file():
        parser.error('Provide --credentials or GOOGLE_APPLICATION_CREDENTIALS pointing to the service-account JSON')
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession
    credentials = service_account.Credentials.from_service_account_file(
        str(args.credentials), scopes=['https://www.googleapis.com/auth/androidpublisher'])
    with args.aab.open('rb') as data:
        digest = hashlib.sha256()
        for block in iter(lambda: data.read(1024 * 1024), b''):
            digest.update(block)
    print('AAB SHA256=' + digest.hexdigest())
    with AuthorizedSession(credentials) as session:
        upload(session, args.package, args.aab, args.commit)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        if isinstance(error, RuntimeError):
            print(str(error), file=sys.stderr)
        else:
            print('Upload failed (%s). Check credentials/network; secrets have not been logged.' % type(error).__name__, file=sys.stderr)
        sys.exit(1)
