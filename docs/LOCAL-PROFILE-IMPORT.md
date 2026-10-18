# Чтение профиля установленной AmneziaVPN

Менеджер читает только выбранную сохранённую клиентскую конфигурацию под текущей учётной записью. Он не изменяет настройки AmneziaVPN, не вызывает API подписки и не создаёт новый слот Premium. Профиль проходит собственный нормализатор, проверку движком и сохраняется в хранилище менеджера.

| ОС | Источник | Ограничения |
| --- | --- | --- |
| Windows | QSettings в HKCU, ключ/IV в Credential Manager | Реальная AmneziaVPN 5.0.3.0 проверена |
| Linux | `$XDG_CONFIG_HOME/AmneziaVPN.ORG/AmneziaVPN.conf` либо `~/.config/AmneziaVPN.ORG/AmneziaVPN.conf` | Поддерживается стандартный незашифрованный Qt INI; изолированные Snap/Flatpak и старые зашифрованные варианты требуют экспорта |
| macOS | CFPreferences `org.amneziavpn.AmneziaVPN`, Generic Password в Keychain | Нужна нативная CGO-сборка; доступ к ключам разрешает macOS, отказ не обходится |

## Форматы и границы

Читаются `Servers/serversList` и `Servers/defaultServerId`. Из массива выбирается только сервер с соответствующим `storageServerId` и его `defaultContainer`. Для Xray берётся `last_config`, для AWG — клиентские данные выбранного контейнера. В результат не входят `auth_data`, ключ API подписки и другие серверы.

В Qt INI декодируются оболочка `@ByteArray(...)`, кавычки и escape-последовательности Qt. На macOS Qt использует точки в ключах CFPreferences: `Servers.serversList` и `Servers.defaultServerId`. Зашифрованные значения имеют префикс `EncData`; общий декодер проверяет AES-256-CBC, PKCS#7 и формат QVariant QByteArray. Ключ и IV читаются только в память и очищаются после использования.

Размер файла Linux и буфера настроек macOS ограничен 2 МиБ, число серверов — 100, Xray `last_config` — 64 КиБ. Конфигурация не передаётся в аргументах процесса. stdout вспомогательного процесса содержит только выбранный профиль и обрабатывается менеджером; диагностический вывод не показывается как содержимое конфигурации.

Для macOS используется `SecItemCopyMatching`: сервис `AmneziaVPN-Keychain`, учётные записи `settingsKeyTag` и `settingsIvTag`. Разрешение App Sandbox на чтение preferences ограничено одним доменом AmneziaVPN; сама песочница остаётся включена. Никакие записи Keychain не создаются и не изменяются этим импортом.

## Источники формата

- [SecureQSettings AmneziaVPN](https://github.com/amnezia-vpn/amnezia-client/blob/ddde43635e957ebf042d92787489da72d3394019/client/secureQSettings.cpp): формат шифрования и отключённое шифрование Linux в проверенной ревизии.
- [QtKeychain Apple backend](https://github.com/frankosterfeld/qtkeychain/blob/7460df6a978669290de5b56c2d98b199b61c3f88/qtkeychain/keychain_apple.mm): имена атрибутов service/account.
- [Qt 6.10 QSettings macOS](https://github.com/qt/qtbase/blob/v6.10.0/src/corelib/io/qsettings_mac.cpp): домен preferences и замена разделителя ключей.
- [Apple: Shared Preference Domain Temporary Exceptions](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html): ограниченный доступ только для чтения.

## Что проверено

Проверены синтетические настройки Qt INI, escape-последовательности, AES/QVariant, выбор нужного сервера, отсутствие данных подписки в результате и отклонение повреждённых записей. Для Linux есть тест чтения файла из временного `XDG_CONFIG_HOME` с проверкой неизменности оригинала. На Windows повторно прочитан настоящий выбранный VLESS после переноса общего декодера; ключи и профиль не сохранялись в журналы или тестовые файлы.

Настоящая установленная AmneziaVPN на macOS/Linux, системный диалог Keychain и ограничения нестандартных пакетов здесь не проверены. Автоматический импорт на этих ОС считается реализацией стандартного формата, а не подтверждённой совместимостью со всеми установками. При несовместимости остаётся ручной импорт файла или ссылки.
