import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html;
import 'package:koneko_contract/koneko_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bangumi.dart';
import 'kazumi/modules/search/plugin_search_module.dart';
import 'kazumi/plugins/plugins.dart';
import 'kazumi/services/plugin/rule_engine.dart';
import 'rules.dart';

String _titleKey(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
  '',
);

class KazumiSources implements PlaybackSources {
  KazumiSources(
    this._rules, {
    Dio? client,
    SharedPreferences? preferences,
  }) : _client = client ?? networkClient(),
       _preferences = preferences {
    _loadRememberedRules();
  }

  static const _lastRuleKey = 'koneko_last_selected_rules_v1';

  final KazumiRules _rules;
  final Dio _client;
  final SharedPreferences? _preferences;
  final _lookups = <(int, Plugin), Future<List<SourceEpisode>>>{};
  final _lastRules = <int, String>{};

  void _loadRememberedRules() {
    final raw = _preferences?.getString(_lastRuleKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonObject(jsonDecode(raw));
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key);
        final ruleId = jsonString(entry.value).trim();
        if (id != null && id > 0 && ruleId.isNotEmpty) {
          _lastRules[id] = ruleId;
        }
      }
    } on FormatException {
      // Ignore corrupt preference.
    }
  }

  @override
  String? lastSelectedRuleId(int subjectId) => _lastRules[subjectId];

  @override
  Future<void> rememberSelectedRule(int subjectId, String ruleId) async {
    final cleaned = ruleId.trim();
    if (subjectId <= 0 || cleaned.isEmpty) return;
    _lastRules[subjectId] = cleaned;
    final prefs = _preferences;
    if (prefs == null) return;
    final encoded = jsonEncode({
      for (final entry in _lastRules.entries) '${entry.key}': entry.value,
    });
    await prefs.setString(_lastRuleKey, encoded);
  }

  Uri? _buildVerifyUri(Plugin rule, String keyword) {
    final candidate = rule.usesApiSearch
        ? rule.baseUrl
        : rule.searchURL.replaceAll(
            '@keyword',
            Uri.encodeQueryComponent(keyword),
          );
    return Uri.tryParse(candidate.isNotEmpty ? candidate : rule.baseUrl);
  }

  @override
  Future<RuleProbeResult> probeRule(
    AnimeSubject subject,
    String ruleId, {
    String? keyword,
  }) async {
    final rule = _rules.enabledPlugin(ruleId);
    if (rule == null) {
      return RuleProbeResult(
        ruleId: ruleId,
        ruleName: ruleId,
        state: RuleProbeState.error,
        message: '该规则未启用',
      );
    }
    final custom = keyword?.trim() ?? '';
    final names = <String>{
      if (custom.isNotEmpty) custom,
      if (custom.isEmpty) subject.title.trim(),
      if (custom.isEmpty) subject.originalTitle.trim(),
    }..remove('');

    var sawCaptcha = false;
    Object? lastError;
    final primaryKeyword = names.isNotEmpty ? names.first : subject.title;

    for (final name in names) {
      try {
        final response = await rule.queryBangumi(name, shouldRethrow: true);
        if (response.data.isNotEmpty) {
          final targetKeys = names.map(_titleKey).toSet();
          final sorted = List<SearchItem>.from(response.data)
            ..sort((a, b) {
              final aExact = targetKeys.contains(_titleKey(a.name)) ? 0 : 1;
              final bExact = targetKeys.contains(_titleKey(b.name)) ? 0 : 1;
              return aExact.compareTo(bExact);
            });
          return RuleProbeResult(
            ruleId: ruleId,
            ruleName: rule.name,
            state: RuleProbeState.found,
            hits: [
              for (final item in sorted)
                RuleSearchHit(title: item.name, sourceUrl: item.src),
            ],
            message: '找到 ${sorted.length} 条结果',
          );
        }
      } on NoResultException {
        continue;
      } on CaptchaRequiredException {
        sawCaptcha = true;
        break;
      } on Object catch (error) {
        lastError = error;
      }
    }

    if (sawCaptcha) {
      return RuleProbeResult(
        ruleId: ruleId,
        ruleName: rule.name,
        state: RuleProbeState.captchaRequired,
        message: '该站点需要完成网页验证，点击进入网页验证后即可继续搜索',
        verifyUrl: _buildVerifyUri(rule, primaryKeyword),
      );
    }
    if (lastError != null) {
      return RuleProbeResult(
        ruleId: ruleId,
        ruleName: rule.name,
        state: RuleProbeState.error,
        message: '搜索请求失败，请检查网络或稍后重试',
      );
    }
    return RuleProbeResult(
      ruleId: ruleId,
      ruleName: rule.name,
      state: RuleProbeState.noResult,
      message: '未找到相关番剧',
    );
  }

  @override
  Future<List<SourceEpisode>> loadEpisodesFromHit(
    String ruleId,
    RuleSearchHit hit,
  ) async {
    final rule = _rules.enabledPlugin(ruleId);
    if (rule == null) throw StateError('请先启用该规则');
    return _episodesFromSource(ruleId, rule, hit.sourceUrl);
  }

  @override
  Future<void> saveVerificationCookies(
    String ruleId,
    Uri pageUrl,
    String cookieString, {
    String? userAgent,
  }) async {
    final rule = _rules.enabledPlugin(ruleId);
    final pluginName = rule?.name ?? ruleId;
    PluginCookieStore.instance.save(
      pluginName: pluginName,
      cookieString: cookieString,
      userAgent: userAgent,
    );
    // Clear cached lookup failures for this rule so subsequent searches retry fresh.
    _lookups.removeWhere((key, _) => key.$2.name == pluginName);
  }

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
    final probe = await probeRule(subject, ruleId);
    switch (probe.state) {
      case RuleProbeState.captchaRequired:
        throw StateError('${rule.name} 需要完成人机验证，请点此打开网页验证');
      case RuleProbeState.noResult:
        throw StateError('${rule.name} 未找到这部番剧');
      case RuleProbeState.error:
      case RuleProbeState.searching:
        throw StateError('${rule.name} ${probe.message}');
      case RuleProbeState.found:
        return _episodesFromSource(ruleId, rule, probe.hits.first.sourceUrl);
    }
  }

  Future<List<SourceEpisode>> _episodesFromSource(
    String ruleId,
    Plugin rule,
    String sourceUrl,
  ) async {
    final roads = await rule.queryChapterRoads(sourceUrl);
    final episodes = <SourceEpisode>[];
    final cookies = PluginCookieStore.instance.cookieHeaderFor(rule.name);
    final verifiedUa = PluginCookieStore.instance.userAgentFor(rule.name);

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
            headers: {
              ...rule.buildHttpHeaders(),
              'user-agent': ?verifiedUa,
              'cookie': ?cookies,
            },
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
    final cookies = PluginCookieStore.instance.cookieHeaderFor(
      episode.ruleName,
    );
    final verifiedUa = PluginCookieStore.instance.userAgentFor(
      episode.ruleName,
    );
    final headers = <String, String>{
      'user-agent': verifiedUa ?? _browserUserAgent,
      'referer': page.toString(),
      'cookie': ?cookies,
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
