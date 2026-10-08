import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from tools.server.seed_population_credentials import seed


class PopulationPreparationTests(unittest.TestCase):
    def test_new_fixtures_preserve_original_credentials_and_resume_privately(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); database = root / 'auth.sqlite'; output = root / 'fixtures.json'
            with sqlite3.connect(database) as db:
                db.executescript('''
                    CREATE TABLE credentials(account TEXT PRIMARY KEY,salt BLOB,password_hash BLOB,created_at INTEGER,legacy_disabled INTEGER);
                    CREATE TABLE sessions(token_hash TEXT PRIMARY KEY,account TEXT,expires_at INTEGER);
                    INSERT INTO credentials VALUES('original',X'0102',X'0304',100,1);
                    INSERT INTO sessions VALUES('existing','original',123);
                ''')
            # Exercise transaction/ownership boundaries without spending32 KDFs;
            # production imports the same scrypt primitive used by real login.
            with patch('tools.server.seed_population_credentials.derive', side_effect=lambda password, salt: hashlib.sha256(password + salt).digest()):
                result = seed(database, output, 'loadtest_test')
                self.assertEqual(result['new_auth_accounts'], 32)
                self.assertEqual(result['original_auth_accounts_preserved'], 1)
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                self.assertEqual(seed(database, output, 'loadtest_test')['reused_auth_accounts'], 32)
                with sqlite3.connect(database) as db:
                    self.assertEqual(db.execute("SELECT * FROM credentials WHERE account='original'").fetchone(), ('original', b'\x01\x02', b'\x03\x04', 100, 1))
                    self.assertEqual(db.execute("SELECT * FROM sessions WHERE account='original'").fetchall(), [('existing', 'original', 123)])
                    self.assertEqual(db.execute('SELECT count(*) FROM credentials').fetchone()[0], 33)
                value = json.loads(output.read_text());value['players'][0]['password'] = 'unrelated-secret-value'
                output.write_text(json.dumps(value))
                with self.assertRaises(ValueError):seed(database, output, 'loadtest_test')
                with sqlite3.connect(database) as db:
                    self.assertEqual(db.execute('SELECT count(*) FROM credentials').fetchone()[0], 33)


if __name__ == '__main__':
    unittest.main()
