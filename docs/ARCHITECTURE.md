# Архитектура

## Границы

Текущая реализация — UI и диагностический CLI; соединение между ними пока отсутствует. Целевая схема:

```text
Приложение пользователя → SOCKS5/HTTP loopback → upstream amnezia-proxy
                                                   ↓
                                     отдельный AmneziaWG userspace stack
                                                   ↓
                                               VPN-сервер

Flutter UI ← JSON Lines / stdio → Go supervisor → upstream subprocess
```

Upstream реализует сетевой стек; supervisor отвечает за жизненный цикл и безопасный контракт UI. Системный туннель AmneziaVPN и системные proxy settings не изменяются. Обнаружение установки AmneziaVPN — подсказка для экспорта, не разрешение на чтение хранилища.

## Компоненты

- Flutter presentation: темы, страницы, состояния. По мере реализации выделить features/profiles, features/connection, features/settings.
- Dart engine client: планируемый запуск supervisor, JSON framing, таймауты и преобразование событий; бизнес-логика не в виджетах.
- Go supervisor: планируемые IPC, machine state, безопасная передача профиля, управление дочерним процессом.
- internal/upstream: существующий адаптер строит exec.Cmd с абсолютными путями и loopback listener. Он не проверяет происхождение binary, не читает профиль и не запускает процесс.
- Хранилище: планируемые метаданные в пользовательском каталоге и секреты в системном хранилище.

Не вводить сервис с повышенными привилегиями без доказанной необходимости.

## Контракт IPC (проект, не реализован)

JSON Lines, UTF-8, protocolVersion=1; одна запись на строку, предел 64 KiB для управляющей записи. Каждая команда содержит requestId и method. Ответ содержит тот же requestId, result либо error.code; событие — event и монотонный sequence. Секреты не возвращаются в ответах и логах. Профиль передаётся по отдельному ограниченному каналу; его предел и очистка должны быть определены в M2.

Методы: capabilities, start(profileId, socksAddress, httpAddress), stop, status. Ошибки: invalid_profile, port_in_use, backend_unavailable, unsupported_version, timeout. Не передавать необработанный stderr upstream в UI.

Сейчас доступен только однократный CLI --capabilities. Он не является реализацией описанного IPC.

## Состояния

disconnected → starting → running → stopping → disconnected; ошибка из starting/running ведёт в error с закрытием ресурсов. Повторный stop идемпотентен. start во время starting/running отклоняется. События старого поколения процесса игнорируются. running означает готовые listeners; отдельно отражать проверку сети/handshake, не подменять её фактом запуска процесса.

Закрытие UI/EOF завершает supervisor и backend. На Windows планируется Job Object; на Unix — группа процессов, мягкое завершение и ограниченный timeout перед принудительным. exec.CommandContext в текущем адаптере сам по себе не решает завершение дерева.

## Профили и безопасность

Импорт — осознанное действие пользователя. Не обходить ACL, Keychain, DPAPI или закрытые форматы. Наличие файла не означает совместимость. Парсер должен ограничивать размер, проверять ключи/адреса и не исполнять wg-quick hook-команды. Нельзя логировать ключи и vpn://.

Только loopback listeners. LAN-доступ потребовал бы отдельной модели аутентификации и сейчас не поддерживается. Локальные процессы всё равно могут использовать loopback-прокси — это не граница изоляции пользователей. Не обещать системный kill switch. DNS клиента может утечь до прокси: необходимо удалённое разрешение имени и реальные проверки. При отказе VPN запрещён прямой fallback.

## ОС и поставка

| ОС | Каркас | До beta |
| --- | --- | --- |
| Windows | Flutter runner, Go CLI | Job Object, Credential Manager/DPAPI, installer и подпись |
| macOS | Flutter runner с исходными sandbox entitlements | Проверка subprocess, Keychain, network entitlements, notarization |
| Linux | GTK runner, Go CLI | Secret Service, отсутствие keyring, пакет и зависимости |

Текущие macOS entitlements оставлены штатными: сетевой backend ещё не включён. Наличие runner не доказывает работоспособность туннеля на ОС. CI собирает каждый runner нативно; архитектуры CPU и упаковка — отдельные задачи.

## Решение об интеграции

Выбран процессный адаптер, поскольку upstream — самостоятельный package main, а не стабильная библиотека. Он позволяет явно контролировать версию и отделить UI. До включения binary необходимо проверить лицензию и сборку. Возможный последующий fork с библиотечным API требует отдельного решения и тестов.
