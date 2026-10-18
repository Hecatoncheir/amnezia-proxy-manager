# Иконка приложения

Общий исходник: `apps/desktop/assets/branding/app_icon.png`, PNG с прозрачными
углами. Знак — оливковый щит с кремовой линией между двумя узлами на тёмной
плитке Gruvbox. Он обозначает защищённое прокси-соединение, без текста и букв.

Иконка создана встроенным инструментом `imagegen`. Исходный запрос:

```text
Create a final production desktop application icon for Amnezia Proxy Manager.
Square 1024x1024 canvas with real transparent outer corners. One centered
rounded-square dark charcoal tile (#282828), occupying 88% of the canvas,
softly rounded corners and a very subtle warm edge. Inside it, one bold
beautifully balanced olive-lime (#b8bb26) geometric shield outline. Inside
the shield, a single simple warm cream (#ebdbb2) connection path with two
round terminal nodes, suggesting a protected proxy relay: one node upper
left, one node lower right, joined by a thick clean angular S-like route.
Strong negative space, flat crisp vector-like shapes with only a tiny
restrained material depth on the tile. Gruvbox desktop aesthetic, confident
understated technical tool, legible at 16 and 32 pixels, precise symmetry
of outer shield, no letters, no text, no arrows outside the shield, no lock,
no gradients, no glow, no watermark. Deliver only the single app icon,
not a sheet, mockup, or presentation.
```

`python tools/prepare_icons.py` подготавливает размеры для Windows ICO,
macOS AppIcon и PNG 256 px для меню Linux. Требуется Python с Pillow.
Дизайн при этом не меняется: выполняется только преобразование размеров и форматов.

Использование:

- Шапка интерфейса Flutter.
- Ресурс Windows EXE: заголовок окна, панель задач, ярлыки, значок файла.
- Windows Setup и значок удаления приложения.
- macOS AppIcon: Finder, Dock, содержимое DMG; тот же значок для тома DMG.
- Linux: значок GTK-окна, запись `.desktop` и каталог значков hicolor.
- README проекта.

Функциональные значки подключения, настроек и направления трафика сохраняют
своё назначение. На странице репозитория GitHub отдельный аватар не поддерживается;
README показывает общий значок без изменения аватара владельца.
