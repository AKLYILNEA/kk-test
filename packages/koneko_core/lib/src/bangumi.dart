import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dio networkClient() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 9),
    receiveTimeout: const Duration(seconds: 16),
    sendTimeout: const Duration(seconds: 12),
    headers: {
      'user-agent':
          'AKLYILNEA/Koneko/0.0.4 (https://github.com/AKLYILNEA/kk-test)',
    },
  ),
);

Map<String, dynamic> jsonObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
List<dynamic> jsonList(Object? value) => value is List ? value : const [];
int jsonInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String jsonString(Object? value) => value is String ? value : '';

class BangumiCatalog implements OnlineCatalog {
  BangumiCatalog(this._preferences, {Dio? client})
    : _client = client ?? networkClient() {
    final raw = _preferences.getString(_cacheKey);
    if (raw == null) return;
    try {
      final cache = jsonObject(jsonDecode(raw));
      for (final data in jsonList(cache['subjects'])) {
        final item = jsonObject(data);
        final id = jsonInt(item['id']);
        if (id > 0) _subjects[id] = item;
      }
      _trending = jsonList(cache['trending']).map(jsonInt).toList();
      for (final day in jsonObject(cache['week']).entries) {
        _week[jsonInt(day.key)] = jsonList(day.value).map(jsonInt).toList();
      }
    } on FormatException {
      // A damaged cache never prevents an online refresh.
    }
  }

  static const _base = 'https://api.bgm.tv';
  static const _nextBase = 'https://next.bgm.tv';
  static const _cacheKey = 'koneko_bangumi_cache_v1';
  final SharedPreferences _preferences;
  final Dio _client;
  final _changes = StreamController<void>.broadcast();
  final _subjects = <int, Map<String, dynamic>>{};
  final _details = <int, Future<void>>{};
  final _episodes = <int, List<Map<String, dynamic>>>{};
  final _related = <int, List<int>>{};
  final _comments = <int, List<SubjectComment>>{};
  final _commentTotals = <int, int>{};
  final _week = <int, List<int>>{};
  final _queries = <String, List<int>>{};
  List<int> _trending = [];
  Future<void>? _refresh;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String get seasonTitle {
    final start = (DateTime.now().month - 1) ~/ 3;
    return '${DateTime.now().year} ${const ['冬', '春', '夏', '秋'][start]}季新番';
  }

  Future<dynamic> get(
    String endpoint, {
    Map<String, Object?>? query,
    String? token,
  }) async {
    final result = await _client.get<dynamic>(
      '$_base$endpoint',
      queryParameters: query,
      options: token == null
          ? null
          : Options(
              headers: {'authorization': 'Bearer $token'},
              followRedirects: false,
            ),
    );
    return result.data;
  }

  Future<dynamic> write(
    String endpoint,
    String method,
    String token,
    Map<String, Object?> data,
  ) async {
    final result = await _client.request<dynamic>(
      '$_base$endpoint',
      data: data,
      options: Options(
        method: method,
        headers: {'authorization': 'Bearer $token'},
        followRedirects: false,
      ),
    );
    return result.data;
  }

  @override
  Future<void> refresh() =>
      _refresh ??= _fetchHome().whenComplete(() => _refresh = null);

