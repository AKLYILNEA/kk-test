import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/common/ui_localizations.dart';
import 'package:koneko/features/shell/home_shell.dart';
import 'package:koneko/ui/miuix/miuix_bg_effect.dart';
import 'package:koneko_core/koneko_core.dart';
import 'package:prism_ui/prism_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Generous memory cache prevents cover eviction & reloads while scrolling.
  PaintingBinding.instance.imageCache
    ..maximumSize = 500
    ..maximumSizeBytes = 256 << 20;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await FontManager.init();
  unawaited(MiuixBgEffectController.warmUp());
  final core = await KonekoCore.open();
  runApp(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(core.catalog),
        ruleRepositoryProvider.overrideWithValue(core.rules),
        trackingStoreProvider.overrideWithValue(core.tracking),
        secretsProvider.overrideWithValue(core.settings),
        trackingSyncProvider.overrideWithValue(core.sync),
        playbackSourcesProvider.overrideWithValue(core.sources),
        offlineLibraryProvider.overrideWithValue(core.offline),
        danmakuProvider.overrideWithValue(core.danmaku),
        checkForUpdateProvider.overrideWithValue(findKonekoUpdate),
        playbackFactoryProvider.overrideWithValue(() {
          NativePlayback.initialize();
          return NativePlayback();
        }),
        videoViewportProvider.overrideWithValue(NativePlayback.viewport),
        danmakuViewportProvider.overrideWithValue(
          (items, status) => NativeDanmaku(items: items, status: status),
        ),
      ],
      child: const KonekoApp(),
    ),
  );
}

class KonekoApp extends ConsumerWidget {
  const KonekoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeSettingsProvider);
    ref.watch(loadHomeCatalogProvider);
    ref.watch(loadTrackedSubjectsProvider);

    return ValueListenableBuilder<String?>(
      valueListenable: FontManager.fontFamilyNotifier,
      builder: (context, customFontFamily, _) {
        final lightTheme = buildKonekoTheme(
          settings: settings,
          brightness: Brightness.light,
          customFontFamily: customFontFamily,
        );
        final darkTheme = buildKonekoTheme(
          settings: settings,
          brightness: Brightness.dark,
          customFontFamily: customFontFamily,
        );
        final liquidGlass = switch (settings.liquidGlass) {
          LiquidGlassMode.none => null,
          LiquidGlassMode.standard => LiquidGlassQuality.standard,
          LiquidGlassMode.ultra => LiquidGlassQuality.ultra,
        };

        return PrismApp(
          debugShowCheckedModeBanner: false,
          title: kAppName,
          themeMode: settings.themeMode,
          theme: lightTheme,
          darkTheme: darkTheme,
          textScale: settings.customTextScaleEnabled
              ? settings.textScale
              : null,
          minTextScale: kMinTextScale,
          maxTextScale: kMaxTextScale,
          liquidGlass: liquidGlass,
          emojiFont: (family: 'Twemoji', pattern: kEmojiPattern),
          localizationsDelegates: const [
            KonekoUiLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [kAppLocale, Locale('en', 'US')],
          locale: kAppLocale,
          builder: (context, child) {
            final size = MediaQuery.sizeOf(context);
            return ViewScope(
              size: size,
              isMobile: size.width < kMobileBreakpoint,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}
