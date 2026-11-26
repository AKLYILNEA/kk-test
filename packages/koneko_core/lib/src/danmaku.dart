import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:koneko_contract/koneko_contract.dart';

import 'bangumi.dart';

class DandanplaySource implements DanmakuSource {
  DandanplaySource(this._vault, {Dio? client})
    : _client = client ?? networkClient();

  final SettingsVault _vault;
  final Dio _client;
  final _cache = <(int, int, String), List<DanmakuItem>>{};

  @override
  Future<List<DanmakuItem>> load(AnimeSubject subject, int episode) async {
    final settings = await _vault.read();
    final appId = settings.danmakuAppId.isNotEmpty
        ? settings.danmakuAppId
        : const String.fromEnvironment('DANDANAPI_APPID');
    final key = settings.danmakuKey.isNotEmpty
        ? settings.danmakuKey
        : const String.fromEnvironment('DANDANAPI_KEY');
    if (appId.isEmpty || key.isEmpty) {
      throw StateError('请在服务设置中填写弹弹Play App ID 和密钥');
    }

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
              'X-Auth': 1,
              'X-AppId': appId,
              'X-Timestamp': timestamp,
              'X-Signature': signature,
            },
          ),
        );
        return jsonObject(response.data);
      }

      final match = await get('/api/v2/bangumi/bgmtv/${subject.subjectId}');
      final animeId = jsonInt(
        match['bangumiId'] ?? jsonObject(match['bangumi'])['animeId'],
      );
      if (animeId <= 0) return const [];
      final matchedEpisodes = jsonList(
        jsonObject(match['bangumi'])['episodes'],
      );
      final episodes = matchedEpisodes.isNotEmpty
          ? matchedEpisodes
          : jsonList(
              jsonObject(
                (await get('/api/v2/bangumi/$animeId'))['bangumi'],
              )['episodes'],
            );
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
