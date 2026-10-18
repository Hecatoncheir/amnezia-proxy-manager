"""Локальная сборка закреплённого upstream и опись зависимостей; без публикации."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REVISION = "f5a7912dba8b128ae5c1a3f68a06be7c1668b908"
TARGETS = [("windows", "amd64"), ("linux", "amd64"), ("darwin", "arm64")]


def run(arguments, source, environment=None):
    return subprocess.check_output(arguments, cwd=source, env=environment,
                                   text=True, encoding="utf-8", stderr=subprocess.STDOUT,
                                   timeout=300)


def objects(source):
    decoder = json.JSONDecoder()
    while source.strip():
        value, end = decoder.raw_decode(source.lstrip())
        yield value
        source = source.lstrip()[end:]


def module_licenses(module, source):
    directory = Path(module.get("Dir", source))
    result = []
    for path in sorted(directory.iterdir()):
        if path.is_file() and path.name.upper().startswith(("LICENSE", "COPYING", "NOTICE")):
            data = path.read_bytes()
            result.append({"file": path.name, "sha256": hashlib.sha256(data).hexdigest(),
                           "firstLines": data.decode("utf-8", errors="replace").splitlines()[:6]})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "work/upstream-amnezia-proxy")
    parser.add_argument("--output", type=Path, default=ROOT / "build/backend")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if run(["git", "rev-parse", "HEAD"], source).strip() != REVISION:
        raise ValueError("Ревизия upstream не совпадает")
    if run(["git", "status", "--porcelain"], source).strip():
        raise ValueError("Исходники upstream изменены")
    output.mkdir(parents=True, exist_ok=True)
    host = (run(["go", "env", "GOHOSTOS"], source).strip(),
            run(["go", "env", "GOHOSTARCH"], source).strip())
    report = {"repository": "synacker/amnezia-proxy", "revision": REVISION,
              "goVersion": run(["go", "version"], source).strip(),
              "distributionApproved": False, "builds": [], "modules": {}}
    report["tests"] = run(["go", "test", "-count=1", "./..."], source).strip()
    report["vet"] = run(["go", "vet", "./..."], source).strip() or "ok"
    for system, architecture in TARGETS:
        environment = dict(os.environ, GOOS=system, GOARCH=architecture, CGO_ENABLED="0")
        name = f"awg-proxy-{system}-{architecture}" + (".exe" if system == "windows" else "")
        target = output / name
        run(["go", "build", "-trimpath", "-o", str(target), "."], source, environment)
        native = (system, architecture) == host
        if native:
            help_text = run([str(target), "-h"], source)
            if not all(flag in help_text for flag in ["-config", "-socks-listen", "-http-listen", "-dial-timeout"]):
                raise ValueError("CLI upstream не соответствует контракту")
        data = target.read_bytes()
        report["builds"].append({"file": name, "os": system, "arch": architecture,
                                 "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                                 "validation": "native CLI/test" if native else "cross-compile only"})
        packages = objects(run(["go", "list", "-deps", "-json", "."], source, environment))
        for package in packages:
            module = package.get("Module")
            if module is None or module["Path"] in report["modules"]:
                continue
            report["modules"][module["Path"]] = {
                "version": module.get("Version", REVISION), "sum": module.get("Sum"),
                "licenseFiles": module_licenses(module, source),
            }
        print(f"Собран {name}", flush=True)
    (output / "audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Отчёт: {output / 'audit.json'}")


if __name__ == "__main__":
    main()
