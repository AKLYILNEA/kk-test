import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:webdav_client/webdav_client.dart' as dav;

import 'bangumi.dart';
import 'kazumi/modules/bangumi/bangumi_item.dart';
import 'kazumi/modules/bangumi/bangumi_tag.dart';
import 'kazumi/modules/collect/collect_change_module.dart';
import 'kazumi/modules/collect/collect_module.dart';
import 'kazumi/modules/history/history_module.dart';
import 'kazumi/modules/history/history_sync.dart';
import 'rules.dart';
import 'tracking.dart';

class KonekoSync implements TrackingSync {
  KonekoSync(this._store, this._catalog, this._vault, this._preferences);

  final TrackingStore _store;
  final BangumiCatalog _catalog;
  final SettingsVault _vault;
  final SharedPreferences _preferences;
  Future<int>? _bangumi;
  Future<int>? _webdav;

  static const _statuses = [
    CollectionStatus.wish,
    CollectionStatus.watched,
    CollectionStatus.watching,
    CollectionStatus.onHold,
    CollectionStatus.dropped,
  ];
  static const _kazumiStatuses = [
    CollectionStatus.watching,
    CollectionStatus.wish,
    CollectionStatus.onHold,
    CollectionStatus.watched,
    CollectionStatus.dropped,
  ];

  @override
  Future<int> syncBangumi() =>
      _bangumi ??= _syncBangumi().whenComplete(() => _bangumi = null);

