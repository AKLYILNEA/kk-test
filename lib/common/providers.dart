import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:koneko_mock/koneko_mock.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Theme & Appearance State (1:1 FlClash ThemeProps + pure black + liquid glass)
// ---------------------------------------------------------------------------

@immutable
class ThemeSettings {
  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.pureBlack = false,
    this.primaryColor = kDefaultPrimaryColor,
    this.primaryColors = kDefaultPrimaryColors,
    this.colorStyle = ColorStyle.soft,
    this.floatingNavigationBar = true,
    this.tabAnimation = TabAnimationMode.slide,
    this.liquidGlass = LiquidGlassMode.standard,
    this.customTextScaleEnabled = false,
    this.textScale = 1.0,
    this.sidebarExpanded = true,
  });

  final ThemeMode themeMode;
  final bool pureBlack;
  /// Null means follow system accent (fallback to Soft Indigo).
  final int? primaryColor;
  final List<int> primaryColors;
  final ColorStyle colorStyle;
  final bool floatingNavigationBar;
  final TabAnimationMode tabAnimation;
  final LiquidGlassMode liquidGlass;
  final bool customTextScaleEnabled;
  final double textScale;
  final bool sidebarExpanded;

  static const _sentinel = Object();

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    bool? pureBlack,
    Object? primaryColor = _sentinel,
    List<int>? primaryColors,
    ColorStyle? colorStyle,
    bool? floatingNavigationBar,
    TabAnimationMode? tabAnimation,
    LiquidGlassMode? liquidGlass,
    bool? customTextScaleEnabled,
    double? textScale,
    bool? sidebarExpanded,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      pureBlack: pureBlack ?? this.pureBlack,
      primaryColor: identical(primaryColor, _sentinel)
          ? this.primaryColor
          : primaryColor as int?,
      primaryColors: primaryColors ?? this.primaryColors,
      colorStyle: colorStyle ?? this.colorStyle,
      floatingNavigationBar:
          floatingNavigationBar ?? this.floatingNavigationBar,
      tabAnimation: tabAnimation ?? this.tabAnimation,
      liquidGlass: liquidGlass ?? this.liquidGlass,
      customTextScaleEnabled:
          customTextScaleEnabled ?? this.customTextScaleEnabled,
      textScale: textScale ?? this.textScale,
      sidebarExpanded: sidebarExpanded ?? this.sidebarExpanded,
    );
  }

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'pureBlack': pureBlack,
    'primaryColor': primaryColor,
    'primaryColors': primaryColors,
    'colorStyle': colorStyle.name,
    'floatingNavigationBar': floatingNavigationBar,
    'tabAnimation': tabAnimation.name,
    'liquidGlass': liquidGlass.name,
    'customTextScaleEnabled': customTextScaleEnabled,
    'textScale': textScale,
    'sidebarExpanded': sidebarExpanded,
  };

  static ThemeSettings fromJson(Map<String, dynamic> map) {
    ThemeMode parseMode(Object? v) => ThemeMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => ThemeMode.system,
    );
    ColorStyle parseStyle(Object? v) => ColorStyle.values.firstWhere(
      (e) => e.name == v,
      orElse: () => ColorStyle.soft,
    );
    TabAnimationMode parseAnim(Object? v) => TabAnimationMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => TabAnimationMode.slide,
    );
    LiquidGlassMode parseGlass(Object? v) => LiquidGlassMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => LiquidGlassMode.standard,
    );
    final colorsRaw = map['primaryColors'];
    final colors = colorsRaw is List
        ? colorsRaw.whereType<int>().toList()
        : kDefaultPrimaryColors;
    return ThemeSettings(
      themeMode: parseMode(map['themeMode']),
      pureBlack: map['pureBlack'] == true,
      primaryColor: map.containsKey('primaryColor')
          ? map['primaryColor'] as int?
          : kDefaultPrimaryColor,
      primaryColors: colors.isEmpty ? kDefaultPrimaryColors : colors,
      colorStyle: parseStyle(map['colorStyle']),
      floatingNavigationBar: map['floatingNavigationBar'] != false,
      tabAnimation: parseAnim(map['tabAnimation']),
      liquidGlass: parseGlass(map['liquidGlass']),
      customTextScaleEnabled: map['customTextScaleEnabled'] == true,
      textScale: (map['textScale'] is num)
          ? (map['textScale'] as num).toDouble().clamp(kMinTextScale, kMaxTextScale)
          : 1.0,
      sidebarExpanded: map['sidebarExpanded'] != false,
    );
  }
}

