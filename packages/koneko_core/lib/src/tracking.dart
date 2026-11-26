import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bangumi.dart';

class LocalTracking implements TrackingStore {
  LocalTracking(this._preferences) {
    final saved = _preferences.getString(_key);
    if (saved != null) {
      try {
        _current = decodeTracking(jsonObject(jsonDecode(saved)));
      } on FormatException {
        // An invalid cache never prevents the rest of the app from starting.
      }
    }
  }

  static const _key = 'koneko_tracking_v1';
  final SharedPreferences _preferences;
  final _changes = StreamController<TrackingSnapshot>.broadcast();
  TrackingSnapshot _current = const TrackingSnapshot();
  Future<void> _pending = Future.value();

  @override
  TrackingSnapshot get current => _current;

  @override
  Stream<TrackingSnapshot> get changes => _changes.stream;

  @override
  Future<void> update(TrackingSnapshot Function(TrackingSnapshot) edit) {
    _current = edit(_current);
    _changes.add(_current);
    final encoded = jsonEncode(encodeTracking(_current));
    return _pending = _pending.onError((Object _, StackTrace _) {}).then((
      _,
    ) async {
      if (!await _preferences.setString(_key, encoded)) {
        throw StateError('无法保存追番与历史');
      }
    });
  }
}

class SecureSettings implements SettingsVault {
  const SecureSettings({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _key = 'koneko_service_credentials_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<SecretSettings> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return const SecretSettings();
    final raw = jsonObject(jsonDecode(value));
    return SecretSettings(
      bangumiToken: jsonString(raw['bangumiToken']),
      webdavUrl: jsonString(raw['webdavUrl']),
      webdavUser: jsonString(raw['webdavUser']),
      webdavPassword: jsonString(raw['webdavPassword']),
      danmakuAppId: jsonString(raw['danmakuAppId']),
      danmakuKey: jsonString(raw['danmakuKey']),
      blockedDanmaku: jsonList(
        raw['blockedDanmaku'],
      ).whereType<String>().toList(),
    );
  }

  @override
  Future<void> write(SecretSettings settings) => _storage.write(
    key: _key,
    value: jsonEncode({
      'bangumiToken': settings.bangumiToken,
      'webdavUrl': settings.webdavUrl,
      'webdavUser': settings.webdavUser,
      'webdavPassword': settings.webdavPassword,
      'danmakuAppId': settings.danmakuAppId,
      'danmakuKey': settings.danmakuKey,
      'blockedDanmaku': settings.blockedDanmaku,
    }),
  );
}

DateTime _date(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(jsonInt(value));

Map<String, dynamic> encodeTracking(TrackingSnapshot snapshot) => {
  'schema': 1,
  'collections': [
    for (final item in snapshot.collections)
      {
        'id': item.subjectId,
        'status': item.status.name,
        'watched': item.watchedEpisodes,
        'modified': item.updatedAt.millisecondsSinceEpoch,
      },
  ],
  'history': [
    for (final item in snapshot.history)
      {
        'id': item.subjectId,
        'episode': item.lastEpisode,
        'duration': item.lastDurationSeconds,
        'position': item.lastPositionSeconds,
        'rule': item.lastRuleId,
        'name': item.lastRuleName,
        'modified': item.updatedAt.millisecondsSinceEpoch,
        'sources': [
          for (final source in item.sourceRecords)
            {
              'episode': source.episodeNumber,
              'duration': source.durationSeconds,
              'position': source.positionSeconds,
              'rule': source.ruleId,
              'name': source.ruleName,
              'modified': source.watchedAt.millisecondsSinceEpoch,
              'completed': source.isCompleted,
            },
        ],
      },
  ],
  'removedHistory': snapshot.removedHistory.map(
    (id, date) => MapEntry('$id', date.millisecondsSinceEpoch),
  ),
  'collectionChanges': snapshot.collectionChanges.map(
    (id, date) => MapEntry('$id', date.millisecondsSinceEpoch),
  ),
};

TrackingSnapshot decodeTracking(Map<String, dynamic> raw) {
  if (raw['schema'] != 1) throw const FormatException('不支持的 Koneko 同步格式');
  final collections = <CollectionEntry>[];
  for (final item in jsonList(raw['collections']).map(jsonObject)) {
    final status = CollectionStatus.values
        .where((status) => status.name == item['status'])
        .firstOrNull;
    if (status == null || jsonInt(item['id']) <= 0) continue;
    collections.add(
      CollectionEntry(
        subjectId: jsonInt(item['id']),
        status: status,
        watchedEpisodes: jsonInt(item['watched']),
        updatedAt: _date(item['modified']),
      ),
    );
  }
  final history = [
    for (final item in jsonList(raw['history']).map(jsonObject))
      if (jsonInt(item['id']) > 0)
        MergedHistoryEntry(
          subjectId: jsonInt(item['id']),
          lastEpisode: jsonInt(item['episode']),
          lastDurationSeconds: jsonInt(item['duration']),
          lastPositionSeconds: jsonInt(item['position']),
          lastRuleId: jsonString(item['rule']),
          lastRuleName: jsonString(item['name']),
          updatedAt: _date(item['modified']),
          sourceRecords: [
            for (final source in jsonList(item['sources']).map(jsonObject))
              SourceProgressRecord(
                ruleId: jsonString(source['rule']),
                ruleName: jsonString(source['name']),
                episodeNumber: jsonInt(source['episode']),
                positionSeconds: jsonInt(source['position']),
                durationSeconds: jsonInt(source['duration']),
                watchedAt: _date(source['modified']),
                isCompleted: source['completed'] == true,
              ),
          ],
        ),
  ];
  Map<int, DateTime> dates(Object? value) => {
    for (final item in jsonObject(value).entries)
      if (jsonInt(item.key) > 0) jsonInt(item.key): _date(item.value),
  };
  return TrackingSnapshot(
    collections: collections,
    history: history,
    removedHistory: dates(raw['removedHistory']),
    collectionChanges: dates(raw['collectionChanges']),
  );
}

TrackingSnapshot mergeTracking(
  TrackingSnapshot local,
  TrackingSnapshot remote,
) {
  final collections = <int, CollectionEntry>{};
  for (final entry in [...local.collections, ...remote.collections]) {
    final previous = collections[entry.subjectId];
    if (previous == null || entry.updatedAt.isAfter(previous.updatedAt)) {
      collections[entry.subjectId] = entry;
    }
  }

  final tombstones = Map<int, DateTime>.of(local.removedHistory);
  for (final item in remote.removedHistory.entries) {
    final previous = tombstones[item.key];
    if (previous == null || previous.isBefore(item.value)) {
      tombstones[item.key] = item.value;
    }
  }

  final history = <int, MergedHistoryEntry>{};
  for (final entry in [...local.history, ...remote.history]) {
    final removed = tombstones[entry.subjectId];
    if (removed != null && !entry.updatedAt.isAfter(removed)) continue;
    final existing = history[entry.subjectId];
    if (existing == null) {
      history[entry.subjectId] = entry;
      continue;
    }
    final sources = <(String, int), SourceProgressRecord>{};
    for (final source in [...existing.sourceRecords, ...entry.sourceRecords]) {
      if (removed != null && !source.watchedAt.isAfter(removed)) continue;
      final key = (source.ruleId, source.episodeNumber);
      final previous = sources[key];
      if (previous == null || source.watchedAt.isAfter(previous.watchedAt)) {
        sources[key] = source;
      }
    }
    final latest = entry.updatedAt.isAfter(existing.updatedAt)
        ? entry
        : existing;
    history[entry.subjectId] = MergedHistoryEntry(
      subjectId: latest.subjectId,
      lastEpisode: latest.lastEpisode,
      lastPositionSeconds: latest.lastPositionSeconds,
      lastDurationSeconds: latest.lastDurationSeconds,
      lastRuleId: latest.lastRuleId,
      lastRuleName: latest.lastRuleName,
      updatedAt: latest.updatedAt,
      sourceRecords: sources.values.toList()
        ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt)),
    );
  }
  return TrackingSnapshot(
    collections: collections.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    history: history.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    removedHistory: tombstones,
    collectionChanges: local.collectionChanges,
  );
}
