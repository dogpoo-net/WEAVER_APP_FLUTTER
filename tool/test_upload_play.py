import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from upload_play import upload


def response(data=None, status=200):
    r = Mock(ok=status < 400, status_code=status, content=b'json')
    r.json.return_value = data or {}
    return r


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bundle = Path(self.tmp.name) / 'app.aab'
        self.bundle.write_bytes(b'test')
        self.session = Mock()
        self.session.post.side_effect = [response({'id': 'edit1'}), response({'versionCode': 2}), response(), response()]
        self.old = {'status': 'completed', 'versionCodes': ['1']}
        self.session.get.side_effect = [response({'releases': [self.old]}), response({'bundles': [{'versionCode': 1}]})]
        self.session.put.return_value = response()
        self.session.delete.return_value = response()

    def test_commit_keeps_existing_release_and_only_adds_internal_draft(self):
        upload(self.session, 'net.dogpoo.weaver', self.bundle, True)
        args, kwargs = self.session.put.call_args
        self.assertTrue(args[0].endswith('/tracks/internal'))
        self.assertEqual(kwargs['json']['releases'], [self.old, {'name': 'WEAVER 2', 'versionCodes': ['2'], 'status': 'draft'}])
        self.assertTrue(self.session.post.call_args.args[0].endswith(':commit'))
        self.session.delete.assert_not_called()

    def test_default_validates_then_discards_without_commit(self):
        upload(self.session, 'net.dogpoo.weaver', self.bundle)
        self.assertEqual(self.session.post.call_count, 3)
        self.assertTrue(self.session.post.call_args.args[0].endswith(':validate'))
        self.session.delete.assert_called_once()

    def test_existing_draft_never_overwritten(self):
        self.session.get.side_effect = [response({'releases': [{'status': 'draft'}]})]
        with self.assertRaisesRegex(RuntimeError, 'draft already exists'):
            upload(self.session, 'net.dogpoo.weaver', self.bundle, True)
        self.session.put.assert_not_called()
        self.assertEqual(self.session.post.call_count, 1)
        self.session.delete.assert_called_once()

    def test_failed_validation_does_not_commit(self):
        self.session.post.side_effect = [response({'id': 'edit1'}), response({'versionCode': 2}), response(status=403)]
        with self.assertRaisesRegex(RuntimeError, 'HTTP 403'):
            upload(self.session, 'net.dogpoo.weaver', self.bundle, True)
        self.assertEqual(self.session.post.call_count, 3)
        self.session.delete.assert_called_once()


if __name__ == '__main__':
    unittest.main()
