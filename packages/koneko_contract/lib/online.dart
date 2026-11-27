import 'koneko_contract.dart';

/// Represents an anime broadcast season (quarter 1=冬, 2=春, 3=夏, 4=秋).
class AnimeSeason {
  const AnimeSeason({required this.year, required this.quarter});

  factory AnimeSeason.current([DateTime? now]) {
    final date = now ?? DateTime.now();
    return AnimeSeason(year: date.year, quarter: ((date.month - 1) ~/ 3) + 1);
  }

  final int year;

  /// 1 = 冬 (1月), 2 = 春 (4月), 3 = 夏 (7月), 4 = 秋 (10月).
  final int quarter;

  int get startMonth => (quarter - 1) * 3 + 1;

  String get seasonName =>
      const ['冬', '春', '夏', '秋'][(quarter - 1).clamp(0, 3)];

  String get label => '$year $seasonName季新番';

  String get shortLabel => '$year $seasonName';

  String get code => '${year}Q$quarter';

  bool isSameAs(AnimeSeason other) =>
      year == other.year && quarter == other.quarter;

  bool get isCurrent => isSameAs(AnimeSeason.current());

  bool isAfter(DateTime now) => DateTime(year, startMonth, 1).isAfter(now);

  (String start, String end) get dateRange {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final start = DateTime(year, startMonth, 1);
    final end = DateTime(year, startMonth + 3, 1);
    return (fmt(start), fmt(end));
  }

  @override
  bool operator ==(Object other) =>
      other is AnimeSeason && year == other.year && quarter == other.quarter;

  @override
  int get hashCode => Object.hash(year, quarter);
}

/// Condition-based Bangumi search filter aligned with Kazumi (without image search).
class SearchFilter {
  const SearchFilter({
    this.keyword = '',
    this.sort = 'heat',
    this.tags = const [],
    this.season,
    this.year,
    this.minScore,
    this.weekdays = const [],
  });

  final String keyword;

  /// One of `'heat'`, `'score'`, `'rank'`, `'match'`.
  final String sort;
  final List<String> tags;
  final AnimeSeason? season;
  final int? year;
  final double? minScore;
  final List<int> weekdays;

  bool get hasActiveFilters => activeFilterCount > 0;

  int get activeFilterCount {
    var count = 0;
    if (sort != 'heat') count++;
    if (tags.isNotEmpty) count++;
    if (season != null || year != null) count++;
    if (minScore != null && minScore! > 0) count++;
    if (weekdays.isNotEmpty) count++;
    return count;
  }

  SearchFilter copyWith({
    String? keyword,
    String? sort,
    List<String>? tags,
    Object? season = _sentinel,
    Object? year = _sentinel,
    Object? minScore = _sentinel,
    List<int>? weekdays,
  }) => SearchFilter(
    keyword: keyword ?? this.keyword,
    sort: sort ?? this.sort,
    tags: tags ?? this.tags,
    season: identical(season, _sentinel) ? this.season : season as AnimeSeason?,
    year: identical(year, _sentinel) ? this.year : year as int?,
    minScore: identical(minScore, _sentinel)
        ? this.minScore
        : minScore as double?,
    weekdays: weekdays ?? this.weekdays,
  );

  static const _sentinel = Object();
}

/// The cache-backed network capabilities are separate from synchronous reads.
class SubjectPerson {
  const SubjectPerson({
    required this.id,
    required this.name,
    this.imageUrl,
    this.credits = const [],
  });

  final int id;
  final String name;
  final String? imageUrl;
  final List<String> credits;
}

class SubjectCharacter {
  const SubjectCharacter({
    required this.id,
    required this.name,
    required this.relation,
    this.imageUrl,
    this.actors = const [],
  });

  final int id;
  final String name;
  final String relation;
  final String? imageUrl;
  final List<SubjectPerson> actors;
}

class SubjectRelation {
  const SubjectRelation({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.relation,
    required this.isAnime,
    this.imageUrl,
  });

