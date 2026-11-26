import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:koneko_contract/koneko_contract.dart';

import 'bangumi.dart';

class DandanplaySource implements DanmakuSource {
  DandanplaySource(this._vault, {Dio? client})
    : _client = client ?? networkClient();

  // Default DanDanPlay credentials aligned with Kazumi so danmaku works out of
  // the box without requiring manual API setup. CI/users may still override.
  static const _defaultAppId = 'qb998n8g3u';
  static const _defaultAppKey = '4y2waS6A6yb4uw7Dhd9pmdTzvrF7YUsg';
  static const _envAppId = String.fromEnvironment('DANDANAPI_APPID');
  static const _envAppKey = String.fromEnvironment('DANDANAPI_KEY');

  final SettingsVault _vault;
  final Dio _client;
  final _cache = <(int, int, String), List<DanmakuItem>>{};

  @override
  Future<List<DanmakuItem>> load(AnimeSubject subject, int episode) async {
    final settings = await _vault.read();
    final appId = settings.danmakuAppId.isNotEmpty
        ? settings.danmakuAppId
        : (_envAppId.isNotEmpty ? _envAppId : _defaultAppId);
    final key = settings.danmakuKey.isNotEmpty
        ? settings.danmakuKey
        : (_envAppKey.isNotEmpty ? _envAppKey : _defaultAppKey);

    final cacheKey = (subject.subjectId, episode, appId);
    var items = _cache[cacheKey];
    if (items == null) {
      Future<Map<String, dynamic>> get(
        String path, [
        Map<String, Object?>? query,
      ]) async {
        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final signature = base64Encode(
          sha256.convert(utf8.encode('$appId$timestamp$path$key')).bytes,
        );
        final response = await _client.get<dynamic>(
          'https://api.dandanplay.net$path',
          queryParameters: query,
          options: Options(
            followRedirects: false,
            headers: {
              'referer': '',
              'X-Auth': 1,
              'X-AppId': appId,
              'X-Timestamp': timestamp,
              'X-Signature': signature,
            },
          ),
        );
        return jsonObject(response.data);
      }

      var animeId = 0;
      var episodes = <dynamic>[];

      // 1. Primary lookup: match via Bangumi subject ID (aligned with Kazumi).
      try {
        final match = await get('/api/v2/bangumi/bgmtv/${subject.subjectId}');
        final bangumiObj = jsonObject(match['bangumi']);
        animeId = jsonInt(match['bangumiId'] ?? bangumiObj['animeId']);
        episodes = jsonList(bangumiObj['episodes']);
      } on Object {
        // Fallback to title search below.
      }

      // 2. Fallback lookup: search DanDanPlay by Chinese or original title.
      if (animeId <= 0) {
        final queries = <String>{
          if (subject.title.trim().isNotEmpty) subject.title.trim(),
          if (subject.originalTitle.trim().isNotEmpty)
            subject.originalTitle.trim(),
        };
        for (final query in queries) {
          try {
            final search = await get('/api/v2/search/episodes', {
              'anime': query,
              'v2': 'true',
            });
            final animes = jsonList(search['animes']);
            if (animes.isNotEmpty) {
              final first = jsonObject(animes.first);
              animeId = jsonInt(first['animeId']);
              episodes = jsonList(first['episodes']);
              if (animeId > 0) break;
            }
          } on Object {
            // Try next query candidate.
          }
        }
      }

      if (animeId <= 0) return const [];

      if (episodes.isEmpty) {
        try {
          final info = await get('/api/v2/bangumi/$animeId');
          episodes = jsonList(jsonObject(info['bangumi'])['episodes']);
        } on Object {
          // Proceed with Kazumi's episode ID convention if episode list fails.
        }
      }

      final matches = episodes
          .map(jsonObject)
          .where(
            (item) =>
                jsonInt(item['episodeNumber']) == episode ||
                RegExp(
                  r'^\s*(?:第\s*)?'
                  '$episode'
                  r'(?:\s*[集话話]|\s*$)',
                ).hasMatch(jsonString(item['episodeTitle'])),
          );
      final episodeId = jsonInt(matches.firstOrNull?['episodeId']);
      final id = episodeId > 0
          ? '$episodeId'
          : '$animeId${episode.toString().padLeft(4, '0')}';
      final raw = await get('/api/v2/comment/$id', {
        'withRelated': 'true',
        'chConvert': '1',
      });
      items = [];
      for (final comment in jsonList(raw['comments']).map(jsonObject)) {
        final parameters = jsonString(comment['p']).split(',');
        final text = jsonString(comment['m']).trim();
        if (parameters.length < 3 || text.isEmpty) continue;
        final seconds = double.tryParse(parameters.first);
        if (seconds == null || !seconds.isFinite || seconds < 0) continue;
        items.add(
          DanmakuItem(
            timeSeconds: seconds,
            text: text,
            colorHex: 0xff000000 | (int.tryParse(parameters[2]) ?? 0xffffff),
            lane: items.length % 6,
          ),
        );
      }
      items.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
      if (_cache.length >= 15) _cache.remove(_cache.keys.first);
      _cache[cacheKey] = items;
    }
    return items
        .where(
          (item) => !settings.blockedDanmaku.any(
            (word) => word.isNotEmpty && item.text.contains(word),
          ),
        )
        .toList();
  }
}
