"""Подготовка и проверка версии, извлечение описания выпуска."""
import argparse
from datetime import date
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
TAG = re.compile(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(rc|beta|alpha)\.(0|[1-9]\d*))?")


def version(tag):
    if not TAG.fullmatch(tag):
        raise ValueError("Нужен тег vX.Y.Z или vX.Y.Z-rc.N (также beta/alpha)")
    return tag[1:]


def notes(source, tag):
    version(tag)
    sections = list(re.finditer(r"^## (\S+).*$", source, re.MULTILINE))
    found = []
    for index, section in enumerate(sections):
        if section[1] == tag:
            end = sections[index + 1].start() if index + 1 < len(sections) else len(source)
            found.append(source[section.end():end].strip())
    if len(found) != 1 or not found[0]:
        raise ValueError("Нужен ровно один непустой раздел changelog для " + tag)
    return found[0] + "\n"


def pubspec_version(source):
    match = re.search(r"^version: (\S+)$", source, re.MULTILINE)
    if match is None:
        raise ValueError("Не найдена версия pubspec.yaml")
    return match


def prepare(source, changelog, tag):
    target = version(tag)
    current = pubspec_version(source)
    old_version, separator, build = current[1].partition("+")
    if old_version == target:
        raise ValueError("Эта версия уже указана в pubspec.yaml")
    marker = "## Unreleased"
    if changelog.count(marker) != 1:
        raise ValueError("Нужен один раздел Unreleased")
    if re.search(r"^## " + re.escape(tag) + r"(?:\s|$)", changelog, re.MULTILINE):
        raise ValueError("Версия уже есть в changelog")
    number = int(build) + 1 if separator else 1
    updated = source[:current.start()] + f"version: {target}+{number}" + source[current.end():]
    heading = f"## Unreleased\n\n## {tag} — {date.today().isoformat()}"
    history = changelog.replace(marker, heading, 1)
    notes(history, tag)
    return updated, history


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "check", "notes"])
    parser.add_argument("tag")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    spec = ROOT / "apps/desktop/pubspec.yaml"
    history = ROOT / "Changelog.md"
    source = spec.read_text(encoding="utf-8")
    changelog = history.read_text(encoding="utf-8")
    expected = version(args.tag)
    if args.command == "prepare":
        source, changelog = prepare(source, changelog, args.tag)
        spec.write_text(source, encoding="utf-8")
        history.write_text(changelog, encoding="utf-8")
    if pubspec_version(source)[1].partition("+")[0] != expected:
        raise ValueError("Версия тега не совпадает с pubspec.yaml")
    body = notes(changelog, args.tag)
    if args.output:
        args.output.write_text(body, encoding="utf-8")
    elif args.command == "notes":
        print(body, end="")


if __name__ == "__main__":
    main()
