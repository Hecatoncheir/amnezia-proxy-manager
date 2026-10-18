# Проверка upstream — 18 октября 2026

Выбран [bropines/awg-wireproxy](https://github.com/bropines/awg-wireproxy),
[v2.1.0](https://github.com/bropines/awg-wireproxy/releases/tag/v2.1.0),
ревизия `02588433b6328171b594d76f3f16bd3404258a83`.
Ранее исследовавшийся synacker/amnezia-proxy заменён; его отсутствие лицензии
больше не блокирует выбранный движок. Результаты прежнего исследования сохранены в Git.

## Лицензия

В проверенной ревизии есть [ISC LICENSE](https://github.com/bropines/awg-wireproxy/blob/v2.1.0/LICENSE):
разрешены использование, изменение и распространение с сохранением copyright и
текста лицензии. Неизменённая копия: `backend/AWG-WIREPROXY-LICENSE.txt`.
В установках движка LICENSE сохраняется рядом с бинарником. Архивы скачиваются
напрямую из релизов автора, собственные сборки не публикуются.

Опись модулей в `backend/build-audit.json`: ISC у проекта, MIT у amneziawg-go/v3,
argparse, heredoc, go-socks5, landlock и Go-обёртки wintun; Apache-2.0 у gvisor,
btree и go-ini; BSD у Go x/* и protect. У libcap/psx двойная лицензия
BSD-3-Clause OR GPL-2.0-only (модуль входит в Linux-зависимости).
Это инвентаризация корневых лицензий модулей, не окончательный файловый аудит.
NOTICE/SBOM и условия зависимостей требуют завершения перед нашей перепубликацией.

## Сборка и пакеты

Исходники без изменений: игнорируемый `work/upstream-awg-wireproxy`.
Go 1.27.1 выбран автоматически по go.mod; локальные сборки CGO=0:
Windows amd64, Linux amd64 и Darwin arm64. На Windows проверен локальный CLI;
две другие сборки — только кросс-компиляция. Отчёт `backend/build-audit.json`.

Отдельно скачаны настоящие релизные архивы трёх платформ. SHA-256 сверены с GitHub
API и `checksums.txt`; вычислены отдельные хеши бинарников, проверены содержимое
и архитектуры. Эти релизные хеши закреплены в приложении; локальные сборки
имеют другие хеши и не подменяют опубликованные пакеты. Снимок: `backend/release-audit.json`.

## Исполненные проверки

- Windows release: `--help`, `--version` = 2.1.0, Go build info с точной ревизией,
  `vcs.modified=false` и windows/amd64.
- `--configtest`: корректный синтетический профиль принимается, неверный ключ
  отклоняется; путь содержит кириллицу и пробелы.
- Реальный Windows subprocess: SOCKS5 negotiation, TCP listener HTTP, остановка
  и освобождение обоих портов. Endpoint — loopback без сервера: внешний VPN этим не проверяется.
- Upstream `go test -count=1 -v .`: успешны локальные туннели WireGuard, AWG 1 и
  AWG 3, SOCKS5-запрос через туннель, тесты конфигурации и HTTP.
- `go vet ./...`: успешно. Полный `go test ./...` не зелёный: в пакете `admin`
  `TestConfigMaskedAndSaved` ожидает Unix-права, Windows сообщает `-rw-rw-rw-`.
  Веб-панель в нашем адаптере не включается. Это зафиксированное ограничение,
  а не исправленный тест upstream.
- Загрузчик UI испытан с настоящими GitHub API/ZIP, затем без сети.

Заявленные upstream параметры AWG 1/1.5/2/3.x изучены; локальные tunnel-тесты
не подтверждают все версии и экспорты AmneziaVPN. Не проверены внешний endpoint,
DNS/IPv6, UDP ASSOCIATE, реальные профили и запуск на macOS/Linux.

## Воспроизведение

```powershell
git clone --depth 1 --branch v2.1.0 https://github.com/bropines/awg-wireproxy.git work/upstream-awg-wireproxy
python tools/audit_backend.py
gh release download v2.1.0 --repo bropines/awg-wireproxy --pattern '*windows_amd64.zip' --dir build/awg-wireproxy-v2.1.0
# Извлечь wireproxy.exe из скачанного архива в тот же каталог.
python tools/check_awg_backend.py build/awg-wireproxy-v2.1.0/wireproxy.exe --output build/awg-wireproxy-v2.1.0/smoke.json
```

Веб-панель может включаться через `WIREPROXY_ADMIN`; адаптер удаляет все
`WIREPROXY_*` из окружения. В M2 разрешать только необходимые поля AWG-профиля:
маршрутные whitelist-правила upstream могут использовать прямой доступ и не
должны попадать в сгенерированный конфиг. Health без CheckAlive не доказывает VPN.
