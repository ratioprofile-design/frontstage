#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('backup', Path(__file__).with_name('server-backup.py'))
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class BackupTests(unittest.TestCase):
    def test_round_trip_preserves_projects_but_invalidates_restored_sessions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, copy, restored = [root / name for name in ('source', 'copy', 'restored')]
            state = {'version': 1, 'accounts': {'owner': {'username': 'owner', 'passwordHash': 'fixture'}},
                     'sessions': {'revoked-token-hash': {'username': 'owner'}}, 'projects': {'fixture': {'revision': 7}}}
            source.write_text(json.dumps(state))
            backup.transfer(source, copy)
            self.assertEqual(source.read_bytes(), copy.read_bytes())
            self.assertEqual(stat.S_IMODE(copy.stat().st_mode), 0o600)
            with self.assertRaises(FileExistsError):
                backup.transfer(source, copy)
            backup.transfer(copy, restored, restore=True)
            expected = dict(state, sessions={})
            self.assertEqual(json.loads(restored.read_bytes()), expected)
            self.assertEqual(json.loads(copy.read_bytes()), state)

    def test_invalid_source_does_not_create_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            source, destination = Path(directory) / 'source', Path(directory) / 'destination'
            source.write_text('{"version":2}')
            with self.assertRaises(ValueError):
                backup.transfer(source, destination)
            self.assertFalse(destination.exists())


if __name__ == '__main__':
    unittest.main()
