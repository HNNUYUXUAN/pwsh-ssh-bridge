import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile
from build import ROOT, build, inventory, validate
from install import install


class BuildTests(unittest.TestCase):
    def test_reproducible_archives_and_complete_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            one, two = build(base / 'one'), build(base / 'two')
            self.assertEqual(one, two)
            for name, expected in one['archives'].items():
                self.assertEqual((base / 'one' / name).read_bytes(), (base / 'two' / name).read_bytes())
                self.assertEqual(hashlib.sha256((base / 'one' / name).read_bytes()).hexdigest(), expected)
                with zipfile.ZipFile(base / 'one' / name) as archive:
                    entries = archive.namelist()
                    self.assertTrue(all(item.startswith('pwsh-ssh-bridge/') for item in entries))
                    self.assertFalse(any('/.git/' in item or '/dist/' in item or '/__pycache__/' in item for item in entries))
                    if '-workspace.' in name:
                        self.assertIn('pwsh-ssh-bridge/dev/build.py', entries)
                        self.assertIn('pwsh-ssh-bridge/tests/Test-Live.ps1', entries)
                    else:
                        self.assertFalse(any('/dev/' in item or '/tests/' in item for item in entries))

    def test_workspace_can_rebuild_after_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            initial = build(base / 'dist')
            source = next((base / 'dist').glob('*-workspace.zip'))
            with zipfile.ZipFile(source) as archive:
                archive.extractall(base / 'extracted')
            rebuilt = build(base / 'rebuilt', base / 'extracted' / 'pwsh-ssh-bridge')
            self.assertEqual(initial, rebuilt)

    def test_install_exact_runtime_and_preserve_existing(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'skills' / 'pwsh-ssh-bridge'
            self.assertEqual(install(target), len(inventory()))
            self.assertEqual(inventory(target), inventory())
            skill = target / 'SKILL.md'
            skill.write_text('local edits', encoding='utf-8')
            with self.assertRaises(FileExistsError):
                install(target)
            self.assertEqual(skill.read_text(), 'local edits')

    def test_broken_link_rejected(self):
        files = inventory()
        files['README.md'] += b'\n[missing](absent.md)\n'
        with self.assertRaises(ValueError):
            validate(files)


if __name__ == '__main__':
    unittest.main()
