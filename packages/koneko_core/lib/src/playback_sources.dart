import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html;
import 'package:koneko_contract/koneko_contract.dart';

import 'bangumi.dart';
import 'kazumi/modules/search/plugin_search_module.dart';
import 'kazumi/plugins/plugins.dart';
import 'rules.dart';

String _titleKey(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
  '',
);

class KazumiSources implements PlaybackSources {
  KazumiSources(this._rules, {Dio? client})
    : _client = client ?? networkClient();

  final KazumiRules _rules;
  final Dio _client;
  final _lookups = <(int, Plugin), Future<List<SourceEpisode>>>{};

  @override
  Future<List<SourceEpisode>> lookup(
    AnimeSubject subject,
    String ruleId,
  ) async {
    final rule = _rules.enabledPlugin(ruleId);
    if (rule == null) throw StateError('请先启用该规则');
    final key = (subject.subjectId, rule);
    if (_lookups.length > 48 && !_lookups.containsKey(key)) {
      _lookups.remove(_lookups.keys.first);
    }
    return _lookups.putIfAbsent(
      key,
      () => _lookup(subject, ruleId, rule).onError((
        Object error,
        StackTrace stack,
      ) {
        _lookups.remove(key);
        Error.throwWithStackTrace(error, stack);
      }),
    );
  }

  Future<List<SourceEpisode>> _lookup(
    AnimeSubject subject,
    String ruleId,
    Plugin rule,
  ) async {
    final names = {subject.title.trim(), subject.originalTitle.trim()}
      ..remove('');
    var results = const <SearchItem>[];
    for (final name in names) {
      try {
        results = (await rule.queryBangumi(name, shouldRethrow: true)).data;
        if (results.isNotEmpty) break;
      } on NoResultException {
        continue;
      } on CaptchaRequiredException {
        throw StateError('${rule.name} 要求人机验证，请选用其他可用规则');
      }
    }
    if (results.isEmpty) throw StateError('${rule.name} 未找到这部番剧');
    final targetKeys = names.map(_titleKey).toSet();
    final exact = results
        .where((result) => targetKeys.contains(_titleKey(result.name)))
        .firstOrNull;
    final match = exact ?? results.first;
    final roads = await rule.queryChapterRoads(match.src);
    final episodes = <SourceEpisode>[];
    for (final (lineIndex, road) in roads.indexed) {
      final line = road.name.trim().isNotEmpty
          ? road.name
          : '线路 ${lineIndex + 1}';
      for (final (i, url) in road.data.indexed) {
        final title = i < road.identifier.length ? road.identifier[i] : '';
        final page = Uri.tryParse(rule.buildFullUrl(url));
        if (page == null ||
            !{'https', 'http'}.contains(page.scheme) ||
            page.host.isEmpty ||
            page.userInfo.isNotEmpty) {
          continue;
        }
        final match = RegExp(
          r'^\s*(?:第|EP\s*)?\s*(\d{1,3})(?:\s*[话話集期]|\s*$)',
          caseSensitive: false,
        ).firstMatch(title);
        final number = int.tryParse(match?.group(1) ?? '') ?? i + 1;
        episodes.add(
          SourceEpisode(
            ruleId: ruleId,
            ruleName: rule.name,
            title: title.trim().isNotEmpty ? title : '第 $number 话',
            line: line,
            number: number,
            page: page,
            headers: rule.buildHttpHeaders(),
            legacy: rule.useLegacyParser,
          ),
        );
      }
    }
    if (episodes.isEmpty) throw StateError('${rule.name} 没有可用的正片地址');
    return episodes;
  }

  @override
  Future<PlayableMedia> resolve(SourceEpisode episode) async {
    final page = networkUri(episode.page.toString());
    final headers = <String, String>{
      'user-agent': _browserUserAgent,
      'referer': page.toString(),
      ...episode.headers,
    };
    if (_isMedia(page)) return PlayableMedia(page, headers: headers);
    if (episode.legacy) {
      final response = await _client.getUri<String>(
        page,
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
      final dom = html.parse(response.data);
      final content = dom
          .querySelector('video[src], video source[src], iframe[src]')
          ?.attributes['src'];
      if (content?.isNotEmpty == true) {
        final target = networkUri(page.resolve(content!).toString());
        if (_isMedia(target)) return PlayableMedia(target, headers: headers);
        return _sniff(target, headers);
      }
    }
    return _sniff(page, headers);
  }

  Future<PlayableMedia> _sniff(Uri page, Map<String, String> headers) async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      throw UnsupportedError('当前平台未接入视频嗅探');
    }
    final result = Completer<PlayableMedia>();
    Timer? probe;
    var probeBusy = false;
    void offer(Object? value) {
      if (result.isCompleted || value is! String) return;
      final uri = Uri.tryParse(value);
      if (uri == null || !_isMedia(uri)) return;
      result.complete(PlayableMedia(uri, headers: headers));
    }

    final webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(page.toString()),
        headers: headers,
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: headers['user-agent'],
        mediaPlaybackRequiresUserGesture: false,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        allowFileAccess: false,
        useOnLoadResource: true,
        useShouldInterceptRequest: true,
        useShouldOverrideUrlLoading: true,
      ),
      shouldOverrideUrlLoading: (_, action) async {
        final uri = action.request.url;
        return uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      shouldInterceptRequest: (_, request) async {
        offer(request.url.toString());
        return null;
      },
      onLoadResource: (_, resource) => offer(resource.url.toString()),
      onLoadStop: (controller, _) {
        probe ??= Timer.periodic(const Duration(milliseconds: 400), (_) async {
          if (probeBusy || result.isCompleted) return;
          probeBusy = true;
          try {
            final resources = await controller.evaluateJavascript(
              source: _scanMedia,
            );
            final values = resources is String
                ? _decodeMediaList(resources)
                : jsonList(resources);
            // Prefer a discovered manifest over assets such as short previews.
            for (final value in values.take(math.min(values.length, 300))) {
              offer(value);
              if (result.isCompleted) break;
            }
          } on Object {
            // A navigation can invalidate a pending evaluation.
          } finally {
            probeBusy = false;
          }
        });
      },
    );
    try {
      await webView.run().timeout(const Duration(seconds: 6));
      return await result.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw StateError('页面没有提供可播放的视频地址，请切换线路或规则'),
      );
    } finally {
      probe?.cancel();
      await webView.dispose();
    }
  }

  static bool _isMedia(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      RegExp(
        r'\.(m3u8|mpd|mp4|m4v|webm|mkv|flv|mov)(?:$|[;/])',
        caseSensitive: false,
      ).hasMatch(uri.path);

  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const _scanMedia = r'''
(() => {
  const urls = [...document.querySelectorAll('video, video source')]
    .flatMap(node => [node.currentSrc, node.src]).filter(Boolean);
  for (const resource of performance.getEntriesByType('resource')) {
    if (/\.(m3u8|mpd|mp4|webm|mkv|flv)([?#]|$)/i.test(resource.name)) {
      urls.push(resource.name);
    }
  }
  return JSON.stringify([...new Set(urls)]);
})()
''';
}

List<dynamic> _decodeMediaList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return jsonList(decoded is String ? jsonDecode(decoded) : decoded);
  } on FormatException {
    return const [];
  }
}
