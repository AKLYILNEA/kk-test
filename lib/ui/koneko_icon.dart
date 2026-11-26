import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Unified icon adapter for Koneko (Scheme 2):
/// wraps [LucideIcons] behind one semantic layer so UI screens stay completely
/// decoupled from any icon library and can later migrate to custom glyphs.
class KonekoIcon extends StatelessWidget {
  const KonekoIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
  });

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color ?? context.colorScheme.onSurface,
    );
  }
}

/// Curated anime/domain icon aliases backed by Lucide Icons.
abstract final class KonekoIcons {
  static const IconData play = LucideIcons.play;
  static const IconData pause = LucideIcons.pause;
  static const IconData star = LucideIcons.star;
  static const IconData heart = LucideIcons.heart;
  static const IconData sparkles = LucideIcons.sparkles;
  static const IconData flame = LucideIcons.flame;
  static const IconData tv = LucideIcons.tv;
  static const IconData layers = LucideIcons.layers;
  static const IconData server = LucideIcons.server;
  static const IconData gauge = LucideIcons.gauge;
  static const IconData cloudSync = LucideIcons.cloud;
  static const IconData history = LucideIcons.history;
  static const IconData search = LucideIcons.search;
  static const IconData sliders = LucideIcons.slidersHorizontal;
  static const IconData palette = LucideIcons.palette;
  static const IconData type = LucideIcons.type;
  static const IconData message = LucideIcons.messageSquare;
  static const IconData volume = LucideIcons.volume2;
  static const IconData sun = LucideIcons.sun;
  static const IconData maximize = LucideIcons.maximize2;
  static const IconData skipNext = LucideIcons.skipForward;
  static const IconData check = LucideIcons.check;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData merge = LucideIcons.gitMerge;
  static const IconData trash = LucideIcons.trash2;
  static const IconData plus = LucideIcons.plus;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData info = LucideIcons.info;
  static const IconData externalLink = LucideIcons.externalLink;
  static const IconData code = LucideIcons.code;
  static const IconData puzzle = LucideIcons.puzzle;
  static const IconData bookOpen = LucideIcons.bookOpen;
}
