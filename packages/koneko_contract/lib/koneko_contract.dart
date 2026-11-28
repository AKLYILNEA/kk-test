export 'online.dart';

/// Collection tracking state aligned with Bangumi & Animeko.
enum CollectionStatus {
  watching('在看'),
  wish('想看'),
  watched('看过'),
  onHold('搁置'),
  dropped('抛弃');

  const CollectionStatus(this.label);
  final String label;
}

/// Conflict resolution strategy when syncing collections with Bangumi (aligned with Kazumi).
enum BangumiSyncPriority {
  localFirst('以本机为准', '冲突时用本机状态覆盖 Bangumi'),
  bangumiFirst('以 Bangumi 为准', '冲突时用 Bangumi 状态覆盖本机'),
  timeFirst('保留最近更新', '自动比较双方更新时间保留最新状态');

  const BangumiSyncPriority(this.label, this.description);
  final String label;
  final String description;
}

/// Four-state episode lifecycle inspired by Animeko.
enum EpisodeWatchState { watched, current, aired, unaired }

/// Visual poster palette seed for deterministic procedural cover art
/// (replaced by network covers when koneko_core connects to Bangumi).
class PosterPalette {
  const PosterPalette({
    required this.primaryHex,
    required this.secondaryHex,
    required this.accentHex,
    required this.motifIndex,
  });

  final int primaryHex;
  final int secondaryHex;
  final int accentHex;
  final int motifIndex;
}

class AnimeSubject {
  const AnimeSubject({
    required this.subjectId,
    required this.title,
    required this.originalTitle,
    required this.summary,
    required this.score,
    required this.rank,
    required this.year,
    required this.seasonLabel,
    required this.weekday,
    required this.airedEpisodes,
    required this.totalEpisodes,
    required this.tags,
    required this.studio,
    required this.poster,
    this.coverUrl,
    this.relatedIds = const [],
  });

  final int subjectId;
  final String title;
  final String originalTitle;
  final String summary;
  final double score;
  final int rank;
  final int year;
  final String seasonLabel;

  /// 1 = Monday .. 7 = Sunday
  final int weekday;
  final int airedEpisodes;
  final int totalEpisodes;
  final List<String> tags;
  final String studio;
  final PosterPalette poster;
  final String? coverUrl;
  final List<int> relatedIds;

  bool get isCompleted => airedEpisodes >= totalEpisodes && totalEpisodes > 0;
}

class EpisodeItem {
  const EpisodeItem({
    required this.episodeNumber,
    required this.title,
    required this.durationSeconds,
    required this.airDate,
    required this.state,
  });

  final int episodeNumber;
  final String title;
  final int durationSeconds;
  final String airDate;
  final EpisodeWatchState state;
}

/// Kazumi-compatible rule plugin metadata.
class RulePluginMeta {
  const RulePluginMeta({
    required this.id,
    required this.name,
    required this.version,
    required this.baseUrl,
    required this.apiType,
    required this.enabled,
    required this.useNativePlayer,
    required this.supportsDanmaku,
    required this.latencyMs,
    required this.lastCheckedLabel,
    this.antiCrawlerEnabled = false,
    this.adBlocker = false,
    this.multiSources = true,
  });

  final String id;
  final String name;
  final String version;
  final String baseUrl;
  final String apiType;
  final bool enabled;
  final bool useNativePlayer;
  final bool supportsDanmaku;
  final int latencyMs;
  final String lastCheckedLabel;
  final bool antiCrawlerEnabled;
  final bool adBlocker;
  final bool multiSources;

  RulePluginMeta copyWith({
    bool? enabled,
    int? latencyMs,
    String? lastCheckedLabel,
  }) {
    return RulePluginMeta(
      id: id,
      name: name,
      version: version,
      baseUrl: baseUrl,
      apiType: apiType,
      enabled: enabled ?? this.enabled,
      useNativePlayer: useNativePlayer,
      supportsDanmaku: supportsDanmaku,
      latencyMs: latencyMs ?? this.latencyMs,
      lastCheckedLabel: lastCheckedLabel ?? this.lastCheckedLabel,
      antiCrawlerEnabled: antiCrawlerEnabled,
      adBlocker: adBlocker,
      multiSources: multiSources,
    );
  }
}

class RuleSourceProbe {
  const RuleSourceProbe({
    required this.ruleId,
    required this.ruleName,
    required this.lineLabel,
    required this.resolutionLabel,
    required this.latencyMs,
    required this.availableEpisodes,
    required this.available,
  });

  final String ruleId;
  final String ruleName;
  final String lineLabel;
  final String resolutionLabel;
  final int latencyMs;
  final int availableEpisodes;
  final bool available;
}

/// One source's watch record inside an Animeko-style merged per-anime history entry.
class SourceProgressRecord {
  const SourceProgressRecord({
    required this.ruleId,
    required this.ruleName,
    required this.episodeNumber,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.watchedAt,
    this.isCompleted = false,
  });