  Future<void> _fetchHome() async {
    final now = DateTime.now();
    final month = ((now.month - 1) ~/ 3) * 3 + 1;
    final start = DateTime(now.year, month);
    final end = DateTime(now.year, month + 3);
    String ymd(DateTime date) => date.toIso8601String().split('T').first;

    final requests = <Future<void>>[
      _client
          .post<dynamic>(
            '$_base/v0/search/subjects',
            queryParameters: {'limit': 50},
            data: {
              'keyword': '',
              'sort': 'heat',
              'filter': {
                'type': [2],
                'air_date': ['>=${ymd(start)}', '<${ymd(end)}'],
                'nsfw': false,
              },
            },
          )
          .then<void>((response) {
            _trending = _readSubjects(jsonObject(response.data)['data']);
          }),
      get('/calendar').then<void>((data) {
        final days = <int, List<int>>{};
        for (final value in jsonList(data)) {
          final day = jsonObject(value);
          final index = jsonInt(jsonObject(day['weekday'])['id']);
          if (index >= 1 && index <= 7) {
            days[index] = _readSubjects(day['items']);
          }
        }
        _week
          ..clear()
          ..addAll(days);
      }),
    ];
    final errors = <Object>[];
    await Future.wait(
      requests.map(
        (request) => request.catchError((Object error) {
          errors.add(error);
        }),
      ),
    );
    _notify();
    if (errors.length == requests.length ||
        (_trending.isEmpty && _week.isEmpty && errors.isNotEmpty)) {
      throw errors.first;
    }
  }

  @override
  Future<void> searchOnline(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return;
    final response = await _client.post<dynamic>(
      '$_base/v0/search/subjects',
      queryParameters: {'limit': 40},
      data: {
        'keyword': query.trim(),
        'sort': 'match',
        'filter': {
          'type': [2],
          'nsfw': false,
        },
      },
    );
    _queries[key] = _readSubjects(jsonObject(response.data)['data']);
    if (_queries.length > 40) _queries.remove(_queries.keys.first);
    _notify();
  }

  @override
  Future<void> loadSubject(int id) => _details.putIfAbsent(
    id,
    () => _fetchSubject(id).onError((Object error, StackTrace stack) {
      _details.remove(id);
      Error.throwWithStackTrace(error, stack);
    }),
  );

  Future<void> _fetchSubject(int id) async {
    final detail = await get('/v0/subjects/$id');
    final subject = jsonObject(detail);
    if (jsonInt(subject['id']) != id) throw const FormatException('番剧详情格式无效');
    _remember(subject);
    _notify();
    await Future.wait([
      _fetchEpisodes(id).onError((Object _, StackTrace _) {}),
      _fetchRelated(id).onError((Object _, StackTrace _) {}),
    ]);
    _notify();
  }

  Future<void> _fetchEpisodes(int id) async {
    final items = <Map<String, dynamic>>[];
    for (var offset = 0; offset < 1000; offset += 100) {
      final response = jsonObject(
        await get(
          '/v0/episodes',
          query: {'subject_id': id, 'type': 0, 'limit': 100, 'offset': offset},
        ),
      );
      final page = jsonList(response['data']);
      items.addAll(page.map(jsonObject));
      if (page.length < 100 ||
          offset + page.length >= jsonInt(response['total'])) {
        break;
      }
    }
    _episodes[id] = items;
  }

  Future<void> _fetchRelated(int id) async {
    final entries = jsonList(await get('/v0/subjects/$id/subjects'));
    _related[id] = [
      for (final data in entries)
        if (jsonInt(jsonObject(data)['type']) == 2) ..._readSubjects([data]),
    ];
  }

  void rememberExternal(Iterable<Map<String, dynamic>> subjects) {
    for (final subject in subjects) {
      _remember(subject);
    }
    if (subjects.isEmpty) return;
    _notify();
  }

  void _remember(Map<String, dynamic> item) {
    final id = jsonInt(item['id']);
    if (id == 0) return;
    final old = _subjects.remove(id);
    // The calendar and search responses omit some of the fields in detail.
    _subjects[id] = {...?old, ...item};
  }

  List<int> _readSubjects(Object? data) {
    final ids = <int>{};
    for (final entry in jsonList(data)) {
      final item = jsonObject(entry);
      final id = jsonInt(item['id']);
      if (id <= 0) continue;
      _remember(item);
      ids.add(id);
    }
    return ids.toList();
  }

  void _notify() {
    _changes.add(null);
    unawaited(_saveCache());
  }

