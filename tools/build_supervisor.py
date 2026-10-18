"""Собрать компонент проверки рядом с исполняемым файлом Flutter для разработки."""
import argparse
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    args = parser.parse_args()
    mode = args.configuration
    system = platform.system()
    if system == "Windows":
        directory = ROOT / f"apps/desktop/build/windows/x64/runner/{mode.title()}"
        name = "proxy-engine.exe"
    elif system == "Darwin":
        directory = ROOT / f"apps/desktop/build/macos/Build/Products/{mode.title()}/amnezia_proxy_manager.app/Contents/MacOS"
        name = "proxy-engine"
    else:
        directory = ROOT / f"apps/desktop/build/linux/x64/{mode}/bundle"
        name = "proxy-engine"
    directory.mkdir(parents=True, exist_ok=True)
    subprocess.run(["go", "build", "-trimpath", "-o", str(directory / name), "./cmd/proxy-engine"],
                   cwd=ROOT / "engine", check=True)
    print(directory / name)


if __name__ == "__main__":
    main()
