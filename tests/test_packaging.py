from pathlib import Path
import hashlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = ROOT / 'packaging' / 'helper' / 'PKGBUILD'

def array(text, name):
    body = re.search(name + r'=\(([^)]*)\)', text).group(1)
    return re.findall(r"'([^']*)'|\"([^\"]*)\"", body)

class HelperPackage(unittest.TestCase):
    # The PKGBUILD downloads the privileged files from a pinned commit; the
    # copies in system/ must be byte-identical to what that commit serves, so
    # a change to either side without the other fails here.
    def test_pinned_checksums_match_system_files(self):
        text = PKGBUILD.read_text()
        sources = [a or b for a, b in array(text, 'source')]
        sums = [a or b for a, b in array(text, 'sha256sums')]
        self.assertEqual(len(sources), len(sums))
        checked = 0
        for source, digest in zip(sources, sums):
            if '::' not in source:
                continue
            name = source.split('::', 1)[0]
            local = ROOT / 'system' / name
            self.assertTrue(local.is_file(), name)
            self.assertEqual(hashlib.sha256(local.read_bytes()).hexdigest(), digest, name)
            checked += 1
        self.assertEqual(checked, 4)

if __name__ == '__main__':
    unittest.main()