  Future<void> _saveCache() async {
    try {
      await _preferences.setString(
        _cacheKey,
        jsonEncode({
          'subjects': _subjects.values
              .toList()
              .reversed
              .take(600)
              .toList()
              .reversed
              .toList(),
          'trending': _trending,
          'week': _week.map((day, ids) => MapEntry('$day', ids)),
        }),
      );
    } catch (_) {
      // Reads remain available in memory when only the cache write failed.
    }
  }

  List<AnimeSubject> _items(Iterable<int> ids, [String? tag]) => [
    for (final id in ids)
      if (getSubjectById(id) case final subject?)
        if (tag == null ||
            tag == '全部' ||
            subject.tags.any((item) => item.contains(tag)))
          subject,
  ];

  @override
  List<AnimeSubject> getAllSubjects() => _items(_subjects.keys);
  @override
  List<AnimeSubject> getTrending({String? tag}) => _items(
    _trending.isEmpty ? _week.values.expand((day) => day).toSet() : _trending,
    tag,
  );
  @override
  List<AnimeSubject> getByWeekday(int weekday) =>
      _items(_week[weekday] ?? const []);
  @override
  List<AnimeSubject> search(String query, {String? tag}) {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return getTrending(tag: tag);
    return _items(_queries[key] ?? const [], tag);
  }

  @override
  AnimeSubject? getSubjectById(int id) {
    final data = _subjects[id];
    if (data == null) return null;
    final rating = jsonObject(data['rating']);
    final cover = jsonObject(data['images']);
    // Prefer Bangumi `common` (400-600px, ~1/5 size of `large`) for Kazumi-speed loading,
    // falling back to `large` / `medium` / `small`.
    final url = const ['common', 'large', 'medium', 'small']
        .map((key) => jsonString(cover[key]))
        .firstWhere((url) => url.startsWith('https://'), orElse: () => '');
    var studio = '';
    for (final entry in jsonList(data['infobox'])) {
      final map = jsonObject(entry);
      final key = jsonString(map['key']);
      if (key == '动画制作' || key == '制作') {
        final rawVal = map['value'];
        if (rawVal is String && rawVal.trim().isNotEmpty) {
          studio = rawVal.trim();
          break;
        }
        if (rawVal is List && rawVal.isNotEmpty) {
          final first = rawVal.first;
          final text = first is Map ? jsonString(first['v']) : '$first';
          if (text.trim().isNotEmpty) {
            studio = text.trim();
            break;
          }
        }
      }
    }
    final date = DateTime.tryParse(
      jsonString(data['date']).isNotEmpty
          ? jsonString(data['date'])
          : jsonString(data['air_date']),
    );
    final original = jsonString(data['name']);
    final chinese = jsonString(data['name_cn']);
    final total = jsonInt(data['total_episodes']) > 0
        ? jsonInt(data['total_episodes'])
        : math.max(jsonInt(data['eps']), jsonInt(data['episodes']));
    final episodes = _episodes[id] ?? const [];
    final aired = episodes.where((ep) {
      final air = DateTime.tryParse(jsonString(ep['airdate']));
      return air != null && air.isBefore(DateTime.now());
    }).length;
    final tags = jsonList(data['tags'])
        .map((tag) => jsonString(jsonObject(tag)['name']))
        .where((tag) => tag.isNotEmpty)
        .toList();
    final weekday = _week.keys
        .where((day) => _week[day]!.contains(id))
        .firstOrNull;
    return AnimeSubject(
      subjectId: id,
      title: chinese.isEmpty
          ? (original.isEmpty ? 'Bangumi #$id' : original)
          : chinese,
      originalTitle: original,
      summary: jsonString(data['summary']),
      score: (rating['score'] as num?)?.toDouble() ?? 0,
      rank: jsonInt(rating['rank']) > 0
          ? jsonInt(rating['rank'])
          : math.max(4, _trending.indexOf(id) + 1),
      year: date?.year ?? 0,
      seasonLabel: date == null ? '' : '${date.year} 年 ${date.month} 月',
      weekday: weekday ?? date?.weekday ?? 1,
      airedEpisodes: aired,
      totalEpisodes: total,
      tags: tags.isEmpty ? const ['动画'] : tags,
      studio: studio,
      poster: const PosterPalette(
        primaryHex: 0xff35426a,
        secondaryHex: 0xff6578a4,
        accentHex: 0xffcfddfb,
        motifIndex: 6,
      ),
      coverUrl: url.isEmpty ? null : url,
      relatedIds: _related[id] ?? const [],
    );
  }

