from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'setup.sh'

class FirstRun(unittest.TestCase):
    def run_helper(self, *args):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            state = base / 'state'
            state.mkdir()
            helper = base / 'helper'
            code = SOURCE.read_text().split("<<'HELPER'\n", 1)[1].split('\nHELPER\n', 1)[0]
            # Redirect every hardware/state path; no real hardware writes.
            code = code.replace('/var/lib/omarchy-predatorsense-ph31552', str(state)).replace('/sys/', str(base / 'sys') + '/')
            helper.write_text(code)
            helper.chmod(0o755)
            result = subprocess.run([str(helper), *args], capture_output=True, text=True)
            return result, {p.name: p.read_text().strip() for p in state.iterdir()}

    def test_first_profile_without_keyboard_link(self):
        result, state = self.run_helper('profile', 'balanced', '7aa2f7')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state.get('profile'), 'balanced')

    def test_keyboard_link_without_saved_profile(self):
        result, state = self.run_helper('kb-link', 'profile', '7aa2f7')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state.get('kblink'), 'profile')

    def test_no_saved_profile_is_noop(self):
        result, state = self.run_helper('apply-saved')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state, {})

    def test_invalid_profile_is_rejected(self):
        result, state = self.run_helper('profile', 'invalid')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(state, {})

if __name__ == '__main__':
    unittest.main()
