# Amnezia Proxy Manager

<img src="apps/desktop/assets/branding/app_icon.png" width="96" alt="Amnezia Proxy Manager">

Кроссплатформенный Flutter Desktop интерфейс для локального SOCKS5/HTTP-прокси через AmneziaWG или VLESS. Целевые ОС: Windows, macOS и Linux; оформление Gruvbox Dark/Light.

## Текущее состояние

Версия приложения — 0.1.3; реализованы отдельная загрузка движка, импорт AmneziaVPN/AmneziaWG, системное хранение ключей и проверка конфигурации. Есть Flutter runners трёх ОС, темы, установщики, обновление приложения и CI. Подключение AmneziaWG/VLESS управляется круглой кнопкой через Go supervisor. На Windows проверены запуск/остановка и HTTPS через Xray; полный нативный прогон других ОС ещё предстоит.

Сетевой движок — [bropines/awg-wireproxy](https://github.com/bropines/awg-wireproxy), проверенный выпуск **v2.1.0**, ревизия `02588433b6328171b594d76f3f16bd3404258a83`, лицензия ISC. Он загружается отдельно напрямую из GitHub Releases автора. Приложение при запуске предлагает последнюю проверенную совместимую версию, проверяет архив и бинарник по SHA-256, архитектуру и CLI, хранит runtime вне установки. Загрузка и повторный запуск без сети проверены на Windows. Импорт профилей и проверка конфигурации реализованы в M2; подключение из UI и управление процессом реализованы в M3. Подробнее: [аудит M1](docs/UPSTREAM.md) · [схема загрузки движка](docs/ENGINE-RUNTIME.md).

Для VLESS добавлен отдельный [XTLS/Xray-core](https://github.com/XTLS/Xray-core) **v26.7.28**, MPL-2.0. Этот выпуск помечен upstream как prerelease: разрешён только конкретный проверенный тег и закреплённые SHA-256, произвольные предварительные версии не устанавливаются. AWG и Xray имеют отдельные каталоги и проверки. [Интеграция VLESS](docs/XRAY.md).

## Важные ограничения

- Go proxy создаёт отдельный userspace-туннель, а не подключается к активному туннелю AmneziaVPN.
- На Windows доступен явный импорт выбранного сохранённого профиля установленной AmneziaVPN под текущей учётной записью. Подписка не копируется, новая конфигурация Premium не создаётся. На других ОС используется экспорт. [Форматы и хранение ключей](docs/PROFILES.md).
- Это не системный VPN и не системный kill switch. Проксируется только трафик приложений, настроенных на локальный прокси.
- Совместимость экспорта, AmneziaWG-параметров, DNS и IPv6 предстоит проверять на реальных серверах. Повторное использование одного ключа одновременно двумя клиентами может вызвать конфликт.
- Адреса по умолчанию: SOCKS5 `127.0.0.1:1080`, HTTP `127.0.0.1:8080`. Публикация в LAN не предусмотрена.

## Быстрый старт

Требуются Flutter 3.47.7 / Dart 3.13.5 и Go 1.25+ (CI использует Go 1.27.0). Для Windows нужен Visual Studio с Desktop development with C++; для macOS — Xcode; для Linux — clang, CMake, Ninja, pkg-config, GTK 3 development, libstdc++ development, libsecret-1-dev; для хранения ключей требуется работающий Secret Service (например GNOME Keyring/KWallet). На Windows плагину хранилища также нужны C++ ATL libraries.

```sh
cd apps/desktop
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
cd ../..
python tools/build_supervisor.py
cd apps/desktop
flutter run -d windows
# На соответствующей ОС: flutter run -d macos / flutter run -d linux
```

```sh
cd engine
go test ./...
go vet ./...
go run ./cmd/proxy-engine --capabilities
go build -o ../build/proxy-engine ./cmd/proxy-engine
```

На Windows используйте имя `proxy-engine.exe`. Команда `--capabilities` возвращает JSON с `canStart: true` и `canValidateConfig: true`; поддерживаются `--inspect-backend` и `--validate-config`. Работающий VPN для этих проверок не требуется.

## Структура

| Путь | Назначение |
| --- | --- |
| apps/desktop/lib | Интерфейс и темы |
| apps/desktop/windows, macos, linux | Нативные runners Flutter |
| apps/desktop/test | Проверка состояния и переключения темы |
| engine/cmd/proxy-engine | Диагностика и безопасная проверка профиля |
| apps/desktop/lib/features/profiles | Импорт, метаданные, системное хранилище и проверка конфигурации |
| engine/internal/upstream | Граница интеграции отдельно собранного backend |
| docs/ARCHITECTURE.md | Компоненты, IPC, безопасность и платформы |
| docs/UPSTREAM.md | Ревизия, стратегия интеграции и лицензирование |
| .github/workflows/ci.yml | Анализ, тесты и сборки трёх ОС |

## Разработка и готовность

Начальный размер окна — 540×540. Размер, положение и развёрнутое состояние
сохраняются между запусками; при отключении монитора окно возвращается в доступную
рабочую область. [Исходник иконки и платформенные размеры](docs/BRANDING.md).

Экран следует концепту Gruvbox: карточки подключения, профиля и скорости, моноширинная типографика и настройки темы. Состояние оформления хранится в одном `SettingsCubit` из `flutter_bloc`; виджеты используют `BlocBuilder`. Тема пока хранится только на время сеанса. Отдельные Bloc/Cubit для ещё не реализованных функций не создаются. Скорость пока отображается как «Нет данных». Круглая кнопка запускает/останавливает выбранный профиль, профили и движки доступны в меню. В настройках есть отдельные переключатели автозапуска и автоподключения (изначально выключены). [Управление сессией](docs/SESSION.md).

[Подробный план и milestones](TODO.md) · [Архитектура](docs/ARCHITECTURE.md) · [Проверки](docs/VALIDATION.md)

Сборка Flutter на каждой ОС выполняется на её собственном runner. CI собирает каркас, но не подтверждает работу VPN. Установщики создаются workflow выпуска по тегу. Реальные профили, ключи и журналы с секретами не должны попадать в Git.

## Выпуски и обновление версии

[История изменений](Changelog.md) · [Подготовка и публикация выпуска](docs/RELEASING.md)

После заполнения `Unreleased` выполните `python tools/release.py prepare v0.1.4`:
команда обновит `pubspec.yaml`, увеличит номер сборки и подготовит раздел changelog.
Отправка тега `v0.1.4` запускает проверки, сборки Windows x64, macOS arm64 и Linux x64,
затем публикацию переносимых архивов, установщиков и SHA-256 в [GitHub Releases](https://github.com/Hecatoncheir/amnezia-proxy-manager/releases).
Предварительные теги вида `v0.1.4-rc.1` создают prerelease. В настройках доступны проверка версии, описание изменений и загрузка с проверкой SHA-256.
Установленная Windows-копия обновляется через Setup с перезапуском; macOS и Linux
показывают пакет и инструкции. Установщики пока не имеют доверенной подписи издателя.

Рекомендуемое описание GitHub: «Кроссплатформенный менеджер SOCKS5/HTTP-прокси AmneziaWG на Flutter и Go». Topics: `flutter`, `golang`, `amneziawg`, `socks5`, `proxy`, `windows`, `macos`, `linux`, `gruvbox`. Сайт пока не опубликован; настройки удалённого репозитория этим коммитом не меняются.
