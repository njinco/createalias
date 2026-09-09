"""Run with python3 -m unittest discover -s tests."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'crealias.sh'


class PersistenceTests(unittest.TestCase):
    def run_manager(self, home, answers):
        env = dict(os.environ, HOME=str(home), USER='termux_test_user', SUDO_USER='')
        result = subprocess.run(
            ['bash', '--noprofile', '--norc', '-c',
             'source "$1"; alias persist_test', 'bash', str(SCRIPT)],
            input=answers, text=True, capture_output=True, env=env, timeout=5)
        return result, env

    def test_permanent_targets_and_fresh_shell(self):
        for target in ('1', '2', '3', ''):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as tmp:
                home = Path(tmp)
                reload_answers = 'n\nn\n' if target == '3' else 'n\n'
                result, env = self.run_manager(
                    home, '1\npersist_test\nprintf "it\'s saved"\ny\n'
                    + target + '\n' + reload_answers + '4\n')
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = ['.bashrc'] if target in ('1', '') else ['.bash_aliases']
                if target == '3':
                    expected = ['.bashrc', '.bash_aliases']
                for filename in expected:
                    self.assertIn('alias persist_test=', (home / filename).read_text())
                fresh = subprocess.run(
                    ['bash', '--noprofile', '-ic', 'alias persist_test'],
                    text=True, capture_output=True, env=env, timeout=5)
                self.assertEqual(fresh.returncode, 0, fresh.stderr)
                self.assertIn('saved', fresh.stdout)

    def test_temporary_alias_does_not_write_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            result, _ = self.run_manager(home, '1\npersist_test\necho temporary\nn\n4\n')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(home.iterdir()), [])

    def test_failed_save_does_not_activate_alias(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / '.bashrc').mkdir()
            result, _ = self.run_manager(home, '1\npersist_test\necho failed\ny\n1\n4\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Could not save alias', result.stdout)
            self.assertNotIn('Alias active', result.stdout)

    def test_invalid_input_does_not_contaminate_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            result, _ = self.run_manager(
                home, '1\nbad name\npersist_test\n\necho saved\ny\ninvalid\n1\nn\n4\n')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("alias persist_test='echo saved'", (home / '.bashrc').read_text())


if __name__ == '__main__':
    unittest.main()
