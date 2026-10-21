import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum BrandGlyph {
  power,
  settings,
  profile,
  engine,
  diagnostics,
  update,
  upload,
  download,
  link,
  unlock,
  back,
  next,
  delete,
  file,
  importProfile,
  check,
  route,
  tunnel,
  protection,
  disconnected,
}

/// Округлые SVG-знаки варианта 03; цвет и размер наследуются от кнопки.
class BrandIcon extends StatelessWidget {
  const BrandIcon(this.glyph, {super.key, this.size, this.color});
  final BrandGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final tint = _foreground(theme, Theme.of(context).colorScheme.onSurface);
    final dimension = size ?? theme.size ?? 24;
    return SvgPicture.asset(
      'assets/icons/${glyph.name}.svg',
      width: dimension,
      height: dimension,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }

  Color _foreground(IconThemeData theme, Color fallback) {
    final foreground = color ?? theme.color ?? fallback;
    return foreground.withValues(alpha: foreground.a * (theme.opacity ?? 1));
  }
}