  final String ruleId;
  final String ruleName;
  final int episodeNumber;
  final int positionSeconds;
  final int durationSeconds;
  final DateTime watchedAt;
  final bool isCompleted;

  double get progressRatio => isCompleted
      ? 1
      : durationSeconds <= 0
      ? 0
      : (positionSeconds / durationSeconds).clamp(0, 1);
}

/// Animeko-style unified watch history card keyed strictly by [subjectId].
/// Unlike Kazumi (which splits each rule source into separate cards), Koneko
/// merges all sources for the same anime and tracks per-source records inside.
class MergedHistoryEntry {
  const MergedHistoryEntry({
    required this.subjectId,
    required this.lastEpisode,
    required this.lastPositionSeconds,
    required this.lastDurationSeconds,
    required this.lastRuleId,
    required this.lastRuleName,
    required this.updatedAt,
    required this.sourceRecords,
  });

  final int subjectId;
  final int lastEpisode;
  final int lastPositionSeconds;
  final int lastDurationSeconds;
  final String lastRuleId;
  final String lastRuleName;
  final DateTime updatedAt;
  final List<SourceProgressRecord> sourceRecords;

  int get mergedSourceCount =>
      sourceRecords.map((record) => record.ruleId).toSet().length;

  double get progressRatio => lastDurationSeconds <= 0
      ? 0
      : (lastPositionSeconds / lastDurationSeconds).clamp(0, 1);
}

/// Raw legacy Kazumi history record (split by pluginName + bangumiId),
/// automatically merged by [HistoryRepository.mergeLegacyKazumiRecords].
class LegacyKazumiHistoryRecord {
  const LegacyKazumiHistoryRecord({
    required this.subjectId,
    required this.pluginName,
    required this.episodeNumber,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.watchedAt,
  });

  final int subjectId;
  final String pluginName;
  final int episodeNumber;
  final int positionSeconds;
  final int durationSeconds;
  final DateTime watchedAt;
}

class CollectionEntry {
  const CollectionEntry({
    required this.subjectId,
    required this.status,
    required this.watchedEpisodes,
    required this.updatedAt,
  });

  final int subjectId;
  final CollectionStatus status;
  final int watchedEpisodes;
  final DateTime updatedAt;

