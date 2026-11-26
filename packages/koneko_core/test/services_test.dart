import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:koneko_core/src/bangumi.dart';
import 'package:koneko_core/src/downloads.dart';
import 'package:koneko_core/src/playback_sources.dart';
import 'package:koneko_core/src/rules.dart';
import 'package:koneko_core/src/sync.dart';
import 'package:koneko_core/src/tracking.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test(
    'Bangumi feed, calendar, search and detail share real IDs and local cache',
    () async {
      final adapter = _FixtureAdapter();
      final catalog = BangumiCatalog(
        preferences,
        client: Dio()..httpClientAdapter = adapter,
      );
      await catalog.refresh();
      expect(catalog.getTrending().single.subjectId, 414461);
      expect(
        catalog.getByWeekday(5).single.coverUrl,
        'https://example.com/cover.jpg',
      );

      await catalog.searchOnline('芙莉莲');
      expect(catalog.search('芙莉莲').single.title, '葬送的芙莉莲');
      await catalog.loadSubject(414461);
      expect(
        catalog.getEpisodes(414461, currentEp: 1).single.state,
        EpisodeWatchState.current,
      );
      expect(catalog.getSubjectById(414461)?.summary, '详情');
      await Future<void>.delayed(Duration.zero);
      expect(
        BangumiCatalog(
          preferences,
          client: Dio(),
        ).getSubjectById(414461)?.subjectId,
        414461,
      );
    },
  );

  test(
    'Kazumi XPath and API rules import, match a real HTTP fixture and survive reload',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        final response = request.response;
        response.headers.contentType = ContentType.html;
        switch (request.uri.path) {
          case '/search':
            expect(request.uri.queryParameters['keyword'], '葬送的芙莉莲');
            response.write(
              '<ul id="result"><li><a href="/subject">葬送的芙莉莲</a></li></ul>',
            );
          case '/subject':
            response.write(
              '<div class="road"><a href="/video.mp4">第1集</a></div>',
            );
          case '/api/search':
            response.headers.contentType = ContentType.json;
            response.write(
              jsonEncode({
                'data': [
                  {'name': '葬送的芙莉莲', 'src': '/subject'},
                ],
              }),
            );
          default:
            response.statusCode = 404;
        }
        await response.close();
      });
      final rules = KazumiRules(preferences);
      final xpath = {
        'name': 'Fixture',
        'api': '9',
        'version': '1',
        'baseURL': base,
        'searchURL': '$base/search?keyword=@keyword',
        'searchList': '//ul[@id="result"]/li',
        'searchName': './a',
        'searchResult': './a',
        'chapterRoads': '//div[@class="road"]',
        'chapterResult': './a',
      };
      final api = {
        ...xpath,
        'name': 'Fixture API',
        'searchMode': 'api',
        'searchApiConfig': {
          'request': {'url': '$base/api/search', 'method': 'GET'},
          'listPath': r'$.data[*]',
          'namePath': r'$.name',
          'sourcePath': r'$.src',
        },
      };
      await rules.importRules(jsonEncode(xpath));
      final sources = KazumiSources(rules);
      final selected = (await sources.lookup(_subject, 'fixture')).single;
      expect(selected.number, 1);
      expect((await sources.resolve(selected)).uri.path, '/video.mp4');
      final loaded = await rules.importRules(jsonEncode(api));
      expect(loaded.last.apiType, 'API');
      expect(
        (await sources.lookup(_subject, 'fixture api')).single.page.path,
        '/video.mp4',
      );
      expect(jsonDecode(rules.exportRule('fixture api'))['searchMode'], 'api');
      rules.toggleRule('fixture', false);
      // The persistence queue is flushed by the following import.
      await rules.importRules(jsonEncode(api));
      expect(KazumiRules(preferences).getAllRules().first.enabled, false);
    },
  );

  test(
    'Kazumi JSON history import merges sources and retains separate episode progress',
    () async {
      final store = LocalTracking(preferences);
      final catalog = BangumiCatalog(preferences);
      final sync = KonekoSync(store, catalog, _EmptyVault(), preferences);
      final history = {
        'bangumiItem': {
          'id': 414461,
          'type': 2,
          'name': '葬送的フリーレン',
          'nameCn': '葬送的芙莉莲',
        },
        'lastWatchEpisode': 1,
        'adapterName': '规则 A',
        'lastWatchTime': 10000,
        'progresses': {
          '1': {
            'episode': 1,
            'road': 0,
            'progressMs': 5000,
            'totalDurationMs': 20000,
            'isCompleted': false,
          },
        },
      };
      final backup = {
        'histories': [
          history,
          {...history, 'adapterName': '规则 B', 'lastWatchTime': 11000},
        ],
      };
      expect(await sync.importKazumi(utf8.encode(jsonEncode(backup))), 1);
      expect(store.current.history.single.mergedSourceCount, 2);
      expect(store.current.history.single.lastRuleName, '规则 B');

      final removed = mergeTracking(
        TrackingSnapshot(
          removedHistory: {414461: DateTime.fromMillisecondsSinceEpoch(12000)},
        ),
        store.current,
      );
      expect(removed.history, isEmpty);
      expect(
        LocalTracking(preferences).current.history.single.sourceRecords,
        hasLength(2),
      );
    },
  );

  test(
    'HLS offline cache rewrites segments and can reopen and remove the local file',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final directory = await Directory.systemTemp.createTemp(
        'koneko-offline-fixture-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final base = Uri.parse('http://127.0.0.1:${server.port}/');
      server.listen((request) async {
        if (request.uri.path == '/playlist.m3u8') {
          request.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nclip.ts\n#EXT-X-ENDLIST\n',
          );
        } else {
          request.response.add([1, 2, 3]);
        }
        await request.response.close();
      });
      final sources = _DirectSource();
      final library = LocalOfflineLibrary(directory, preferences, sources);
      final episode = SourceEpisode(
        ruleId: 'fixture',
        ruleName: 'Fixture',
        title: '01',
        line: '线路 1',
        number: 1,
        page: base.resolve('playlist.m3u8'),
      );
      await library.download(_subject, episode);
      final saved = library.entries.single;
      expect(saved.state, OfflineState.ready);
      final playlist = File.fromUri(saved.media!);
      expect(await playlist.readAsString(), contains('part_0.ts'));
      expect(
        File.fromUri(playlist.uri.resolve('part_0.ts')).readAsBytesSync(),
        [1, 2, 3],
      );
      expect(
        LocalOfflineLibrary(
          directory,
          preferences,
          sources,
        ).entries.single.state,
        OfflineState.ready,
      );
      await library.remove(saved.id);
      expect(library.entries, isEmpty);
      expect(await playlist.exists(), false);
    },
  );
}

