import 'koneko_contract.dart';

/// The cache-backed network capabilities are separate from synchronous reads.
abstract interface class OnlineCatalog implements CatalogRepository {
  Stream<void> get changes;
  String get seasonTitle;
  Future<void> refresh();
  Future<void> loadSubject(int id);
  Future<void> searchOnline(String query);
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

abstract interface class PlaybackSources {
  Future<List<SourceEpisode>> lookup(AnimeSubject subject, String ruleId);
  Future<PlayableMedia> resolve(SourceEpisode episode);
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