  CollectionEntry copyWith({
    CollectionStatus? status,
    int? watchedEpisodes,
    DateTime? updatedAt,
  }) {
    return CollectionEntry(
      subjectId: subjectId,
      status: status ?? this.status,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DanmakuItem {
  const DanmakuItem({
    required this.timeSeconds,
    required this.text,
    required this.colorHex,
    required this.lane,
    this.source = '',
  });

  final double timeSeconds;
  final String text;
  final int colorHex;
  final int lane;

  /// Source tag from DanDanPlay aggregated feed (e.g. `[BiliBili]`, `[Gamer]`, `[AcFun]`, or DanDanPlay).
  final String source;
}

/// Persistent Kazumi-aligned Danmaku display, typography & source settings.
class DanmakuSettings {
  const DanmakuSettings({
    this.fontSize = 16.0,
    this.fontWeight = 4,
    this.strokeEnabled = true,
    this.strokeWidth = 1.5,
    this.opacity = 0.9,
    this.area = 0.5,
    this.duration = 8.0,
    this.lineHeight = 1.2,
    this.showScroll = true,
    this.showTop = true,
    this.showBottom = true,
    this.massiveMode = false,
    this.colorful = true,
    this.sourceBilibili = true,
    this.sourceGamer = true,
    this.sourceDandan = true,
  });

  final double fontSize;
  final int fontWeight;
  final bool strokeEnabled;
  final double strokeWidth;
  final double opacity;

  /// Display area ratio (0.25 = 1/4屏, 0.5 = 半屏, 0.75 = 3/4屏, 1.0 = 全屏).
  final double area;
  final double duration;
  final double lineHeight;
  final bool showScroll;
  final bool showTop;
  final bool showBottom;
  final bool massiveMode;
  final bool colorful;
  final bool sourceBilibili;
  final bool sourceGamer;
  final bool sourceDandan;

  bool allowsSource(String rawSource) {
    final lower = rawSource.toLowerCase();
    if (lower.contains('bilibili')) return sourceBilibili;
    if (lower.contains('gamer') || lower.contains('bahamut')) {
      return sourceGamer;
    }
    return sourceDandan;
  }

  DanmakuSettings copyWith({
    double? fontSize,
    int? fontWeight,
    bool? strokeEnabled,
    double? strokeWidth,
    double? opacity,
    double? area,
    double? duration,
    double? lineHeight,
    bool? showScroll,
    bool? showTop,
    bool? showBottom,
    bool? massiveMode,
    bool? colorful,
    bool? sourceBilibili,
    bool? sourceGamer,
    bool? sourceDandan,
  }) {
    return DanmakuSettings(
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      strokeEnabled: strokeEnabled ?? this.strokeEnabled,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      area: area ?? this.area,
      duration: duration ?? this.duration,
      lineHeight: lineHeight ?? this.lineHeight,
      showScroll: showScroll ?? this.showScroll,
      showTop: showTop ?? this.showTop,
      showBottom: showBottom ?? this.showBottom,
      massiveMode: massiveMode ?? this.massiveMode,
      colorful: colorful ?? this.colorful,
      sourceBilibili: sourceBilibili ?? this.sourceBilibili,
      sourceGamer: sourceGamer ?? this.sourceGamer,
      sourceDandan: sourceDandan ?? this.sourceDandan,
    );
  }

  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'strokeEnabled': strokeEnabled,
    'strokeWidth': strokeWidth,
    'opacity': opacity,
    'area': area,
    'duration': duration,
    'lineHeight': lineHeight,
    'showScroll': showScroll,
    'showTop': showTop,
    'showBottom': showBottom,
    'massiveMode': massiveMode,
    'colorful': colorful,
    'sourceBilibili': sourceBilibili,
    'sourceGamer': sourceGamer,
    'sourceDandan': sourceDandan,
  };

  static DanmakuSettings fromJson(Map<String, dynamic> map) {
    double numOr(String k, double fallback, double min, double max) =>
        map[k] is num
            ? (map[k] as num).toDouble().clamp(min, max)
            : fallback;
    int intOr(String k, int fallback, int min, int max) => map[k] is num
        ? (map[k] as num).toInt().clamp(min, max).toInt()
        : fallback;
    bool boolOr(String k, bool fallback) =>
        map[k] is bool ? map[k] as bool : fallback;
    return DanmakuSettings(
      fontSize: numOr('fontSize', 16.0, 10.0, 38.0),
      fontWeight: intOr('fontWeight', 4, 1, 9),
      strokeEnabled: boolOr('strokeEnabled', true),
      strokeWidth: numOr('strokeWidth', 1.5, 0.1, 3.0),
      opacity: numOr('opacity', 0.9, 0.1, 1.0),
      area: numOr('area', 0.5, 0.125, 1.0),
      duration: numOr('duration', 8.0, 2.0, 16.0),
      lineHeight: numOr('lineHeight', 1.2, 0.8, 2.4),
      showScroll: boolOr('showScroll', true),
      showTop: boolOr('showTop', true),
      showBottom: boolOr('showBottom', true),
      massiveMode: boolOr('massiveMode', false),
      colorful: boolOr('colorful', true),
      sourceBilibili: boolOr('sourceBilibili', true),
      sourceGamer: boolOr('sourceGamer', true),
      sourceDandan: boolOr('sourceDandan', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DanmakuSettings &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.strokeEnabled == strokeEnabled &&
      other.strokeWidth == strokeWidth &&
      other.opacity == opacity &&
      other.area == area &&
      other.duration == duration &&
      other.lineHeight == lineHeight &&
      other.showScroll == showScroll &&
      other.showTop == showTop &&
      other.showBottom == showBottom &&
      other.massiveMode == massiveMode &&
      other.colorful == colorful &&
      other.sourceBilibili == sourceBilibili &&
      other.sourceGamer == sourceGamer &&
      other.sourceDandan == sourceDandan;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontWeight,
    strokeEnabled,
    strokeWidth,
    opacity,
    area,
    duration,
    lineHeight,
    showScroll,
    showTop,
    showBottom,
    massiveMode,
    colorful,
    sourceBilibili,
    sourceGamer,
    sourceDandan,
  );
}

class SubjectComment {
  const SubjectComment({
    required this.userName,
    required this.content,
    required this.rate,
    required this.updatedAt,
    this.avatarUrl,
  });

  final String userName;
  final String content;
  final int rate;
  final DateTime updatedAt;
  final String? avatarUrl;
}

class SubjectCommentsPage {
  const SubjectCommentsPage({
    required this.items,
    required this.total,
    this.hasMore = false,
  });

  final List<SubjectComment> items;
  final int total;
  final bool hasMore;
}

abstract interface class CatalogRepository {
  List<AnimeSubject> getAllSubjects();
  AnimeSubject? getSubjectById(int subjectId);
  List<AnimeSubject> getTrending({String? tag});
  List<AnimeSubject> getByWeekday(int weekday);
  List<AnimeSubject> search(String query, {String? tag});
  List<EpisodeItem> getEpisodes(
    int subjectId, {
    int watchedCount = 0,
    int? currentEp,
  });
  List<RuleSourceProbe> probeSources(int subjectId);
  List<DanmakuItem> getDanmaku(int subjectId, int episodeNumber);
  List<SubjectComment> getComments(int subjectId);
}

abstract interface class RuleRepository {
  List<RulePluginMeta> getAllRules();
  List<RulePluginMeta> toggleRule(String ruleId, bool enabled);
  Future<List<RulePluginMeta>> testAllLatencies();
}
