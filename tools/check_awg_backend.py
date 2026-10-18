"""Проверка опубликованного Windows-бинарника без настоящего VPN-профиля."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    binary = args.binary.resolve()
    socks, http = port(), port()
    while socks == http:
        http = port()
    # Публичные тестовые ключи upstream, endpoint loopback без VPN-сервера.
    config = f"""[Interface]
Address = 10.200.200.2/32
PrivateKey = uCTIK+56CPyCvwJxmU5dBfuyJvPuSXAq1FzHdnIxe1Q=
DNS = 10.200.200.1
[Peer]
PublicKey = QP+A67Z2UBrMgvNIdHv8gPel5URWNLS4B3ZQ2hQIZlg=
Endpoint = 127.0.0.1:9
AllowedIPs = 0.0.0.0/0, ::/0
[Socks5]
BindAddress = 127.0.0.1:{socks}
[http]
BindAddress = 127.0.0.1:{http}
"""
    environment = {k: v for k, v in os.environ.items()
                   if not k.upper().startswith("WIREPROXY_")}
    report = {"realVpn": False, "configtest": False, "invalidConfigRejected": False,
              "socksHandshake": False, "httpListener": False, "stopped": False}
    with tempfile.TemporaryDirectory(prefix="awg проверка ") as temporary:
        profile = Path(temporary) / "тестовый профиль.conf"
        profile.write_text(config, encoding="utf-8")
        result = subprocess.run([str(binary), "--config", str(profile), "--configtest"],
                                env=environment, capture_output=True, timeout=10)
        assert result.returncode == 0, "Корректная конфигурация отклонена"
        report["configtest"] = True
        profile.write_text(config.replace("uCTIK+56CPyCvwJxmU5dBfuyJvPuSXAq1FzHdnIxe1Q=", "invalid"), encoding="utf-8")
        result = subprocess.run([str(binary), "--config", str(profile), "--configtest"],
                                env=environment, capture_output=True, timeout=10)
        assert result.returncode != 0, "Ошибочная конфигурация принята"
        report["invalidConfigRejected"] = True
        profile.write_text(config, encoding="utf-8")
        process = subprocess.Popen([str(binary), "--config", str(profile), "--silent"],
                                   env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 10
            while True:
                try:
                    connection = socket.create_connection(("127.0.0.1", socks), timeout=1)
                    break
                except OSError:
                    assert process.poll() is None and time.monotonic() < deadline, "SOCKS5 не запущен"
                    time.sleep(0.05)
            with connection:
                connection.sendall(b"\x05\x01\x00")
                assert connection.recv(2) == b"\x05\x00", "Неверный SOCKS5 handshake"
                report["socksHandshake"] = True
            with socket.create_connection(("127.0.0.1", http), timeout=2):
                report["httpListener"] = True
        finally:
            process.terminate()
            process.wait(timeout=10)
        for number in [socks, http]:
            with socket.socket() as connection:
                assert connection.connect_ex(("127.0.0.1", number)) != 0, "Порт остался занят"
        report["stopped"] = True
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