  final int id;
  final String title;
  final String originalTitle;
  final String relation;
  final bool isAnime;
  final String? imageUrl;
}

class BangumiProfile {
  const BangumiProfile({
    required this.id,
    required this.username,
    required this.nickname,
    this.sign = '',
    this.avatarUrl = '',
  });

  final int id;
  final String username;
  final String nickname;
  final String sign;
  final String avatarUrl;
}

abstract interface class OnlineCatalog implements CatalogRepository {
  Stream<void> get changes;
  String get seasonTitle;
  Future<void> refresh();
  Future<bool> loadMoreTrending({String? tag});
  Future<BangumiProfile?> loadProfile(String token);
  Future<void> loadSubject(int id, {bool includeExtras = true});
  Future<List<SubjectCharacter>> loadCharacters(int subjectId);
  Future<List<SubjectPerson>> loadCredits(int subjectId);
  Future<List<SubjectRelation>> loadRelations(int subjectId);
  Future<void> searchOnline(String query);
  Future<List<AnimeSubject>> searchFiltered(
    SearchFilter filter, {
    int offset = 0,
    int limit = 30,
  });
  Future<Map<int, List<AnimeSubject>>> loadSeasonCalendar(AnimeSeason season);
  Future<SubjectCommentsPage> loadComments(
    int subjectId, {
    int offset = 0,
    int limit = 20,
  });
}

class RuleListing {
  const RuleListing({
    required this.name,
    required this.version,
    required this.url,
  });

  final String name;
  final String version;
  final Uri url;
}

abstract interface class ManagedRules implements RuleRepository {
  Future<List<RuleListing>> browse({String? repository});
  Future<List<RulePluginMeta>> install(Uri url);
  Future<List<RulePluginMeta>> importRules(String text);
  Future<List<RulePluginMeta>> removeRule(String id);
  String exportRule(String id);
}

class SourceEpisode {
  const SourceEpisode({
    required this.ruleId,
    required this.ruleName,
    required this.title,
    required this.line,
    required this.number,
    required this.page,
    this.headers = const {},
    this.legacy = false,
  });

  final String ruleId;
  final String ruleName;
  final String title;
  final String line;
  final int number;
  final Uri page;
  final Map<String, String> headers;
  final bool legacy;
}

class PlayableMedia {
  const PlayableMedia(this.uri, {this.headers = const {}, this.mimeType});

  final Uri uri;
  final Map<String, String> headers;
  final String? mimeType;
}

enum RuleProbeState { searching, found, noResult, captchaRequired, error }

class RuleSearchHit {
  const RuleSearchHit({required this.title, required this.sourceUrl});

  final String title;
  final String sourceUrl;
}

class RuleProbeResult {
  const RuleProbeResult({
    required this.ruleId,
    required this.ruleName,
    required this.state,
    this.hits = const [],
    this.message = '',
    this.verifyUrl,
    this.latencyMs = 0,
  });

  final String ruleId;
  final String ruleName;
  final RuleProbeState state;
  final List<RuleSearchHit> hits;
  final String message;
  final Uri? verifyUrl;
  final int latencyMs;
}

class DanmakuAnimeMatch {
  const DanmakuAnimeMatch({
    required this.animeId,
    required this.title,
    this.typeDescription = '',
    this.episodes = const [],
  });

  final int animeId;
  final String title;
  final String typeDescription;
  final List<DanmakuEpisodeMatch> episodes;
}

class DanmakuEpisodeMatch {
  const DanmakuEpisodeMatch({
    required this.episodeId,
    required this.episodeNumber,
    required this.title,
  });

  final int episodeId;
  final int episodeNumber;
  final String title;
}

enum MediaProbeStatus { reachable, inconclusive, invalid }