const _subject = AnimeSubject(
  subjectId: 414461,
  title: '葬送的芙莉莲',
  originalTitle: '葬送的フリーレン',
  summary: '',
  score: 8.8,
  rank: 4,
  year: 2023,
  seasonLabel: '2023 秋',
  weekday: 5,
  airedEpisodes: 1,
  totalEpisodes: 28,
  tags: ['奇幻'],
  studio: '',
  poster: PosterPalette(
    primaryHex: 0xff222222,
    secondaryHex: 0xff333333,
    accentHex: 0xffffffff,
    motifIndex: 0,
  ),
);

const _item = {
  'id': 414461,
  'type': 2,
  'name': '葬送的フリーレン',
  'name_cn': '葬送的芙莉莲',
  'date': '2023-09-29',
  'rating': {'score': 8.8},
  'images': {'large': 'https://example.com/cover.jpg'},
  'tags': [
    {'name': '奇幻'},
  ],
};

class _FixtureAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.uri.path) {
      '/calendar' => [
        {
          'weekday': {'id': 5},
          'items': [_item],
        },
      ],
      '/v0/search/subjects' => {
        'data': [_item],
      },
      '/v0/subjects/414461' => {..._item, 'summary': '详情'},
      '/v0/subjects/414461/subjects' => [],
      '/v0/episodes' => {
        'total': 1,
        'data': [
          {'sort': 1, 'name': '第一话', 'airdate': '2023-09-29'},
        ],
      },
      _ => throw StateError('Unexpected request ${options.uri}'),
    };
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _EmptyVault implements SettingsVault {
  @override
  Future<SecretSettings> read() async => const SecretSettings();
  @override
  Future<void> write(SecretSettings settings) async {}
}

class _DirectSource implements PlaybackSources {
  @override
  Future<List<SourceEpisode>> lookup(
    AnimeSubject subject,
    String ruleId,
  ) async => const [];
  @override
  Future<PlayableMedia> resolve(SourceEpisode episode) async =>
      PlayableMedia(episode.page);
}