class ThemeSettingsNotifier extends Notifier<ThemeSettings> {
  static const _prefKey = 'koneko_theme_settings_v1';

  @override
  ThemeSettings build() {
    unawaited(_load());
    return const ThemeSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      final map = json.decode(raw);
      if (map is Map<String, dynamic>) {
        state = ThemeSettings.fromJson(map);
      }
    } catch (_) {}
  }

  void update(ThemeSettings Function(ThemeSettings current) updater) {
    state = updater(state);
    unawaited(_save(state));
  }

  Future<void> _save(ThemeSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, json.encode(settings.toJson()));
    } catch (_) {}
  }
}

final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
      ThemeSettingsNotifier.new,
    );

/// Generates a [ColorScheme] using prism_ui's HCT seeded scheme, matching FlClash.
ColorScheme buildKonekoColorScheme({
  required Brightness brightness,
  required int? primaryColor,
  required ColorStyle colorStyle,
  required bool pureBlack,
  Color? overrideColor,
}) {
  final seed = overrideColor ??
      Color(primaryColor ?? kDefaultPrimaryColor);
  final scheme = seededColorScheme(
    seedColor: seed,
    brightness: brightness,
    style: colorStyle,
  );
  return scheme.toPureBlack(pureBlack);
}

ThemeData buildKonekoTheme({
  required ThemeSettings settings,
  required Brightness brightness,
  required String? customFontFamily,
}) {
  final scheme = buildKonekoColorScheme(
    brightness: brightness,
    primaryColor: settings.primaryColor,
    colorStyle: settings.colorStyle,
    pureBlack: settings.pureBlack,
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: customFontFamily,
    fontFamilyFallback: const ['Twemoji'],
  );
}

// ---------------------------------------------------------------------------
// Domain Repositories & State (Strict koneko_contract -> koneko_mock boundary)
// ---------------------------------------------------------------------------

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (_) => MockCatalogRepository(),
);

final ruleRepositoryProvider = Provider<RuleRepository>(
  (_) => MockRuleRepository(),
);

class LibraryNotifier extends Notifier<List<CollectionEntry>> {
  @override
  List<CollectionEntry> build() => MockSeedData.initialCollections();

  CollectionEntry? entryFor(int subjectId) {
    for (final entry in state) {
      if (entry.subjectId == subjectId) return entry;
    }
    return null;
  }

  void setStatus(int subjectId, CollectionStatus status) {
    final now = DateTime.now();
    final exists = state.any((e) => e.subjectId == subjectId);
    if (exists) {
      state = [
        for (final e in state)
          if (e.subjectId == subjectId)
            e.copyWith(status: status, updatedAt: now)
          else
            e,
      ];
    } else {
      state = [
        CollectionEntry(
          subjectId: subjectId,
          status: status,
          watchedEpisodes: 0,
          updatedAt: now,
        ),
        ...state,
      ];
    }
  }

