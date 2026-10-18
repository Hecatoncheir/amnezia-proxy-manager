"""Подготовить платформенные размеры значка из общего PNG (нужен Pillow)."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = ROOT / "apps/desktop/assets/branding/app_icon.png"
    image = Image.open(source).convert("RGBA")
    image.resize((256, 256), Image.Resampling.LANCZOS).save(source.with_name("app_icon_256.png"))
    image.save(ROOT / "apps/desktop/windows/runner/resources/app_icon.ico",
               sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
    target = ROOT / "apps/desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        image.resize((size, size), Image.Resampling.LANCZOS).save(target / f"app_icon_{size}.png")


if __name__ == "__main__":
    main()
