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
  });

  final double timeSeconds;
  final String text;
  final int colorHex;
  final int lane;
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
