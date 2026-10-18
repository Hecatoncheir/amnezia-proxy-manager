"""Проверка настоящего оболочечного установщика с отдельным HOME на Linux."""
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


@unittest.skipUnless(sys.platform == "linux", "Нужна Linux-среда")
class LinuxInstallerTest(unittest.TestCase):
    def test_extract_install_and_update(self):
        with tempfile.TemporaryDirectory(prefix="amnezia-package-") as temporary:
            root = Path(temporary)
            payload = io.BytesIO()
            with tarfile.open(fileobj=payload, mode="w:gz") as archive:
                for name, data, mode in [
                    ("amnezia_proxy_manager", b"#!/bin/sh\nexit 0\n", 0o755),
                    ("data/flutter_assets/assets/branding/app_icon.png", b"icon", 0o644),
                    ("data/flutter_assets/assets/branding/app_icon_256.png", b"icon", 0o644),
                ]:
                    entry = tarfile.TarInfo(name)
                    entry.size, entry.mode = len(data), mode
                    archive.addfile(entry, io.BytesIO(data))
            installer = root / "package with spaces.run"
            installer.write_bytes(Path(__file__).with_name("linux-header.sh").read_bytes() + payload.getvalue())
            extracted = root / "extracted"
            subprocess.run(["sh", str(installer), "--extract", str(extracted)], check=True)
            self.assertTrue(os.access(extracted / "amnezia_proxy_manager", os.X_OK))
            home = root / "home"
            home.mkdir()
            environment = dict(os.environ, HOME=str(home))
            subprocess.run(["sh", str(installer)], env=environment, check=True)
            application = home / ".local/opt/amnezia-proxy-manager"
            sentinel = application / "preserve.txt"
            sentinel.write_text("preserve")
            subprocess.run(["sh", str(installer)], env=environment, check=True)
            self.assertEqual(sentinel.read_text(), "preserve")
            self.assertTrue((home / ".local/bin/amnezia-proxy-manager").is_symlink())
            desktop = home / ".local/share/applications/io.github.hecatoncheir.amnezia_proxy_manager.desktop"
            self.assertIn("Icon=", desktop.read_text())


if __name__ == "__main__":
    unittest.main()