  void markEpisodeWatched(int subjectId, int episodeNumber, int totalEpisodes) {
    final now = DateTime.now();
    final existing = entryFor(subjectId);
    final nextWatched = existing == null
        ? episodeNumber
        : (episodeNumber > existing.watchedEpisodes
              ? episodeNumber
              : existing.watchedEpisodes);
    final nextStatus =
        (totalEpisodes > 0 && nextWatched >= totalEpisodes)
            ? CollectionStatus.watched
            : CollectionStatus.watching;
    if (existing == null) {
      state = [
        CollectionEntry(
          subjectId: subjectId,
          status: nextStatus,
          watchedEpisodes: nextWatched,
          updatedAt: now,
        ),
        ...state,
      ];
    } else {
      state = [
        for (final e in state)
          if (e.subjectId == subjectId)
            e.copyWith(
              status: nextStatus,
              watchedEpisodes: nextWatched,
              updatedAt: now,
            )
          else
            e,
      ];
    }
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, List<CollectionEntry>>(
      LibraryNotifier.new,
    );

class HistoryNotifier extends Notifier<List<MergedHistoryEntry>> {
  @override
  List<MergedHistoryEntry> build() => MockSeedData.initialMergedHistory();

  MergedHistoryEntry? entryFor(int subjectId) {
    for (final entry in state) {
      if (entry.subjectId == subjectId) return entry;
    }
    return null;
  }

  /// Records progress under [ruleId]/[ruleName] and merges it into the single
  /// per-anime [MergedHistoryEntry] keyed by [subjectId] (Animeko behavior).
  void recordProgress({
    required int subjectId,
    required int episodeNumber,
    required int positionSeconds,
    required int durationSeconds,
    required String ruleId,
    required String ruleName,
  }) {
    final now = DateTime.now();
    final newSourceRec = SourceProgressRecord(
      ruleId: ruleId,
      ruleName: ruleName,
      episodeNumber: episodeNumber,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      watchedAt: now,
    );

    final existing = entryFor(subjectId);
    final mergedSources = <SourceProgressRecord>[
      newSourceRec,
      if (existing != null)
        ...existing.sourceRecords.where((r) => r.ruleId != ruleId),
    ];

    final updated = MergedHistoryEntry(
      subjectId: subjectId,
      lastEpisode: episodeNumber,
      lastPositionSeconds: positionSeconds,
      lastDurationSeconds: durationSeconds,
      lastRuleId: ruleId,
      lastRuleName: ruleName,
      updatedAt: now,
      sourceRecords: mergedSources,
    );

    state = [
      updated,
      for (final item in state)
        if (item.subjectId != subjectId) item,
    ];
  }

  /// Simulates importing a Kazumi WebDAV multi-source backup and auto-merging
  /// duplicate cards that belong to the same anime [subjectId].
  int importLegacyKazumiSample() {
    final now = DateTime.now();
    final sample = [
      LegacyKazumiHistoryRecord(
        subjectId: 1001,
        pluginName: 'Kazumi · 哔哩备用源',
        episodeNumber: 14,
        positionSeconds: 910,
        durationSeconds: 1425,
        watchedAt: now.subtract(const Duration(minutes: 45)),
      ),
      LegacyKazumiHistoryRecord(
        subjectId: 1009,
        pluginName: 'Kazumi · 樱花源',
        episodeNumber: 13,
        positionSeconds: 720,
        durationSeconds: 1425,
        watchedAt: now.subtract(const Duration(hours: 3)),
      ),
      LegacyKazumiHistoryRecord(
        subjectId: 1009,
        pluginName: 'Kazumi · AGE 源',
        episodeNumber: 12,
        positionSeconds: 1415,
        durationSeconds: 1425,
        watchedAt: now.subtract(const Duration(days: 3)),
      ),
    ];
    state = MockSeedData.mergeLegacyKazumiRecords(state, sample);
    return sample.length;
  }

  void removeSubject(int subjectId) {
    state = [
      for (final item in state)
        if (item.subjectId != subjectId) item,
    ];
  }

  void clearAll() {
    state = const [];
  }
}

final historyProvider =
    NotifierProvider<HistoryNotifier, List<MergedHistoryEntry>>(
      HistoryNotifier.new,
    );

class RulesNotifier extends Notifier<List<RulePluginMeta>> {
  @override
  List<RulePluginMeta> build() => ref.read(ruleRepositoryProvider).getAllRules();

  void toggle(String ruleId, bool enabled) {
    state = ref.read(ruleRepositoryProvider).toggleRule(ruleId, enabled);
  }

  Future<void> testLatencies() async {
    state = await ref.read(ruleRepositoryProvider).testAllLatencies();
  }
}

final rulesProvider = NotifierProvider<RulesNotifier, List<RulePluginMeta>>(
  RulesNotifier.new,
);

/// Current active navigation tab index (shared across Mobile Dock & Desktop Sidebar).
class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);

/// Helper to read [FontManager.fontFamilyNotifier] cleanly.
String? currentCustomFontFamily() => FontManager.fontFamilyNotifier.value;
