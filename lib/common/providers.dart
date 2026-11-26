import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/core_providers.dart';
import 'package:koneko/common/font_manager.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:koneko/common/core_providers.dart';

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
    this.tabAnimation = TabAnimationMode.fade,
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
      orElse: () => TabAnimationMode.fade,
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
          ? (map['textScale'] as num).toDouble().clamp(
              kMinTextScale,
              kMaxTextScale,
            )
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
  final seed = overrideColor ?? Color(primaryColor ?? kDefaultPrimaryColor);
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
    fontFamilyFallback: appFontFamilyFallback(
      platform: defaultTargetPlatform,
      locales: const [kAppLocale],
      fontFamily: customFontFamily,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tracking and rule state exposed to the UI
// ---------------------------------------------------------------------------

class LibraryNotifier extends Notifier<List<CollectionEntry>> {
  @override
  List<CollectionEntry> build() {
    ref.listen(trackingUpdatesProvider, (_, next) {
      if (next.value case final snapshot?) state = snapshot.collections;
    });
    return ref.watch(trackingStoreProvider)?.current.collections ?? const [];
  }

  void _save(List<CollectionEntry> next, int id, DateTime changedAt) {
    state = next;
    final store = ref.read(trackingStoreProvider);
    if (store == null) return;
    unawaited(
      store
          .update(
            (current) => current.copyWith(
              collections: next,
              collectionChanges: {...current.collectionChanges, id: changedAt},
            ),
          )
          .onError((Object _, StackTrace _) {}),
    );
  }

  CollectionEntry? entryFor(int subjectId) {
    for (final entry in state) {
      if (entry.subjectId == subjectId) return entry;
    }
    return null;
  }

  void setStatus(int subjectId, CollectionStatus status) {
    final now = DateTime.now();
    final entry = entryFor(subjectId);
    final updated =
        entry?.copyWith(status: status, updatedAt: now) ??
        CollectionEntry(
          subjectId: subjectId,
          status: status,
          watchedEpisodes: 0,
          updatedAt: now,
        );
    _save(
      [
        updated,
        for (final other in state)
          if (other.subjectId != subjectId) other,
      ],
      subjectId,
      now,
    );
  }

  void removeSubject(int subjectId) {
    final now = DateTime.now();
    _save(
      [
        for (final other in state)
          if (other.subjectId != subjectId) other,
      ],
      subjectId,
      now,
    );
  }

  void markEpisodeWatched(int subjectId, int episodeNumber, int totalEpisodes) {
    final existing = entryFor(subjectId);
    final previous = existing?.watchedEpisodes ?? 0;
    final nextWatched = episodeNumber > previous ? episodeNumber : previous;
    final isComplete = totalEpisodes > 0 && nextWatched >= totalEpisodes;
    final status = isComplete || existing?.status == CollectionStatus.watched
        ? CollectionStatus.watched
        : CollectionStatus.watching;
    if (existing != null &&
        status == existing.status &&
        nextWatched == previous) {
      return;
    }
    final now = DateTime.now();
    _save(
      [
        CollectionEntry(
          subjectId: subjectId,
          status: status,
          watchedEpisodes: nextWatched,
          updatedAt: now,
        ),
        for (final other in state)
          if (other.subjectId != subjectId) other,
      ],
      subjectId,
      now,
    );
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, List<CollectionEntry>>(
      LibraryNotifier.new,
    );

class HistoryNotifier extends Notifier<List<MergedHistoryEntry>> {
  @override
  List<MergedHistoryEntry> build() {
    ref.listen(trackingUpdatesProvider, (_, next) {
      if (next.value case final snapshot?) state = snapshot.history;
    });
    return ref.watch(trackingStoreProvider)?.current.history ?? const [];
  }

  void _save(
    List<MergedHistoryEntry> entries, {
    Iterable<int> removed = const [],
  }) {
    state = entries;
    final store = ref.read(trackingStoreProvider);
    if (store == null) return;
    final now = DateTime.now();
    unawaited(
      store
          .update(
            (current) => current.copyWith(
              history: entries,
              removedHistory: {
                ...current.removedHistory,
                for (final id in removed) id: now,
              },
            ),
          )
          .onError((Object _, StackTrace _) {}),
    );
  }

  SourceProgressRecord? positionFor(int subjectId, int episode) => entryFor(
    subjectId,
  )?.sourceRecords.where((item) => item.episodeNumber == episode).firstOrNull;

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
    bool completed = false,
  }) {
    final now = DateTime.now();
    final newSourceRec = SourceProgressRecord(
      ruleId: ruleId,
      ruleName: ruleName,
      episodeNumber: episodeNumber,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      watchedAt: now,
      isCompleted: completed,
    );

    final existing = entryFor(subjectId);
    final mergedSources = <SourceProgressRecord>[
      newSourceRec,
      if (existing != null)
        ...existing.sourceRecords.where(
          (r) => r.ruleId != ruleId || r.episodeNumber != episodeNumber,
        ),
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

    _save([
      updated,
      for (final item in state)
        if (item.subjectId != subjectId) item,
    ]);
  }

  void removeSubject(int subjectId) {
    _save(
      [
        for (final item in state)
          if (item.subjectId != subjectId) item,
      ],
      removed: [subjectId],
    );
  }

  void clearAll() {
    _save(const [], removed: state.map((entry) => entry.subjectId).toList());
  }
}

final historyProvider =
    NotifierProvider<HistoryNotifier, List<MergedHistoryEntry>>(
      HistoryNotifier.new,
    );

class RulesNotifier extends Notifier<List<RulePluginMeta>> {
  @override
  List<RulePluginMeta> build() =>
      ref.read(ruleRepositoryProvider).getAllRules();

  void toggle(String ruleId, bool enabled) {
    state = ref.read(ruleRepositoryProvider).toggleRule(ruleId, enabled);
  }

  void replace(List<RulePluginMeta> rules) {
    state = rules;
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
