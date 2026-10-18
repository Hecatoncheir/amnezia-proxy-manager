# Интеграция upstream — M1, 18 октября 2026 года

Источник: [synacker/amnezia-proxy](https://github.com/synacker/amnezia-proxy).
Проверенная ревизия: `f5a7912dba8b128ae5c1a3f68a06be7c1668b908` — текущий main
на момент проверки. Исходники клонированы в игнорируемый `work/upstream-amnezia-proxy`,
не изменялись и не включены в исходники нашего приложения.

## Лицензия и возможность поставки

GitHub API возвращает `license: null`. В дереве проверенной ревизии нет файлов
LICENSE/COPYING/NOTICE; в README не найдено явного разрешения на распространение.
Поэтому правовое основание нашей публикации backend **не подтверждено**.
Локальные сборки для исследования остаются в игнорируемом `build/backend/`;
не создавались fork, issue, PR или релиз с чужими бинарниками.

Это согласуется с [пояснением GitHub о репозиториях без лицензии](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
Проверка не заменяет разрешения автора. Собственная лицензия проекта также ещё
не выбрана владельцем.

Опись реально используемых Go-модулей по трём сборкам:

| Модуль | Версия | Файл лицензии уровня модуля |
| --- | --- | --- |
| amnezia-proxy | указанная ревизия | Отсутствует |
| github.com/amnezia-vpn/amneziawg-go/v3 | v3.1.20260828 | MIT |
| golang.zx2c4.com/wintun | v0.0.0-20230126152724-0fa3db229ce2 | MIT (Go-обёртка) |
| github.com/google/btree | v1.1.3 | Apache-2.0 |
| gvisor.dev/gvisor | v0.0.0-20231202080848-1f7806d17489 | Apache-2.0 |
| golang.org/x/crypto | v0.42.0 | BSD-3-Clause |
| golang.org/x/net | v0.44.0 | BSD-3-Clause |
| golang.org/x/sys | v0.36.0 | BSD-3-Clause |
| golang.org/x/time | v0.9.0 | BSD-3-Clause |

Тексты и SHA-256 файлов LICENSE просмотрены локально; версии/Go sums/хеши лицензий
записаны в [описи сборки](backend/build-audit.json). Это начальная опись модулей,
**не окончательный NOTICE или SBOM**: отдельные файлы и компоненты могут иметь
дополнительные условия. Отдельный драйвер Wintun DLL не скачивался и не поставлялся.
Лицензии зависимостей не лицензируют автоматически код самого amnezia-proxy.

## Сборка и фактические проверки

Go 1.27.0, `CGO_ENABLED=0`, `go build -trimpath`; версия в upstream go.mod — 1.25.0.
Воспроизведение из корня проекта:

```powershell
git clone https://github.com/synacker/amnezia-proxy.git work/upstream-amnezia-proxy
git -C work/upstream-amnezia-proxy checkout f5a7912dba8b128ae5c1a3f68a06be7c1668b908
python tools/audit_backend.py
```

Скрипт отклоняет другую ревизию или изменённое дерево. Создаются:

- `build/backend/awg-proxy-windows-amd64.exe` — Windows PE x64.
- `build/backend/awg-proxy-linux-amd64` — ELF x64, только кросс-компиляция.
- `build/backend/awg-proxy-darwin-arm64` — Mach-O arm64, только кросс-компиляция.
- `build/backend/audit.json` — контрольные суммы и модульная опись.

На Windows прошли `go test -count=1 ./...`, `go vet ./...`, `-h` и проверка
`go version -m`: правильная ревизия, `vcs.modified=false`, GOOS/GOARCH, CGO=0.
Наш `upstream.VerifyBinary` проверен на настоящем собранном бинарнике:

```powershell
$env:BACKEND_TEST_BINARY = (Resolve-Path build/backend/awg-proxy-windows-amd64.exe).Path
cd engine
go test ./...
```

Upstream-тесты HTTP и CONNECT используют локальный сервер и прямой тестовый dial,
а не действующий AmneziaWG-сервер. Они подтверждают обработчики прокси, но не VPN,
DNS, IPv6, SOCKS5 через реальный туннель или отсутствие утечек.

## Совместимость и обнаруженные ограничения

CLI подтверждён: `-config`, `-socks-listen`, `-http-listen`, `-dial-timeout`,
`-verbose`. Нет `--version`, `--capabilities`, JSON IPC или передачи конфигурации
через stdin. Исходный CLI требует путь к файлу; секреты нельзя помещать в аргументы.
Для версии используются манифест релиза и встроенные Go build info.

По исходникам поддерживаются wg-quick INI и `vpn://` (qCompress/zlib/JSON с AWG).
Это пока не подтверждение совместимости с реальным экспортом пользователя.
`vpn.go` читает файл и распакованный JSON без явного общего ограничения размера:
до запуска backend нужен ограниченный разбор в M2. `PostUp`/`PostDown` не выполняются
как команды, но неизвестные поля INI не отклоняются; UI должен иметь свой allowlist.
Сообщение о listener печатается до фактического bind — лог не является признаком
готовности. Прямой stderr может содержать приватный путь/значение ошибки и не должен
показываться в UI без очистки. На Windows пока не подтверждены управляемая остановка
SIGTERM и завершение дерева; для этого нужен supervisor/Job Object в M3.

В upstream на момент проверки нет тегов и GitHub Releases, только Linux-артефакт
workflow автора. CI-артефакт не используется как замена стабильному выпуску.
Приложение подготавливает отдельную загрузку по [контракту runtime](ENGINE-RUNTIME.md),
но до согласованной публикации оно корректно сообщает об отсутствии совместимого
движка. Включение backend в наш установщик не требуется.

## Что осталось для выхода из M1

1. Явная лицензия/разрешение автора и согласованные релизы с бинарниками/манифестом.
2. Нативный запуск macOS/Linux, sandbox и подписи; окончательная опись лицензий.
3. Настоящий тестовый сервер/отдельный профиль для SOCKS5, HTTP, DNS, IPv4/IPv6,
   неверного ключа, недоступного endpoint и поведения без прямого fallback.
4. После этого M2–M3: безопасный импорт, хранение ключей и жизненный цикл туннеля.