abstract interface class PlaybackSources {
  Future<List<SourceEpisode>> lookup(AnimeSubject subject, String ruleId);
  Future<PlayableMedia> resolve(
    SourceEpisode episode, {
    Future<void>? cancelled,
  });
  Future<MediaProbeStatus> probeMedia(
    PlayableMedia media, {
    Future<void>? cancelled,
  });
  Future<RuleProbeResult> probeRule(
    AnimeSubject subject,
    String ruleId, {
    String? keyword,
  });
  Future<List<SourceEpisode>> loadEpisodesFromHit(
    String ruleId,
    RuleSearchHit hit,
  );
  Future<void> saveVerificationCookies(
    String ruleId,
    Uri pageUrl,
    String cookieString, {
    String? userAgent,
  });
  String? lastSelectedRuleId(int subjectId);
  Future<void> rememberSelectedRule(int subjectId, String ruleId);
}

class PlaybackStatus {
  const PlaybackStatus({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.error,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool completed;
  final String? error;
}

abstract interface class PlaybackSession {
  Stream<PlaybackStatus> get changes;
  PlaybackStatus get status;
  Future<void> open(PlayableMedia media, {Duration startAt = Duration.zero});
  Future<void> seek(Duration position);
  Future<void> setPlaying(bool playing);
  Future<void> setRate(double rate);
  Future<void> setUpscaling(bool enabled);
  Future<void> dispose();
}

class SecretSettings {
  const SecretSettings({
    this.bangumiToken = '',
    this.webdavUrl = '',
    this.webdavUser = '',
    this.webdavPassword = '',
    this.danmakuAppId = '',
    this.danmakuKey = '',
    this.blockedDanmaku = const [],
  });

  final String bangumiToken;
  final String webdavUrl;
  final String webdavUser;
  final String webdavPassword;
  final String danmakuAppId;
  final String danmakuKey;
  final List<String> blockedDanmaku;
}

abstract interface class SettingsVault {
  Future<SecretSettings> read();
  Future<void> write(SecretSettings settings);
}

abstract interface class DanmakuSource {
  Future<List<DanmakuItem>> load(AnimeSubject subject, int episode);
  Future<List<DanmakuAnimeMatch>> searchAnimes(String keyword);
  Future<List<DanmakuItem>> loadByEpisodeId(int episodeId);
}

/// A tombstone protects deliberate local removals from being revived by sync.
class TrackingSnapshot {
  const TrackingSnapshot({
    this.collections = const [],
    this.history = const [],
    this.removedHistory = const {},
    this.collectionChanges = const {},
  });

  final List<CollectionEntry> collections;
  final List<MergedHistoryEntry> history;
  final Map<int, DateTime> removedHistory;
  final Map<int, DateTime> collectionChanges;

  TrackingSnapshot copyWith({
    List<CollectionEntry>? collections,
    List<MergedHistoryEntry>? history,
    Map<int, DateTime>? removedHistory,
    Map<int, DateTime>? collectionChanges,
  }) => TrackingSnapshot(
    collections: collections ?? this.collections,
    history: history ?? this.history,
    removedHistory: removedHistory ?? this.removedHistory,
    collectionChanges: collectionChanges ?? this.collectionChanges,
  );
}

abstract interface class TrackingStore {
  TrackingSnapshot get current;
  Stream<TrackingSnapshot> get changes;
  Future<void> update(TrackingSnapshot Function(TrackingSnapshot) edit);
}

abstract interface class TrackingSync {
  Future<int> syncBangumi();
  Future<int> syncWebDav();
  Future<int> importKazumi(List<int> bytes);
}

enum OfflineState { downloading, ready, failed }

class OfflineEpisode {
  const OfflineEpisode({
    required this.id,
    required this.subjectId,
    required this.subjectTitle,
    required this.number,
    required this.ruleId,
    required this.ruleName,
    required this.state,
    this.progress,
    this.media,
    this.error,
  });

  final String id;
  final int subjectId;
  final String subjectTitle;
  final int number;
  final String ruleId;
  final String ruleName;
  final OfflineState state;
  final double? progress;
  final Uri? media;
  final String? error;
}

abstract interface class OfflineLibrary {
  List<OfflineEpisode> get entries;
  Stream<List<OfflineEpisode>> get changes;
  Future<void> download(AnimeSubject subject, SourceEpisode episode);
  Future<void> remove(String id);
}
