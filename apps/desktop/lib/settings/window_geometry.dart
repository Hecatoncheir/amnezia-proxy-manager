import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

const defaultWindowSize = Size(540, 840);
const minimumWindowSize = Size(380, 560);

class WindowGeometry {
  const WindowGeometry(this.bounds, {this.maximized = false});
  final Rect bounds;
  final bool maximized;

  static WindowGeometry? decode(String? source) {
    if (source == null) return null;
    try {
      final values = jsonDecode(source) as Map<String, dynamic>;
      final numbers = [
        'x',
        'y',
        'width',
        'height',
      ].map((key) => (values[key] as num).toDouble()).toList();
      if (numbers.any((value) => !value.isFinite)) return null;
      if (numbers[2] <= 0 || numbers[3] <= 0) return null;
      return WindowGeometry(
        Rect.fromLTWH(numbers[0], numbers[1], numbers[2], numbers[3]),
        maximized: values['maximized'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
    'maximized': maximized,
  });
}

Rect fitWindowToDisplays(Rect? saved, List<Rect> workAreas) {
  final areas = workAreas.where((area) => !area.isEmpty).toList();
  if (areas.isEmpty) {
    return saved ?? const Offset(40, 40) & defaultWindowSize;
  }
  var area = areas.first;
  if (saved != null) {
    var largest = 0.0;
    for (final candidate in areas) {
      final overlap = candidate.intersect(saved);
      final size = overlap.isEmpty ? 0.0 : overlap.width * overlap.height;
      if (size > largest) {
        largest = size;
        area = candidate;
      }
    }
  }
  final size = saved?.size ?? defaultWindowSize;
  final width = size.width.clamp(
    math.min(minimumWindowSize.width, area.width),
    area.width,
  );
  final height = size.height.clamp(
    math.min(minimumWindowSize.height, area.height),
    area.height,
  );
  final origin =
      saved?.topLeft ??
      Offset(
        area.left + (area.width - width) / 2,
        area.top + (area.height - height) / 2,
      );
  return Rect.fromLTWH(
    origin.dx.clamp(area.left, area.right - width),
    origin.dy.clamp(area.top, area.bottom - height),
    width.toDouble(),
    height.toDouble(),
  );
}