  Future<int> _syncBangumi() async {
    final token = (await _vault.read()).bangumiToken.trim();
    if (token.isEmpty) throw StateError('请先在服务设置中填写 Bangumi Access Token');
    final account = jsonObject(await _catalog.get('/v0/me', token: token));
    final username = jsonString(account['username']);
    if (username.isEmpty) throw StateError('Bangumi 账号验证失败');

    final remote = <CollectionEntry>[];
    final metadata = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 100) {
      final response = jsonObject(
        await _catalog.get(
          '/v0/users/${Uri.encodeComponent(username)}/collections',
          query: {'subject_type': 2, 'limit': 100, 'offset': offset},
          token: token,
        ),
      );
      final rows = jsonList(response['data']);
      for (final entry in rows.map(jsonObject)) {
        final id = jsonInt(entry['subject_id']);
        final status = jsonInt(entry['type']);
        if (id <= 0 || status < 1 || status > _statuses.length) continue;
        final brief = jsonObject(entry['subject']);
        if (brief.isNotEmpty) metadata.add({...brief, 'id': id});
        remote.add(
          CollectionEntry(
            subjectId: id,
            status: _statuses[status - 1],
            watchedEpisodes: jsonInt(entry['ep_status']),
            updatedAt:
                DateTime.tryParse(jsonString(entry['updated_at'])) ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
      if (rows.length < 100 ||
          offset + rows.length >= jsonInt(response['total'])) {
        break;
      }
    }
    _catalog.rememberExternal(metadata);
    await _store.update((local) {
      final pending = local.collectionChanges;
      return mergeTracking(
        local,
        TrackingSnapshot(
          collections: [
            for (final entry in remote)
              if (!pending.containsKey(entry.subjectId)) entry,
          ],
        ),
      );
    });

    final current = _store.current;
    for (final entry in current.collections) {
      final id = entry.subjectId;
      final stamp = current.collectionChanges[id];
      if (stamp == null) continue;
      final path = '/v0/users/-/collections/$id';
      final played = current.history
          .where((history) => history.subjectId == id)
          .firstOrNull;
      final completed =
          played?.sourceRecords
              .where((source) => source.isCompleted)
              .map((source) => source.episodeNumber)
              .toSet() ??
          const <int>{};
      if (completed.isNotEmpty) {
        final ids = <int>[];
        for (var offset = 0; offset < 1000; offset += 100) {
          final response = jsonObject(
            await _catalog.get(
              '/v0/episodes',
              query: {
                'subject_id': id,
                'type': 0,
                'limit': 100,
                'offset': offset,
              },
            ),
          );
          final rows = jsonList(response['data']);
          for (final row in rows.map(jsonObject)) {
            final number = jsonInt(row['sort']);
            final episodeId = jsonInt(row['id']);
            if (row['sort'] == number &&
                completed.contains(number) &&
                episodeId > 0) {
              ids.add(episodeId);
            }
          }
          if (rows.length < 100 ||
              offset + rows.length >= jsonInt(response['total'])) {
            break;
          }
        }
        // Create the collection if needed before registering episode progress.
        await _catalog.write(path, 'POST', token, {
          'type': _statuses.indexOf(entry.status) + 1,
        });
        if (ids.isNotEmpty) {
          await _catalog.write('$path/episodes', 'PATCH', token, {
            'episode_id': ids,
            'type': 2,
          });
        }
      }
      // Reapply the intended status after Bangumi recalculates progress.
      await _catalog.write(path, 'POST', token, {
        'type': _statuses.indexOf(entry.status) + 1,
      });
      await _store.update(
        (now) => now.copyWith(
          collectionChanges: {
            for (final change in now.collectionChanges.entries)
              if (change.key != id || change.value != stamp)
                change.key: change.value,
          },
        ),
      );
    }
    return remote.length;
  }

  @override
  Future<int> syncWebDav() =>
      _webdav ??= _syncWebDav().whenComplete(() => _webdav = null);

  Future<int> _syncWebDav() async {
    final settings = await _vault.read();
    if (settings.webdavUrl.trim().isEmpty) {
      throw StateError('请先在服务设置中填写 WebDAV 地址');
    }
    final address = networkUri(settings.webdavUrl).toString();
    final client = dav.newClient(
      address,
      user: settings.webdavUser,
      password: settings.webdavPassword,
    );
    client.c.options
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 35)
      ..sendTimeout = const Duration(seconds: 35)
      ..followRedirects = false;
    await client.ping();

    const ownRoot = '/konekoSync';
    await client.mkdirAll(ownRoot);
    var remote = const TrackingSnapshot();
    for (final file in await client.readDir(ownRoot)) {
      final name = file.name ?? '';
      if (!RegExp(r'^[A-Fa-f0-9-]{36}\.json$').hasMatch(name) ||
          file.isDir == true) {
        continue;
      }
      final data = await client.read('$ownRoot/$name');
      remote = mergeTracking(
        remote,
        decodeTracking(jsonObject(jsonDecode(utf8.decode(data)))),
      );
    }

    final legacy = await _readKazumi(client);
    remote = mergeTracking(remote, legacy);
    await _store.update((local) => mergeTracking(local, remote));
    var device = _preferences.getString('koneko_webdav_device');
    if (device == null) {
      device = const Uuid().v4();
      if (!await _preferences.setString('koneko_webdav_device', device)) {
        throw StateError('设备标识保存失败');
      }
    }
    final destination = '$ownRoot/$device.json';
    final temporary = '$destination.pending';
    final snapshot = _store.current.copyWith(collectionChanges: const {});
    await client.write(
      temporary,
      utf8.encode(jsonEncode(encodeTracking(snapshot))),
    );
    await client.rename(temporary, destination, true);
    return remote.history.length + remote.collections.length;
  }

  Future<TrackingSnapshot> _readKazumi(dav.Client client) async {
    const root = '/kazumiSync';
    try {
      final listing = await client.readDir(root);
      final names = listing.map((file) => file.name).toSet();
      final collected = names.contains('collectibles.tmp')
          ? await _readHive(await client.read('$root/collectibles.tmp'))
          : const <Object>[];
      final changes = names.contains('collectchanges.tmp')
          ? await _readHive(await client.read('$root/collectchanges.tmp'))
          : const <Object>[];
      final collections = _legacyCollections(collected, changes);

      HistorySyncSnapshot snapshot = HistorySyncSnapshot.empty();
      if (names.contains('history')) {
        final files = await client.readDir('$root/history');
        final entries = files.map((file) => file.name).toSet();
        if (entries.contains('snapshot.json')) {
          final bytes = await client.read('$root/history/snapshot.json');
          snapshot = HistorySyncSnapshot.fromJson(
            jsonObject(jsonDecode(utf8.decode(bytes))),
          );
        }
        if (entries.contains('changes')) {
          final merger = HistorySyncStreamMerger(snapshot);
          for (final file in await client.readDir('$root/history/changes')) {
            final name = file.name ?? '';
            if (!RegExp(r'^[A-Za-z0-9_-]+\.jsonl$').hasMatch(name) ||
                file.isDir == true ||
                file.size == 0) {
              continue;
            }
            final bytes = await client.read('$root/history/changes/$name');
            merger.addAll(
              HistorySyncCodec.eventsFromJsonLines(utf8.decode(bytes)),
            );
          }
          snapshot = merger.snapshot();
        }
      } else if (names.contains('history.tmp')) {
        snapshot = HistorySyncSnapshot.fromHistories(
          (await _readHive(
            await client.read('$root/history.tmp'),
          )).whereType<History>().toList(),
        );
      }
      return _withLegacyHistory(snapshot.histories, collections);
    } on Object catch (error) {
      // The legacy directory is optional on a fresh WebDAV account.
      if (error is Exception && error.toString().contains('404')) {
        return const TrackingSnapshot();
      }
      rethrow;
    }
  }

  @override
  Future<int> importKazumi(List<int> bytes) async {
    String? text;
    try {
      text = utf8.decode(bytes).trim();
    } on FormatException {
      // Older Kazumi installations exported binary Hive boxes.
    }
    TrackingSnapshot imported;
    if (text != null && (text.startsWith('{') || text.startsWith('['))) {
      imported = _decodeKazumiText(text);
    } else {
      final values = await _readHive(bytes);
      imported = _withLegacyHistory(
        values.whereType<History>(),
        _legacyCollections(values, const []),
      );
      if (imported.collections.isEmpty && imported.history.isEmpty) {
        throw const FormatException('备份中没有追番或历史记录');
      }
    }
    await _store.update((local) => mergeTracking(local, imported));
    return imported.history.length + imported.collections.length;
  }

  TrackingSnapshot _decodeKazumiText(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      final snapshot = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: HistorySyncCodec.eventsFromJsonLines(text),
      );
      return _withLegacyHistory(snapshot.histories, const []);
    }
    final root = jsonObject(decoded);
    if (root['schema'] == 1) return decodeTracking(root);
    if (root.containsKey('histories')) {
      return _withLegacyHistory(
        HistorySyncSnapshot.fromJson(root).histories,
        const [],
      );
    }
    if (root.containsKey('bangumiItem') && root.containsKey('progresses')) {
      return _withLegacyHistory([
        HistorySyncCodec.historyFromJson(root),
      ], const []);
    }
    if (decoded is List) {
      return _withLegacyHistory(
        decoded.map(
          (item) => HistorySyncCodec.historyFromJson(jsonObject(item)),
        ),
        const [],
      );
    }
    if (root.containsKey('op')) {
      final merger = HistorySyncStreamMerger(HistorySyncSnapshot.empty())
        ..add(HistorySyncEvent.fromJson(root));
      return _withLegacyHistory(merger.snapshot().histories, const []);
    }
    throw const FormatException('无法识别 Kazumi 备份');
  }

  List<CollectionEntry> _legacyCollections(
    Iterable<Object> items,
    Iterable<Object> changes,
  ) {
    final deleted = <int, CollectedBangumiChange>{};
    for (final change in changes.whereType<CollectedBangumiChange>()) {
      if ((deleted[change.bangumiID]?.timestamp ?? 0) < change.timestamp) {
        deleted[change.bangumiID] = change;
      }
    }
    final entries = <CollectionEntry>[];
    final subjects = <Map<String, dynamic>>[];
    for (final item in items.whereType<CollectedBangumi>()) {
      final id = item.bangumiItem.id;
      final mutation = deleted[id];
      if (mutation?.action == 3 &&
          mutation!.timestamp * 1000 >= item.time.millisecondsSinceEpoch) {
        continue;
      }
      if (item.type < 1 || item.type > _kazumiStatuses.length) continue;
      subjects.add(_legacySubject(item.bangumiItem));
      entries.add(
        CollectionEntry(
          subjectId: id,
          status: _kazumiStatuses[item.type - 1],
          watchedEpisodes: 0,
          updatedAt: item.time,
        ),
      );
    }
    _catalog.rememberExternal(subjects);
    return entries;
  }

  TrackingSnapshot _withLegacyHistory(
    Iterable<History> input,
    List<CollectionEntry> collections,
  ) {
    var data = TrackingSnapshot(collections: collections);
    final subjects = <Map<String, dynamic>>[];
    for (final item in input) {
      subjects.add(_legacySubject(item.bangumiItem));
      final current = item.progresses[item.lastWatchEpisode];
      final id = item.adapterName.toLowerCase();
      final history = MergedHistoryEntry(
        subjectId: item.bangumiItem.id,
        lastEpisode: item.lastWatchEpisode,
        lastPositionSeconds: current?.progress.inSeconds ?? 0,
        lastDurationSeconds: current?.totalDuration.inSeconds ?? 0,
        lastRuleId: id,
        lastRuleName: item.adapterName,
        updatedAt: item.lastWatchTime,
        sourceRecords: [
          for (final entry in item.progresses.entries)
            SourceProgressRecord(
              ruleId: id,
              ruleName: item.adapterName,
              episodeNumber: entry.key,
              positionSeconds: entry.value.progress.inSeconds,
              durationSeconds: entry.value.totalDuration.inSeconds,
              watchedAt: DateTime.fromMillisecondsSinceEpoch(
                entry.value.effectiveUpdatedAtMs(item.lastWatchTime),
              ),
              isCompleted: entry.value.isCompleted,
            ),
        ],
      );
      data = mergeTracking(data, TrackingSnapshot(history: [history]));
    }
    _catalog.rememberExternal(subjects);
    return data;
  }

  static Map<String, dynamic> _legacySubject(BangumiItem item) => {
    'id': item.id,
    'name': item.name,
    'name_cn': item.nameCn,
    'summary': item.summary,
    'air_date': item.airDate,
    'rating': {'score': item.ratingScore, 'rank': item.rank},
    'images': item.images,
    'tags': item.tags.map((tag) => tag.toJson()).toList(),
  };

  static Future<List<Object>> _readHive(List<int> bytes) async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(BangumiItemAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(HistoryAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProgressAdapter());
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(CollectedBangumiAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(BangumiTagAdapter());
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(CollectedBangumiChangeAdapter());
    }
    final box = await Hive.openBox<dynamic>(
      'koneko_import_${const Uuid().v4()}',
      bytes: Uint8List.fromList(bytes),
    );
    try {
      return box.values.whereType<Object>().toList();
    } finally {
      await box.close();
    }
  }
}
