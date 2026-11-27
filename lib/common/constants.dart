import 'package:flutter/widgets.dart';

const String kAppName = 'Koneko';
const String kAppVersion = '0.0.10';
const kAppLocale = Locale('zh', 'CN');
const String kPackageName = 'com.anime.koneko';
const String kRepoUrl = 'https://github.com/AKLYILNEA/kk-test';
const String kPrismUiUrl = 'https://github.com/chen08209/prism_ui';
const String kKazumiUrl = 'https://github.com/Predidit/Kazumi';
const String kAnimekoUrl = 'https://github.com/open-ani/animeko';

const double kMinTextScale = 0.8;
const double kMaxTextScale = 1.4;
const double kMobileBreakpoint = 720.0;

/// Default Koneko / FlClash Soft Indigo seed.
const int kDefaultPrimaryColor = 0xFF465F96;

/// Default FlClash-style seed palette.
const List<int> kDefaultPrimaryColors = [
  0xFF465F96, // Soft Indigo (default)
  0xFF3E63DD, // Cobalt Blue
  0xFF7B5EA7, // Wisteria Purple
  0xFFD65A8A, // Sakura Rose
  0xFF2B8A6E, // Pine Jade
  0xFFD97724, // Amber Ochre
  0xFF2685A8, // Cerulean Teal
];

/// Matches emoji clusters so [PrismApp] routes them exclusively to Twemoji.
final RegExp kEmojiPattern = RegExp(
  r'(?:[\u{1F1E6}-\u{1F1FF}]{2}|'
  r'[\u{1F300}-\u{1F9FF}\u{1FA00}-\u{1FAFF}\u{2600}-\u{27BF}]'
  r'\uFE0F?[\u{1F3FB}-\u{1F3FF}]?'
  r'(?:\u200D[\u{1F300}-\u{1F9FF}\u{1FA00}-\u{1FAFF}\u{2600}-\u{27BF}]'
  r'\uFE0F?[\u{1F3FB}-\u{1F3FF}]?)*)',
  unicode: true,
);

enum LiquidGlassMode {
  none('关闭'),
  standard('标准'),
  ultra('极致');

  const LiquidGlassMode(this.label);
  final String label;
}

enum TabAnimationMode {
  slide('滑动'),
  fade('淡入');

  const TabAnimationMode(this.label);
  final String label;
}

double systemTextScaleOf(BuildContext context) {
  return MediaQuery.textScalerOf(context).scale(1.0);
}

String formatDurationShort(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final mins = (clamped ~/ 60).toString().padLeft(2, '0');
  final secs = (clamped % 60).toString().padLeft(2, '0');
  return '$mins:$secs';
}

String formatRelativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}
