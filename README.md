# Amnezia Proxy Manager

Кроссплатформенный Flutter Desktop интерфейс для локального SOCKS5/HTTP-прокси через AmneziaWG. Целевые ОС: Windows, macOS и Linux; оформление Gruvbox Dark/Light.

## Текущее состояние

Начальный каркас, версия 0.1.0. Есть нативные Flutter runners трёх ОС, переключение темы с анимацией, Go CLI диагностики, проверяемый адаптер аргументов upstream и CI. Импорт, IPC, запуск/остановка туннеля и упаковка движка **ещё не реализованы**. Кнопка подключения отключена; демонстрация не имитирует VPN.

Основа будущего движка — [synacker/amnezia-proxy](https://github.com/synacker/amnezia-proxy), зафиксированная ревизия `f5a7912dba8b128ae5c1a3f68a06be7c1668b908`. Код upstream не скопирован и не включён в зависимости: до распространения необходимо проверить лицензионные условия. Подробнее: [интеграция](docs/UPSTREAM.md).

## Важные ограничения

- Go proxy создаёт отдельный userspace-туннель, а не подключается к активному туннелю AmneziaVPN.
- Поиск установленного приложения не даёт доступа к его защищённым профилям. Основной будущий сценарий — явный экспорт пользователем и импорт поддерживаемого профиля.
- Это не системный VPN и не системный kill switch. Проксируется только трафик приложений, настроенных на локальный прокси.
- Совместимость экспорта, AmneziaWG-параметров, DNS и IPv6 предстоит проверять на реальных серверах. Повторное использование одного ключа одновременно двумя клиентами может вызвать конфликт.
- Адреса по умолчанию: SOCKS5 `127.0.0.1:1080`, HTTP `127.0.0.1:8080`. Публикация в LAN не предусмотрена.

## Быстрый старт

Требуются Flutter 3.47.7 / Dart 3.13.5 и Go 1.25+ (CI использует Go 1.27.0). Для Windows нужен Visual Studio с Desktop development with C++; для macOS — Xcode; для Linux — clang, CMake, Ninja, pkg-config, GTK 3 development, libstdc++ development.

```sh
cd apps/desktop
flutter pub get
flutter analyze
flutter test
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

На Windows используйте имя `proxy-engine.exe`. Команда `--capabilities` возвращает JSON с `canStart: false`; другие команды завершаются с кодом 2. Работающий VPN для этих проверок не требуется.

## Структура

| Путь | Назначение |
| --- | --- |
| apps/desktop/lib | Интерфейс и темы |
| apps/desktop/windows, macos, linux | Нативные runners Flutter |
| apps/desktop/test | Проверка состояния и переключения темы |
| engine/cmd/proxy-engine | Диагностический Go CLI |
| engine/internal/upstream | Граница интеграции отдельно собранного backend |
| docs/ARCHITECTURE.md | Компоненты, IPC, безопасность и платформы |
| docs/UPSTREAM.md | Ревизия, стратегия интеграции и лицензирование |
| .github/workflows/ci.yml | Анализ, тесты и сборки трёх ОС |

## Разработка и готовность

[Подробный план и milestones](TODO.md) · [Архитектура](docs/ARCHITECTURE.md) · [Проверки](docs/VALIDATION.md)

Сборка Flutter на каждой ОС выполняется на её собственном runner. CI собирает каркас, но не подтверждает работу VPN и не выпускает установщики. Реальные профили, ключи и журналы с секретами не должны попадать в Git.

## Выпуски и обновление версии

[История изменений](Changelog.md) · [Подготовка и публикация выпуска](docs/RELEASING.md)

После заполнения `Unreleased` выполните `python tools/release.py prepare v0.1.1`:
команда обновит `pubspec.yaml`, увеличит номер сборки и подготовит раздел changelog.
Отправка тега `v0.1.1` запускает проверки, сборки Windows x64, macOS arm64 и Linux x64,
затем публикацию архивов и SHA-256 в [GitHub Releases](https://github.com/Hecatoncheir/amnezia-proxy-manager/releases).
Предварительные теги вида `v0.1.1-rc.1` создают prerelease. Обновление пока ручное,
через скачивание и распаковку новой версии; архивы не подписаны.

Рекомендуемое описание GitHub: «Кроссплатформенный менеджер SOCKS5/HTTP-прокси AmneziaWG на Flutter и Go». Topics: `flutter`, `golang`, `amneziawg`, `socks5`, `proxy`, `windows`, `macos`, `linux`, `gruvbox`. Сайт пока не опубликован; настройки удалённого репозитория этим коммитом не меняются.