  @override
  List<EpisodeItem> getEpisodes(
    int subjectId, {
    int watchedCount = 0,
    int? currentEp,
  }) {
    final result = <EpisodeItem>[];
    for (final item in _episodes[subjectId] ?? const <Map<String, dynamic>>[]) {
      final number = jsonInt(item['sort']);
      if (number <= 0 || number != item['sort']) continue;
      final airdate = jsonString(item['airdate']);
      final air = DateTime.tryParse(airdate);
      final name = jsonString(item['name_cn']);
      result.add(
        EpisodeItem(
          episodeNumber: number,
          title: name.isNotEmpty ? name : jsonString(item['name']),
          durationSeconds: 0,
          airDate: airdate,
          state: number == currentEp
              ? EpisodeWatchState.current
              : number <= watchedCount
              ? EpisodeWatchState.watched
              : air != null && air.isAfter(DateTime.now())
              ? EpisodeWatchState.unaired
              : EpisodeWatchState.aired,
        ),
      );
    }
    return result;
  }

  @override
  List<RuleSourceProbe> probeSources(int subjectId) => const [];

  @override
  List<DanmakuItem> getDanmaku(int subjectId, int episodeNumber) => const [];

  @override
  List<SubjectComment> getComments(int subjectId) =>
      List.unmodifiable(_comments[subjectId] ?? const []);

  @override
  Future<SubjectCommentsPage> loadComments(
    int subjectId, {
    int offset = 0,
    int limit = 20,
  }) async {
    final response = await _client.get<dynamic>(
      '$_nextBase/p1/subjects/$subjectId/comments',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final payload = jsonObject(response.data);
    final total = jsonInt(payload['total']);
    final parsed = <SubjectComment>[];
    for (final raw in jsonList(payload['data'])) {
      final item = jsonObject(raw);
      final content = jsonString(item['comment']).trim();
      if (content.isEmpty) continue;
      final user = jsonObject(item['user']);
      final avatar = jsonObject(user['avatar']);
      final avatarUrl = const ['medium', 'large', 'small']
          .map((k) => jsonString(avatar[k]))
          .firstWhere((u) => u.startsWith('http'), orElse: () => '');
      final nickname = jsonString(user['nickname']).trim();
      final username = jsonString(user['username']).trim();
      final updatedSec = jsonInt(item['updatedAt']);
      parsed.add(
        SubjectComment(
          userName: nickname.isNotEmpty
              ? nickname
              : (username.isNotEmpty ? username : 'Bangumi 用户'),
          content: content,
          rate: jsonInt(item['rate']),
          updatedAt: updatedSec > 0
              ? DateTime.fromMillisecondsSinceEpoch(updatedSec * 1000)
              : DateTime.now(),
          avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
        ),
      );
    }

    final existing = offset == 0
        ? <SubjectComment>[]
        : List<SubjectComment>.from(_comments[subjectId] ?? const []);
    existing.addAll(parsed);
    _comments[subjectId] = existing;
    _commentTotals[subjectId] = math.max(total, existing.length);

    final hasMore = offset + parsed.length < total && parsed.isNotEmpty;
    return SubjectCommentsPage(
      items: List.unmodifiable(existing),
      total: _commentTotals[subjectId] ?? existing.length,
      hasMore: hasMore,
    );
  }
}
