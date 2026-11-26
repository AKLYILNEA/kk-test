import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, SystemUiMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/player/rule_verify_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/ui/koneko_comments.dart';
import 'package:koneko/ui/koneko_danmaku_sheet.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _PanelTab { episodes, sources, comments }

enum _DrawerTab { episodes, sources, danmaku }

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.subjectId,
    required this.initialEpisode,
    required this.initialRuleId,
    required this.initialRuleName,
    this.offline,
  });

  final int subjectId;
  final int initialEpisode;
  final String initialRuleId;
  final String initialRuleName;
  final OfflineEpisode? offline;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with RouteSettledMixin<PlayerPage>, WidgetsBindingObserver {
  static const _pageSize = 24;

  late int _episode = widget.initialEpisode;
  late String _ruleId = widget.initialRuleId;
  late String _ruleName = widget.initialRuleName;
  PlaybackSession? _session;
  PlaybackStatus _status = const PlaybackStatus();
  StreamSubscription<PlaybackStatus>? _subscription;
  Timer? _saveTimer;
  Timer? _brightnessTimer;
  Timer? _hudTimer;
  SourceEpisode? _source;
  List<SourceEpisode> _choices = const [];
  List<DanmakuItem> _danmaku = const [];
  final Map<String, RuleProbeResult> _probes = {};
  final TextEditingController _sourceKeywordController =
      TextEditingController();

  bool _loading = true;
  bool _loaded = false;
  bool _pageActive = true;
  bool _showHud = true;
  bool _showDanmaku = true;
  bool _fullscreen = false;
  bool _drawerOpen = false;
  bool _upscale = false;
  double _speed = 1;
  double _brightness = 1;
  double? _scrub;
  bool _changingBrightness = false;
  _PanelTab _panelTab = _PanelTab.episodes;
  _DrawerTab _drawer = _DrawerTab.episodes;
  int _epPageIndex = 0;
  String? _error;
  Uri? _errorVerifyUrl;
  String? _errorVerifyRuleId;
  String? _errorVerifyRuleName;
  String? _activeHitUrl;
  String? _loadingHint;
  String? _danmakuError;
  bool _danmakuLoading = false;
  int _request = 0;
  int _danmakuRequest = 0;
  int _probeGeneration = 0;
  int _lastCheckpoint = -1;
  bool _lastCompleted = false;

  AnimeSubject? get _subject =>
      ref.read(catalogRepositoryProvider).getSubjectById(widget.subjectId);

  bool get _isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didSettleRoute() => unawaited(_start());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = PageActivityScope.isActiveOf(context);
    if (_pageActive && !active) unawaited(_session?.setPlaying(false));
    _pageActive = active;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _checkpoint();
    }
  }

  @override
  void dispose() {
    if (_fullscreen) {
      unawaited(_restoreSystemUi());
    }
    WidgetsBinding.instance.removeObserver(this);
    _request++;
    _danmakuRequest++;
    _probeGeneration++;
    _saveTimer?.cancel();
    _brightnessTimer?.cancel();
    _hudTimer?.cancel();
    _sourceKeywordController.dispose();
    unawaited(_subscription?.cancel());
    unawaited(_session?.dispose());
    super.dispose();
  }

  void _armHudAutoHide() {
    _hudTimer?.cancel();
    if (!_showHud || !_status.playing || _drawerOpen) return;
    _hudTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _status.playing && !_drawerOpen) {
        setState(() => _showHud = false);
      }
    });
  }

  void _toggleHud() {
    setState(() {
      if (_drawerOpen) {
        _drawerOpen = false;
      } else {
        _showHud = !_showHud;
      }
    });
    if (_showHud) _armHudAutoHide();
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (_fullscreen == enabled) return;
    setState(() {
      _fullscreen = enabled;
      if (!enabled) _drawerOpen = false;
    });
    if (_isMobilePlatform) {
      if (enabled) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await _restoreSystemUi();
      }
    }
  }

  Future<void> _restoreSystemUi() async {
    if (!_isMobilePlatform) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _start() async {
    try {
      if (_session == null) {
        final factory = ref.read(playbackFactoryProvider);
        if (factory == null) throw StateError('播放器服务不可用');
        final session = factory();
        _subscription = session.changes.listen(_onStatus);
        setState(() => _session = session);
        _saveTimer ??= Timer.periodic(
          const Duration(seconds: 10),
          (_) => _checkpoint(),
        );
      }
      final offline = widget.offline;
      if (offline?.media case final uri?) {
        await _startOffline(uri);
      } else {
        // Resolve remembered rule before opening (from explicit arg, history, or store).
        final sources = ref.read(playbackSourcesProvider);
        final historyRule = ref
            .read(historyProvider.notifier)
            .entryFor(widget.subjectId)
            ?.lastRuleId;
        final remembered = _ruleId.isNotEmpty
            ? _ruleId
            : (sources?.lastSelectedRuleId(widget.subjectId) ??
                  historyRule ??
                  '');
        if (remembered.isNotEmpty) {
          _ruleId = remembered;
        }
        unawaited(_probeAllEnabledRules());
        await _openEpisode(
          _episode,
          strictPreferredRule: remembered.isNotEmpty,
          autoSelectFastest: remembered.isEmpty,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = featureError(error, '播放器初始化失败');
        _loading = false;
      });
    }
  }

  void _onStatus(PlaybackStatus status) {
    if (!mounted) return;
    final completed = status.completed && !_status.completed;
    final startedPlaying = status.playing && !_status.playing;
    setState(() => _status = status);
    if (completed) _checkpoint();
    if (startedPlaying) _armHudAutoHide();
  }

  bool _isCurrent(int request) => mounted && request == _request;

  Duration _resumeAt(int episode) {
    final history = ref
        .read(historyProvider.notifier)
        .positionFor(widget.subjectId, episode);
    if (history == null || history.isCompleted) return Duration.zero;
    return Duration(seconds: history.positionSeconds);
  }

  /// Probes ALL enabled rules in parallel so the user can see exact search hits
  /// for every source (aligned with Kazumi's SourceSheet).
  Future<void> _probeAllEnabledRules({String? customKeyword}) async {
    final resolver = ref.read(playbackSourcesProvider);
    if (resolver == null) return;
    var subject = _subject;
    if (subject == null) {
      await ref.read(onlineCatalogProvider)?.loadSubject(widget.subjectId);
      subject = _subject;
    }
    if (!mounted || subject == null) return;

    final enabledRules = ref
        .read(rulesProvider)
        .where((r) => r.enabled)
        .toList();
    if (enabledRules.isEmpty) return;

    final gen = ++_probeGeneration;
    setState(() {
      for (final rule in enabledRules) {
        _probes[rule.id] = RuleProbeResult(
          ruleId: rule.id,
          ruleName: rule.name,
          state: RuleProbeState.searching,
          message: '正在搜索...',
        );
      }
    });

    final targetSubject = subject;
    await Future.wait(
      enabledRules.map((rule) async {
        final result = await resolver.probeRule(
          targetSubject,
          rule.id,
          keyword: customKeyword,
        );
        if (!mounted || gen != _probeGeneration) return;
        setState(() => _probes[rule.id] = result);
      }),
    );
  }

  Future<void> _verifyRule(String ruleId, String ruleName, Uri verifyUrl) async {
    if (_fullscreen) {
      await _setFullscreen(false);
    }
    if (!mounted) return;
    final verified = await showRuleVerifySheet(
      context: context,
      ruleId: ruleId,
      ruleName: ruleName,
      verifyUrl: verifyUrl,
    );
    if (!mounted || verified != true) return;
    showKonekoBanner(
      context,
      '$ruleName 验证已保存，正在重新搜索',
      level: BannerLevel.success,
    );
    final resolver = ref.read(playbackSourcesProvider);
    final subject = _subject;
    if (resolver != null && subject != null) {
      setState(() {
        _probes[ruleId] = RuleProbeResult(
          ruleId: ruleId,
          ruleName: ruleName,
          state: RuleProbeState.searching,
          message: '验证通过，重新搜索中...',
        );
      });
      final result = await resolver.probeRule(
        subject,
        ruleId,
        keyword: _sourceKeywordController.text.trim().isEmpty
            ? null
            : _sourceKeywordController.text.trim(),
      );
      if (mounted) {
        setState(() => _probes[ruleId] = result);
        if (result.state == RuleProbeState.found) {
          await _openEpisode(_episode, ruleId: ruleId);
        }
      }
    }
  }

  static String _normTitle(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

  Future<void> _openHit(String ruleId, String ruleName, RuleSearchHit hit) async {
    final session = _session;
    final resolver = ref.read(playbackSourcesProvider);
    if (session == null || resolver == null) return;
    _checkpoint();
    final request = ++_request;
    setState(() {
      _loading = true;
      _loadingHint = '正在加载 $ruleName...';
      _loaded = false;
      _error = null;
      _errorVerifyUrl = null;
      _errorVerifyRuleId = null;
      _errorVerifyRuleName = null;
      _ruleId = ruleId;
      _ruleName = ruleName;
      _activeHitUrl = hit.sourceUrl;
    });
    try {
      await session.setPlaying(false);
      final options = await resolver.loadEpisodesFromHit(ruleId, hit);
      if (!_isCurrent(request)) return;
      final available = options.where((e) => e.number == _episode).toList();
      final targetLines = available.isNotEmpty ? available : [options.first];
      setState(() {
        _choices = options;
        _episode = targetLines.first.number;
      });
      Object? lastErr;
      for (final episodeSource in targetLines) {
        if (!_isCurrent(request)) return;
        try {
          final media = await resolver.resolve(episodeSource);
          if (!_isCurrent(request)) return;
          await session.open(media, startAt: _resumeAt(episodeSource.number));
          if (!_isCurrent(request)) return;
          if (!_pageActive) await session.setPlaying(false);
          if (!_isCurrent(request)) return;
          await resolver.rememberSelectedRule(widget.subjectId, ruleId);
          setState(() {
            _source = episodeSource;
            _ruleId = episodeSource.ruleId;
            _ruleName = episodeSource.ruleName;
            _status = session.status;
            _loading = false;
            _loadingHint = null;
            _loaded = true;
            _lastCheckpoint = -1;
            _lastCompleted = false;
          });
          _armHudAutoHide();
          unawaited(_loadDanmaku());
          return;
        } on Object catch (err) {
          lastErr = err;
        }
      }
      throw lastErr ?? StateError('该结果暂无可用线路');
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _loadingHint = null;
        _error = featureError(error, '加载失败');
      });
    }
  }

  Future<void> _startOffline(Uri uri) async {
    final request = ++_request;
    final session = _session!;
    setState(() {
      _loading = true;
      _error = null;
      _errorVerifyUrl = null;
    });
    try {
      await session.open(PlayableMedia(uri), startAt: _resumeAt(_episode));
      if (!_isCurrent(request)) return;
      if (!_pageActive) await session.setPlaying(false);
      if (!_isCurrent(request)) return;
      setState(() {
        _loaded = true;
        _loading = false;
      });
      _armHudAutoHide();
      unawaited(_loadDanmaku());
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _error = featureError(error, '离线文件播放失败');
      });
    }
  }

  Future<void> _openEpisode(
    int episode, {
    String? ruleId,
    SourceEpisode? choice,
    bool strictPreferredRule = false,
    bool autoSelectFastest = false,
    String? excludeRuleId,
  }) async {
    final session = _session;
    if (session == null) return;
    _checkpoint();
    final initialPosition = episode == _episode && _loaded
        ? _status.position
        : _resumeAt(episode);
    final request = ++_request;
    ++_danmakuRequest;
    setState(() {
      _episode = episode;
      _loaded = false;
      _loading = true;
      _loadingHint = autoSelectFastest ? '正在优选可用播放源...' : null;
      _error = null;
      _errorVerifyUrl = null;
      _errorVerifyRuleId = null;
      _errorVerifyRuleName = null;
      _scrub = null;
      _danmaku = const [];
      _danmakuError = null;
    });
    try {
      await session.setPlaying(false);
      final resolver = ref.read(playbackSourcesProvider);
      if (resolver == null) throw StateError('播放服务不可用');
      var subject = _subject;
      if (subject == null) {
        await ref.read(onlineCatalogProvider)?.loadSubject(widget.subjectId);
        if (!_isCurrent(request)) return;
        subject = _subject;
      }
      if (subject == null) throw StateError('番剧资料加载失败');

      final rules = ref
          .read(rulesProvider)
          .where((rule) => rule.enabled)
          .toList();
      if (rules.isEmpty) throw StateError('请先添加播放规则');

      // Smart auto-selection for unwatched anime or when user taps "自动选择":
      // races all enabled rules in parallel, ranks by speed + title match, and
      // verifies the resolved stream is actually reachable & playable.
      if (autoSelectFastest) {
        await _autoSelectFastestPlayable(
          request: request,
          episode: episode,
          initialPosition: initialPosition,
          subject: subject,
          rules: rules,
          resolver: resolver,
          session: session,
          excludeRuleId: excludeRuleId,
        );
        return;
      }

      // If remembered/preferred rule was removed or disabled, immediately
      // surface the 3 choices (重试 / 自动选择 / 手动切换源).
      if (strictPreferredRule &&
          ruleId == null &&
          _ruleId.isNotEmpty &&
          !rules.any((r) => r.id == _ruleId)) {
        final missingName = _ruleName.isNotEmpty ? _ruleName : _ruleId;
        throw StateError('上次使用的「$missingName」已不可用');
      }

      final hasPreferred =
          ruleId != null || (strictPreferredRule && _ruleId.isNotEmpty);
      final ids = ruleId != null
          ? [ruleId]
          : hasPreferred
          ? [_ruleId]
          : [for (final r in rules) r.id];

      Object? problem;
      RuleProbeResult? captchaProbe;

      for (final id in ids) {
        if (!_isCurrent(request)) return;
        final ruleMeta = rules.where((r) => r.id == id).firstOrNull;
        if (mounted) {
          setState(
            () => _loadingHint = '正在加载 ${ruleMeta?.name ?? id}...',
          );
        }
        try {
          final existingProbe = _probes[id];
          if (existingProbe?.state == RuleProbeState.captchaRequired) {
            captchaProbe = existingProbe;
            if (hasPreferred) break;
            continue;
          }

          final options = await resolver.lookup(subject, id);
          if (!_isCurrent(request)) return;
          final available = options
              .where((item) => item.number == episode)
              .toList();
          if (available.isEmpty) throw StateError('暂无第 $episode 话');
          setState(() {
            _choices = options;
            _ruleId = id;
            _ruleName = options.first.ruleName;
          });
          final currentLine = _source?.line;
          final orderedLines = choice != null
              ? [choice]
              : [
                  ...available.where((item) => item.line == currentLine),
                  ...available.where((item) => item.line != currentLine),
                ];

          Object? lineProblem;
          for (final episodeSource in orderedLines) {
            if (!_isCurrent(request)) return;
            try {
              final media = await resolver.resolve(episodeSource);
              if (!_isCurrent(request)) return;
              await session.open(media, startAt: initialPosition);
              if (!_isCurrent(request)) return;
              if (!_pageActive) await session.setPlaying(false);
              if (!_isCurrent(request)) return;
              await resolver.rememberSelectedRule(widget.subjectId, id);
              setState(() {
                _episode = episode;
                _source = episodeSource;
                _ruleId = episodeSource.ruleId;
                _ruleName = episodeSource.ruleName;
                _status = session.status;
                _loading = false;
                _loadingHint = null;
                _loaded = true;
                _lastCheckpoint = -1;
                _lastCompleted = false;
              });
              _armHudAutoHide();
              unawaited(_loadDanmaku());
              return;
            } on Object catch (err) {
              lineProblem = err;
            }
          }
          throw lineProblem ?? StateError('线路不可用');
        } on Object catch (error) {
          problem = error;
          final probe = _probes[id];
          if (probe?.state == RuleProbeState.captchaRequired) {
            captchaProbe = probe;
          }
        }
      }

      if (captchaProbe != null && captchaProbe.verifyUrl != null) {
        if (!_isCurrent(request)) return;
        setState(() {
          _loading = false;
          _loadingHint = null;
          _error = '${captchaProbe!.ruleName} 需要验证';
          _errorVerifyUrl = captchaProbe.verifyUrl;
          _errorVerifyRuleId = captchaProbe.ruleId;
          _errorVerifyRuleName = captchaProbe.ruleName;
        });
        return;
      }

      if (hasPreferred) {
        final preferredName =
            rules.where((r) => r.id == ids.first).firstOrNull?.name ??
            (_ruleName.isNotEmpty ? _ruleName : ids.first);
        throw StateError('「$preferredName」暂时不可用');
      }
      throw problem ?? StateError('暂无可用播放源');
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _loadingHint = null;
        _error = featureError(error, '无法播放');
      });
    }
  }

  Future<void> _autoSelectFastestPlayable({
    required int request,
    required int episode,
    required Duration initialPosition,
    required AnimeSubject subject,
    required List<RulePluginMeta> rules,
    required PlaybackSources resolver,
    required PlaybackSession session,
    String? excludeRuleId,
  }) async {
    final candidates = rules
        .where((r) => excludeRuleId == null || r.id != excludeRuleId)
        .toList();
    final targetRules = candidates.isNotEmpty ? candidates : rules;

    // Step 1: Race parallel probes across candidate rules with an early-exit
    // window so fast sources win immediately without waiting on dead rules.
    final foundPool = <String, RuleProbeResult>{};
    RuleProbeResult? firstCaptcha;
    final probeReady = Completer<void>();
    Timer? graceTimer;
    var finishedCount = 0;

    void maybeFinishRace() {
      if (probeReady.isCompleted) return;
      if (finishedCount >= targetRules.length || foundPool.length >= 3) {
        graceTimer?.cancel();
        probeReady.complete();
      } else if (foundPool.isNotEmpty && graceTimer == null) {
        graceTimer = Timer(const Duration(milliseconds: 700), () {
          if (!probeReady.isCompleted) probeReady.complete();
        });
      }
    }

    for (final rule in targetRules) {
      final cached = _probes[rule.id];
      if (cached != null && cached.state != RuleProbeState.searching) {
        finishedCount++;
        if (cached.state == RuleProbeState.found && cached.hits.isNotEmpty) {
          foundPool[rule.id] = cached;
        } else if (cached.state == RuleProbeState.captchaRequired &&
            firstCaptcha == null) {
          firstCaptcha = cached;
        }
        continue;
      }
      unawaited(() async {
        final result = await resolver.probeRule(subject, rule.id);
        if (mounted) {
          setState(() => _probes[rule.id] = result);
        }
        finishedCount++;
        if (result.state == RuleProbeState.found && result.hits.isNotEmpty) {
          foundPool[rule.id] = result;
        } else if (result.state == RuleProbeState.captchaRequired &&
            firstCaptcha == null) {
          firstCaptcha = result;
        }
        maybeFinishRace();
      }());
    }
    maybeFinishRace();

    if (!probeReady.isCompleted) {
      await probeReady.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    }
    graceTimer?.cancel();
    if (!_isCurrent(request)) return;

    // Step 2: Sort found candidates by exact title match + connection speed.
    final titleKeys = {
      _normTitle(subject.title),
      if (subject.originalTitle.trim().isNotEmpty)
        _normTitle(subject.originalTitle),
    }..remove('');
    final ruleMetaById = {for (final r in targetRules) r.id: r};

    List<RuleProbeResult> rankCandidates(Iterable<RuleProbeResult> items) {
      final list = items.toList();
      list.sort((a, b) {
        final aExact = titleKeys.contains(_normTitle(a.hits.first.title))
            ? 0
            : 1;
        final bExact = titleKeys.contains(_normTitle(b.hits.first.title))
            ? 0
            : 1;
        if (aExact != bExact) return aExact.compareTo(bExact);
        final aMs = a.latencyMs > 0
            ? a.latencyMs
            : (ruleMetaById[a.ruleId]?.latencyMs ?? 0) > 0
            ? ruleMetaById[a.ruleId]!.latencyMs
            : 9999;
        final bMs = b.latencyMs > 0
            ? b.latencyMs
            : (ruleMetaById[b.ruleId]?.latencyMs ?? 0) > 0
            ? ruleMetaById[b.ruleId]!.latencyMs
            : 9999;
        return aMs.compareTo(bMs);
      });
      return list;
    }

    ({
      List<SourceEpisode> options,
      SourceEpisode episodeSource,
      PlayableMedia media,
      String hitUrl,
    })?
    fallbackCandidate;

    final triedIds = <String>{};

    Future<bool> tryProbe(RuleProbeResult probe) async {
      if (!_isCurrent(request) || !triedIds.add(probe.ruleId)) return false;
      final bestHit = probe.hits.first;
      if (mounted) {
        setState(() => _loadingHint = '正在测速 ${probe.ruleName}...');
      }
      try {
        final options = await resolver.loadEpisodesFromHit(
          probe.ruleId,
          bestHit,
        );
        if (!_isCurrent(request)) return false;
        final available = options
            .where((item) => item.number == episode)
            .toList();
        if (available.isEmpty) return false;

        for (final line in available) {
          if (!_isCurrent(request)) return false;
          try {
            final media = await resolver.resolve(line);
            if (!_isCurrent(request)) return false;
            final ttfb = await resolver.verifyPlayable(media);
            if (!_isCurrent(request)) return false;
            if (ttfb == null) {
              fallbackCandidate ??= (
                options: options,
                episodeSource: line,
                media: media,
                hitUrl: bestHit.sourceUrl,
              );
              continue;
            }
            setState(() {
              _choices = options;
              _ruleId = probe.ruleId;
              _ruleName = probe.ruleName;
              _activeHitUrl = bestHit.sourceUrl;
            });
            await session.open(media, startAt: initialPosition);
            if (!_isCurrent(request)) return false;
            if (!_pageActive) await session.setPlaying(false);
            if (!_isCurrent(request)) return false;
            await resolver.rememberSelectedRule(widget.subjectId, probe.ruleId);
            setState(() {
              _episode = episode;
              _source = line;
              _ruleId = line.ruleId;
              _ruleName = line.ruleName;
              _status = session.status;
              _loading = false;
              _loadingHint = null;
              _loaded = true;
              _lastCheckpoint = -1;
              _lastCompleted = false;
            });
            _armHudAutoHide();
            unawaited(_loadDanmaku());
            return true;
          } on Object {
            continue;
          }
        }
      } on Object {
        return false;
      }
      return false;
    }

    // Try ranked fast candidates first.
    for (final probe in rankCandidates(foundPool.values)) {
      if (await tryProbe(probe)) return;
      if (!_isCurrent(request)) return;
    }

    // Also try any late-arriving found probes that completed while we tested.
    final lateFound = _probes.values
        .where(
          (p) =>
              p.state == RuleProbeState.found &&
              p.hits.isNotEmpty &&
              !triedIds.contains(p.ruleId) &&
              (excludeRuleId == null || p.ruleId != excludeRuleId),
        )
        .toList();
    for (final probe in rankCandidates(lateFound)) {
      if (await tryProbe(probe)) return;
      if (!_isCurrent(request)) return;
    }

    // Fallback to the first resolved stream if all strict HTTP pre-checks
    // failed (e.g. a CDN that blocks Range requests but plays fine in mpv).
    if (fallbackCandidate case final fb?) {
      if (!_isCurrent(request)) return;
      setState(() {
        _choices = fb.options;
        _ruleId = fb.episodeSource.ruleId;
        _ruleName = fb.episodeSource.ruleName;
        _activeHitUrl = fb.hitUrl;
      });
      await session.open(fb.media, startAt: initialPosition);
      if (!_isCurrent(request)) return;
      if (!_pageActive) await session.setPlaying(false);
      if (!_isCurrent(request)) return;
      await resolver.rememberSelectedRule(
        widget.subjectId,
        fb.episodeSource.ruleId,
      );
      setState(() {
        _episode = episode;
        _source = fb.episodeSource;
        _ruleId = fb.episodeSource.ruleId;
        _ruleName = fb.episodeSource.ruleName;
        _status = session.status;
        _loading = false;
        _loadingHint = null;
        _loaded = true;
        _lastCheckpoint = -1;
        _lastCompleted = false;
      });
      _armHudAutoHide();
      unawaited(_loadDanmaku());
      return;
    }

    final captcha = firstCaptcha;
    if (captcha != null && captcha.verifyUrl != null) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _loadingHint = null;
        _error = '${captcha.ruleName} 需要验证';
        _errorVerifyUrl = captcha.verifyUrl;
        _errorVerifyRuleId = captcha.ruleId;
        _errorVerifyRuleName = captcha.ruleName;
      });
      return;
    }

    throw StateError('未找到可播放的源');
  }

  void _checkpoint() {
    if (!_loaded) return;
    final position = _status.position.inSeconds;
    final total = _status.duration.inSeconds;
    if (total <= 0 || position <= 0 || _ruleId.isEmpty) return;
    final complete = _status.completed || position / total >= 0.94;
    if (position == _lastCheckpoint && complete == _lastCompleted) return;
    _lastCheckpoint = position;
    _lastCompleted = complete;
    ref
        .read(historyProvider.notifier)
        .recordProgress(
          subjectId: widget.subjectId,
          episodeNumber: _episode,
          positionSeconds: position,
          durationSeconds: total,
          ruleId: _ruleId,
          ruleName: _ruleName,
          completed: complete,
        );
    if (complete) {
      ref
          .read(libraryProvider.notifier)
          .markEpisodeWatched(
            widget.subjectId,
            _episode,
            _subject?.totalEpisodes ?? 0,
          );
    }
  }

  String _danmakuSummary() {
    var bili = 0;
    var gamer = 0;
    var other = 0;
    for (final item in _danmaku) {
      final s = item.source.toLowerCase();
      if (s.contains('bilibili')) {
        bili++;
      } else if (s.contains('gamer') || s.contains('bahamut')) {
        gamer++;
      } else {
        other++;
      }
    }
    final parts = <String>[
      if (bili > 0) 'B站 $bili',
      if (gamer > 0) '巴哈 $gamer',
      if (other > 0) '弹弹 $other',
    ];
    return parts.isEmpty
        ? '已加载 ${_danmaku.length} 条弹幕'
        : '共 ${_danmaku.length} 条 · ${parts.join(' / ')}';
  }

  Future<void> _loadDanmaku({int? overrideEpisodeId}) async {
    final token = ++_danmakuRequest;
    if (!_showDanmaku) return;
    final subject = _subject;
    final source = ref.read(danmakuProvider);
    if (source == null || (subject == null && overrideEpisodeId == null)) {
      return;
    }
    setState(() {
      _danmakuLoading = true;
      _danmakuError = null;
    });
    try {
      final items = overrideEpisodeId != null
          ? await source.loadByEpisodeId(overrideEpisodeId)
          : await source.load(subject!, _episode);
      if (mounted && token == _danmakuRequest) {
        setState(() {
          _danmaku = items;
          _danmakuLoading = false;
          _danmakuError = items.isEmpty ? '当前话暂未匹配到弹幕，可点击下方手动匹配' : null;
        });
      }
    } on Object catch (error) {
      if (mounted && token == _danmakuRequest) {
        setState(() {
          _danmakuLoading = false;
          _danmakuError = featureError(error, '弹幕加载失败，请重试或手动匹配');
        });
      }
    }
  }

  Future<void> _openDanmakuSearchSheet() async {
    final source = ref.read(danmakuProvider);
    if (source == null) return;
    final searchController = TextEditingController(
      text: _subject?.title ?? '',
    );
    List<DanmakuAnimeMatch> matches = const [];
    DanmakuAnimeMatch? selectedAnime;
    bool searching = false;
    String? error;

    await showKonekoSheet<void>(
      context: context,
      title: '手动匹配弹幕',
      subtitle: '搜索弹弹Play 番剧并选择对应集数',
      detents: const [0.72, 0.92],
      bodyBuilder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = sheetContext.colorScheme;
            Future<void> doSearch() async {
              final q = searchController.text.trim();
              if (q.isEmpty) return;
              setSheetState(() {
                searching = true;
                error = null;
                selectedAnime = null;
              });
              try {
                final res = await source.searchAnimes(q);
                setSheetState(() {
                  matches = res;
                  searching = false;
                  if (res.isEmpty) error = '未找到匹配的弹幕番剧';
                });
              } on Object {
                setSheetState(() {
                  searching = false;
                  error = '弹幕库搜索失败，请检查网络';
                });
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            hintText: '输入番剧名称搜索弹幕...',
                          ),
                          onSubmitted: (_) => unawaited(doSearch()),
                        ),
                      ),
                      FilledButton(
                        onPressed: searching ? null : () => unawaited(doSearch()),
                        child: const Text('搜索'),
                      ),
                    ],
                  ),
                ),
                if (selectedAnime != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        KonekoChip(
                          label: '← 返回番剧列表',
                          height: 28,
                          fontSize: 12,
                          onPressed: () =>
                              setSheetState(() => selectedAnime = null),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedAnime!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.footnote
                                .of(sheetContext, emphasized: true)
                                .copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: searching
                      ? const Center(child: ActivityIndicator())
                      : error != null
                      ? Center(child: Text(error!))
                      : selectedAnime != null
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            KonekoGroup(
                              items: [
                                for (final ep in selectedAnime!.episodes)
                                  DecorationListItem(
                                    title: Text(ep.title),
                                    subtitle: Text('第 ${ep.episodeNumber} 话'),
                                    trailing: const GlyphIcon(
                                      Glyphs.chevronForward,
                                    ),
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      setState(() => _showDanmaku = true);
                                      unawaited(
                                        _loadDanmaku(
                                          overrideEpisodeId: ep.episodeId,
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        )
                      : matches.isEmpty
                      ? Center(
                          child: Text(
                            '点击「搜索」从弹弹Play 匹配对应番剧',
                            style: AppTextStyle.footnote
                                .of(sheetContext)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            KonekoGroup(
                              items: [
                                for (final anime in matches)
                                  DecorationListItem(
                                    title: Text(anime.title),
                                    subtitle: Text(
                                      '${anime.typeDescription.isNotEmpty ? '${anime.typeDescription} · ' : ''}共 ${anime.episodes.length} 集',
                                    ),
                                    trailing: const GlyphIcon(
                                      Glyphs.chevronForward,
                                    ),
                                    onPressed: () => setSheetState(
                                      () => selectedAnime = anime,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
  }

  Future<void> _setUpscale(bool enabled) async {
    final session = _session;
    if (session == null) return;
    try {
      await session.setUpscaling(enabled);
      if (mounted) setState(() => _upscale = enabled);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '当前设备无法启用超分'),
          level: BannerLevel.error,
        );
      }
    }
  }

  Future<void> _download() async {
    final source = _source;
    final subject = _subject;
    final library = ref.read(offlineLibraryProvider);
    if (source == null || subject == null || library == null) return;
    showKonekoBanner(context, '正在准备缓存第 $_episode 话');
    try {
      await library.download(subject, source);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '未能创建下载任务'),
          level: BannerLevel.error,
        );
      }
    }
  }

  Future<void> _pickCollectionStatus(
    String title,
    CollectionStatus? currentStatus,
  ) async {
    final choice = await showKonekoStatusSheet(
      context: context,
      subjectTitle: title,
      currentStatus: currentStatus,
    );
    if (!mounted || choice == null) return;
    if (choice.remove) {
      ref.read(libraryProvider.notifier).removeSubject(widget.subjectId);
      showKonekoBanner(context, '已移出追番列表');
    } else if (choice.status case final status?) {
      ref.read(libraryProvider.notifier).setStatus(widget.subjectId, status);
      showKonekoBanner(
        context,
        '已标记为「${status.label}」',
        level: BannerLevel.success,
      );
    }
  }

  void _adjustBrightness(double delta) {
    setState(() {
      _brightness = (_brightness + delta).clamp(.15, 1);
      _changingBrightness = true;
    });
    _brightnessTimer?.cancel();
    _brightnessTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => _changingBrightness = false);
    });
  }

  void _switchToSources() {
    if (_fullscreen) {
      setState(() {
        _drawer = _DrawerTab.sources;
        _drawerOpen = true;
      });
    } else {
      setState(() => _panelTab = _PanelTab.sources);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogUpdatesProvider);
    ref.watch(loadCatalogSubjectProvider(widget.subjectId));
    final catalog = ref.watch(catalogRepositoryProvider);
    final subject = _subject;
    final title = subject?.title ?? widget.offline?.subjectTitle ?? 'Koneko';
    final rules = ref.watch(rulesProvider);
    final library = ref.watch(libraryProvider);
    final collection = library
        .where((e) => e.subjectId == widget.subjectId)
        .firstOrNull;
    final session = _session;
    final viewport = ref.watch(videoViewportProvider);
    final overlay = ref.watch(danmakuViewportProvider);
    final danmakuSettings = ref.watch(danmakuSettingsProvider);
    final status = _status;
    final error =
        _error ??
        (_loaded && status.duration == Duration.zero && status.error != null
            ? '播放失败'
            : null);
    final offline = widget.offline != null;

    final videoStage = _buildVideoStage(
      context: context,
      subject: subject,
      title: title,
      rules: rules,
      session: session,
      viewport: viewport,
      overlay: overlay,
      danmakuSettings: danmakuSettings,
      status: status,
      error: error,
      offline: offline,
    );

    return PopScope<void>(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) {
          unawaited(_setFullscreen(false));
          return;
        }
        if (didPop) _checkpoint();
      },
      child: _fullscreen
          ? ColoredBox(color: Colors.black, child: videoStage)
          : LayoutBuilder(
              builder: (context, constraints) {
                final colorScheme = context.colorScheme;
                final pageBg = SurfaceLevel.page.colorOf(colorScheme);
                final safe = MediaQuery.paddingOf(context);
                final isWide = constraints.maxWidth >= 840;

                final panel = _buildSideOrBottomPanel(
                  context: context,
                  catalog: catalog,
                  title: title,
                  collection: collection,
                  rules: rules,
                  offline: offline,
                  bottomPadding: safe.bottom + 20,
                );

                if (isWide) {
                  return SurfaceScope(
                    level: SurfaceLevel.page,
                    child: ColoredBox(
                      color: pageBg,
                      child: Row(
                        children: [
                          Expanded(
                            child: ColoredBox(
                              color: Colors.black,
                              child: SafeArea(right: false, child: videoStage),
                            ),
                          ),
                          Container(
                            width: 1,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.25,
                            ),
                          ),
                          SizedBox(
                            width: math.min(400, constraints.maxWidth * 0.36),
                            child: SafeArea(
                              left: false,
                              bottom: false,
                              child: panel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Portrait split layout: crisp 16:9 video on top, tabs below.
                return SurfaceScope(
                  level: SurfaceLevel.page,
                  child: ColoredBox(
                    color: pageBg,
                    child: Column(
                      children: [
                        ColoredBox(
                          color: Colors.black,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: safe.top),
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: videoStage,
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: panel),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildVideoStage({
    required BuildContext context,
    required AnimeSubject? subject,
    required String title,
    required List<RulePluginMeta> rules,
    required PlaybackSession? session,
    required Widget Function(PlaybackSession)? viewport,
    required Widget Function(List<DanmakuItem>, PlaybackStatus, DanmakuSettings)?
    overlay,
    required DanmakuSettings danmakuSettings,
    required PlaybackStatus status,
    required String? error,
    required bool offline,
  }) {
    final safe = _fullscreen ? MediaQuery.paddingOf(context) : EdgeInsets.zero;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleHud,
          onDoubleTap: !_loaded
              ? null
              : () => session?.setPlaying(!status.playing),
          onVerticalDragUpdate: (event) =>
              _adjustBrightness(-event.delta.dy * .004),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (session != null && viewport != null)
                IgnorePointer(child: viewport(session))
              else if (subject != null)
                Opacity(opacity: .35, child: KonekoPosterArt(subject: subject)),
              if (_brightness < 1)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 1 - _brightness),
                  ),
                ),
              if (_showDanmaku && _danmaku.isNotEmpty && overlay != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: overlay(_danmaku, status, danmakuSettings),
                  ),
                ),
            ],
          ),
        ),
        if (_loading || (_loaded && status.buffering))
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                const ActivityIndicator(color: Colors.white),
                if (_loading && (_loadingHint?.isNotEmpty ?? false))
                  _GlassPill(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      _loadingHint!,
                      style: _style(context, small: true),
                    ),
                  ),
              ],
            ),
          ),
        if (error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GlassPill(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _style(context, small: !_fullscreen),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_errorVerifyUrl != null &&
                            _errorVerifyRuleId != null)
                          _HudAction(
                            label: '去验证',
                            active: true,
                            onTap: () => _verifyRule(
                              _errorVerifyRuleId!,
                              _errorVerifyRuleName ?? _errorVerifyRuleId!,
                              _errorVerifyUrl!,
                            ),
                          ),
                        _HudAction(
                          label: '重试',
                          onTap: () => _openEpisode(
                            _episode,
                            ruleId: _ruleId.isEmpty ? null : _ruleId,
                            strictPreferredRule: _ruleId.isNotEmpty,
                            autoSelectFastest: _ruleId.isEmpty,
                          ),
                        ),
                        if (!offline && rules.any((rule) => rule.enabled))
                          _HudAction(
                            label: '自动选择',
                            active: _errorVerifyUrl == null,
                            onTap: () => _openEpisode(
                              _episode,
                              autoSelectFastest: true,
                              excludeRuleId: _ruleId.isEmpty ? null : _ruleId,
                            ),
                          ),
                        if (!offline)
                          _HudAction(
                            label: rules.any((rule) => rule.enabled)
                                ? '手动切换源'
                                : '添加规则',
                            onTap: () async {
                              if (rules.any((rule) => rule.enabled)) {
                                _switchToSources();
                              } else {
                                await BaseNavigator.push<void>(
                                  context,
                                  const RulesPage(showBack: true),
                                );
                                if (mounted) await _start();
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_changingBrightness)
          Positioned(
            top: safe.top + (_fullscreen ? 64 : 40),
            left: 16,
            right: 16,
            child: Center(
              child: _GlassPill(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Text(
                  '亮度 ${(_brightness * 100).round()}%',
                  style: _style(context, small: true),
                ),
              ),
            ),
          ),
        // Top HUD bar — ultra-slim gradient scrim in compact portrait mode
        if (_showHud)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                safe.left + (_fullscreen ? 12 : 4),
                safe.top + (_fullscreen ? 8 : 2),
                safe.right + (_fullscreen ? 12 : 4),
                _fullscreen ? 14 : 10,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                spacing: 2,
                children: [
                  _bareIcon(
                    glyph: Glyphs.backFor(Theme.of(context).platform),
                    tooltip: _fullscreen ? '退出全屏' : '返回',
                    onPressed: () {
                      if (_fullscreen) {
                        unawaited(_setFullscreen(false));
                      } else {
                        Navigator.of(context).maybePop();
                      }
                    },
                  ),
                  Expanded(
                    child: Text(
                      '$title · 第 $_episode 话',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(context, small: !_fullscreen),
                    ),
                  ),
                  _bareIcon(
                    glyph: KonekoGlyphs.danmaku,
                    tooltip: _showDanmaku ? '关闭弹幕' : '开启弹幕',
                    active: _showDanmaku,
                    onPressed: () {
                      setState(() => _showDanmaku = !_showDanmaku);
                      if (_showDanmaku) unawaited(_loadDanmaku());
                      _armHudAutoHide();
                    },
                  ),
                  if (_fullscreen)
                    _bareIcon(
                      glyph: KonekoGlyphs.layers,
                      tooltip: '选集与播放源',
                      onPressed: () =>
                          setState(() => _drawerOpen = !_drawerOpen),
                    ),
                ],
              ),
            ),
          ),
        // Bottom HUD bar — single compact slim row in portrait, rich bar in fullscreen
        if (_showHud)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _controls(context, status, session, offline, safe),
          ),
        if (_fullscreen)
          AnimatedPositioned(
            duration: context.motionDuration(
              const Duration(milliseconds: 230),
            ),
            curve: Curves.easeOutCubic,
            top: safe.top + 12,
            bottom: safe.bottom + 12,
            right: _drawerOpen ? safe.right + 12 : -360,
            width: math.min(330, MediaQuery.sizeOf(context).width - 24),
            child: ExcludeFocus(
              excluding: !_drawerOpen,
              child: IgnorePointer(
                ignoring: !_drawerOpen,
                child: _buildDrawer(context, rules, offline),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSideOrBottomPanel({
    required BuildContext context,
    required CatalogRepository catalog,
    required String title,
    required CollectionEntry? collection,
    required List<RulePluginMeta> rules,
    required bool offline,
    required double bottomPadding,
  }) {
    final colorScheme = context.colorScheme;
    final commentsCount =
        ref.watch(subjectCommentsProvider(widget.subjectId)).value?.total ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.headline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      offline
                          ? '正在播放离线缓存 · 第 $_episode 话'
                          : '第 $_episode 话 · ${_ruleName.isEmpty ? '匹配线路中' : _ruleName}${_source != null ? ' · ${_source!.line}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              KonekoChip(
                label: collection?.status.label ?? '追番',
                height: 30,
                fontSize: 12,
                backgroundColor: collection != null
                    ? colorScheme.primary.withValues(alpha: 0.14)
                    : SurfaceLevel.card.colorOf(colorScheme),
                foregroundColor: collection != null
                    ? colorScheme.primary
                    : colorScheme.onSurface,
                trailing: GlyphIcon(
                  Glyphs.chevronDown,
                  size: 12,
                  color: collection != null
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                onPressed: () =>
                    _pickCollectionStatus(title, collection?.status),
              ),
              if (!offline)
                KonekoCircleButton(
                  size: 32,
                  iconSize: 15,
                  glyph: KonekoGlyphs.importFile,
                  tooltip: '离线缓存当前话',
                  onPressed: _loaded && _source != null ? _download : null,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: KonekoSegmentedBar<_PanelTab>(
            segments: [
              const (_PanelTab.episodes, '选集'),
              const (_PanelTab.sources, '换源与弹幕'),
              (
                _PanelTab.comments,
                commentsCount > 0 ? '评论 ($commentsCount)' : '评论',
              ),
            ],
            value: _panelTab,
            onChanged: (tab) => setState(() => _panelTab = tab),
          ),
        ),
        Expanded(
          child: switch (_panelTab) {
            _PanelTab.episodes => _buildEpisodesPanel(
              context: context,
              catalog: catalog,
              collection: collection,
              offline: offline,
              bottomPadding: bottomPadding,
            ),
            _PanelTab.sources => _buildSourcesAndDanmakuPanel(
              context: context,
              rules: rules,
              offline: offline,
              bottomPadding: bottomPadding,
            ),
            _PanelTab.comments => KonekoCommentsPanel(
              subjectId: widget.subjectId,
              embedded: true,
              bottomPadding: bottomPadding,
            ),
          },
        ),
      ],
    );
  }

  Widget _buildEpisodesPanel({
    required BuildContext context,
    required CatalogRepository catalog,
    required CollectionEntry? collection,
    required bool offline,
    required double bottomPadding,
  }) {
    final colorScheme = context.colorScheme;
    final lines = _choices.where((item) => item.number == _episode).toList();

    final sourceEpNums = <int>{for (final item in _choices) item.number}.toList()
      ..sort();
    final catalogEps = catalog.getEpisodes(
      widget.subjectId,
      watchedCount: collection?.watchedEpisodes ?? 0,
      currentEp: _episode,
    );
    final epNumbers = sourceEpNums.isNotEmpty
        ? sourceEpNums
        : [for (final e in catalogEps) e.episodeNumber];

    final totalPages = epNumbers.isEmpty
        ? 1
        : (epNumbers.length + _pageSize - 1) ~/ _pageSize;
    final safePage = _epPageIndex
        .clamp(0, math.max(0, totalPages - 1))
        .toInt();
    final visibleEps = epNumbers
        .skip(safePage * _pageSize)
        .take(_pageSize)
        .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPadding),
      children: [
        if (!offline && lines.length > 1) ...[
          Text(
            '播放线路',
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final line in lines)
                KonekoChip(
                  label: line.line,
                  height: 30,
                  fontSize: 12,
                  elevated: true,
                  selected:
                      line.line == _source?.line && line.page == _source?.page,
                  backgroundColor:
                      line.line == _source?.line && line.page == _source?.page
                      ? colorScheme.primary
                      : SurfaceLevel.card.colorOf(colorScheme),
                  onPressed: () => unawaited(
                    _openEpisode(
                      _episode,
                      ruleId: line.ruleId,
                      choice: line,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '剧集列表',
                      style: AppTextStyle.headline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                  Text(
                    epNumbers.isEmpty ? '加载中' : '共 ${epNumbers.length} 话',
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (totalPages > 1) ...[
                const SizedBox(height: 10),
                KonekoAutoScrollChipBar(
                  height: 32,
                  chipHeight: 28,
                  fontSize: 11.5,
                  elevated: false,
                  padding: EdgeInsets.zero,
                  unselectedColor: SurfaceLevel.block.colorOf(colorScheme),
                  labels: [
                    for (var idx = 0; idx < totalPages; idx++)
                      '${idx * _pageSize + 1}-${((idx + 1) * _pageSize).clamp(1, epNumbers.length)}',
                  ],
                  selectedIndex: safePage,
                  onSelected: (idx) => setState(() => _epPageIndex = idx),
                ),
              ],
              const SizedBox(height: 12),
              if (visibleEps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      offline
                          ? '正在播放离线缓存的第 $_episode 话'
                          : '匹配规则后将自动显示可选剧集',
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final number in visibleEps)
                      _EpisodeChipButton(
                        number: number,
                        current: number == _episode,
                        watched:
                            (collection?.watchedEpisodes ?? 0) >= number &&
                            number != _episode,
                        onPressed: offline
                            ? null
                            : () => unawaited(
                                _openEpisode(
                                  number,
                                  ruleId: _ruleId.isEmpty ? null : _ruleId,
                                  autoSelectFastest: _ruleId.isEmpty,
                                ),
                              ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesAndDanmakuPanel({
    required BuildContext context,
    required List<RulePluginMeta> rules,
    required bool offline,
    required double bottomPadding,
  }) {
    final colorScheme = context.colorScheme;
    final enabledRules = rules.where((r) => r.enabled).toList();
    final lines = _choices.where((item) => item.number == _episode).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPadding),
      children: [
        // Danmaku status & manual matcher card
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                children: [
                  const GlyphIcon(KonekoGlyphs.danmaku, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '弹幕',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.headline
                              .of(context, emphasized: true)
                              .copyWith(color: colorScheme.onSurface),
                        ),
                        Text(
                          _danmakuLoading
                              ? '正在拉取弹幕...'
                              : _danmakuError ??
                                    (_showDanmaku
                                        ? (_danmaku.isNotEmpty
                                            ? _danmakuSummary()
                                            : '暂无弹幕')
                                        : '弹幕已关闭'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _showDanmaku,
                    onChanged: (value) {
                      setState(() => _showDanmaku = value);
                      if (value) unawaited(_loadDanmaku());
                    },
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  KonekoChip(
                    label: '弹幕设置',
                    height: 30,
                    fontSize: 12,
                    leading: GlyphIcon(
                      KonekoGlyphs.tune,
                      size: 13,
                      color: colorScheme.onPrimary,
                    ),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    onPressed: () =>
                        unawaited(openKonekoDanmakuSettingsPage(context)),
                  ),
                  KonekoChip(
                    label: '重新拉取',
                    height: 30,
                    fontSize: 12,
                    leading: GlyphIcon(
                      KonekoGlyphs.refresh,
                      size: 13,
                      color: colorScheme.primary,
                    ),
                    onPressed: _danmakuLoading ? null : () => _loadDanmaku(),
                  ),
                  KonekoChip(
                    label: '手动匹配',
                    height: 30,
                    fontSize: 12,
                    backgroundColor: colorScheme.primary.withValues(
                      alpha: 0.14,
                    ),
                    foregroundColor: colorScheme.primary,
                    onPressed: _openDanmakuSearchSheet,
                  ),
                  KonekoChip(
                    label: '屏蔽词',
                    height: 30,
                    fontSize: 12,
                    onPressed: () => BaseNavigator.push<void>(
                      context,
                      const ServiceSettingsPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!offline)
          KonekoCard(
            corner: 24,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '播放源',
                        style: AppTextStyle.headline
                            .of(context, emphasized: true)
                            .copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                    KonekoChip(
                      label: '重新检索',
                      height: 28,
                      fontSize: 12,
                      onPressed: () => unawaited(
                        _probeAllEnabledRules(
                          customKeyword:
                              _sourceKeywordController.text.trim().isEmpty
                              ? null
                              : _sourceKeywordController.text.trim(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    KonekoChip(
                      label: '规则',
                      height: 28,
                      fontSize: 12,
                      onPressed: () async {
                        await BaseNavigator.push<void>(
                          context,
                          const RulesPage(showBack: true),
                        );
                        if (mounted) {
                          unawaited(_probeAllEnabledRules());
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sourceKeywordController,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText:
                              '自定义搜索词（默认：${_subject?.title ?? ''}）',
                        ),
                        onSubmitted: (v) => unawaited(
                          _probeAllEnabledRules(
                            customKeyword: v.trim().isEmpty ? null : v.trim(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (enabledRules.isEmpty)
                  TextButton(
                    onPressed: () async {
                      await BaseNavigator.push<void>(
                        context,
                        const RulesPage(showBack: true),
                      );
                      if (mounted) await _start();
                    },
                    child: const Text('添加播放规则'),
                  )
                else
                  Column(
                    spacing: 8,
                    children: [
                      for (final rule in enabledRules)
                        _buildRuleProbeCard(context, rule),
                    ],
                  ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '播放线路',
                    style: AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final line in lines)
                        KonekoChip(
                          label: line.line,
                          height: 30,
                          fontSize: 12,
                          selected:
                              line.line == _source?.line &&
                              line.page == _source?.page,
                          onPressed: () => unawaited(
                            _openEpisode(
                              _episode,
                              ruleId: line.ruleId,
                              choice: line,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRuleProbeCard(BuildContext context, RulePluginMeta rule) {
    final colorScheme = context.colorScheme;
    final probe = _probes[rule.id];
    final state = probe?.state ?? RuleProbeState.searching;
    final isCurrent = _ruleId == rule.id;

    final (badgeText, badgeBg, badgeFg) = switch (state) {
      RuleProbeState.searching => (
        '搜索中',
        SurfaceLevel.card.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.found => (
        probe!.latencyMs > 0
            ? '${probe.latencyMs}ms · ${probe.hits.length} 条'
            : '${probe.hits.length} 条',
        colorScheme.successContainer,
        colorScheme.onSuccessContainer,
      ),
      RuleProbeState.noResult => (
        '无结果',
        SurfaceLevel.card.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.captchaRequired => (
        '需验证',
        colorScheme.warningContainer,
        colorScheme.onWarningContainer,
      ),
      RuleProbeState.error => (
        '失败',
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
    };

    void handleSelectRule() {
      if (state == RuleProbeState.captchaRequired &&
          probe?.verifyUrl != null) {
        unawaited(_verifyRule(rule.id, rule.name, probe!.verifyUrl!));
      } else if (state == RuleProbeState.found &&
          probe != null &&
          probe.hits.isNotEmpty) {
        unawaited(_openHit(rule.id, rule.name, probe.hits.first));
      } else {
        unawaited(_openEpisode(_episode, ruleId: rule.id));
      }
    }

    return KonekoBlock(
      selected: isCurrent,
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          PressSurface(
            fill: Colors.transparent,
            shape: AppShape.sm,
            onPressed: handleSelectRule,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                  if (isCurrent)
                    KonekoChip(
                      label: '当前',
                      height: 22,
                      fontSize: 10.5,
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                  KonekoChip(
                    label: badgeText,
                    height: 22,
                    fontSize: 10.5,
                    backgroundColor: badgeBg,
                    foregroundColor: badgeFg,
                  ),
                ],
              ),
            ),
          ),
          if (state == RuleProbeState.found && probe != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final hit in probe.hits.take(6))
                  KonekoChip(
                    label: hit.title,
                    height: 28,
                    fontSize: 12,
                    selected: isCurrent && _activeHitUrl == hit.sourceUrl,
                    backgroundColor:
                        isCurrent && _activeHitUrl == hit.sourceUrl
                        ? colorScheme.primary
                        : SurfaceLevel.card.colorOf(colorScheme),
                    foregroundColor:
                        isCurrent && _activeHitUrl == hit.sourceUrl
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    onPressed: () =>
                        unawaited(_openHit(rule.id, rule.name, hit)),
                  ),
              ],
            )
          else if (state == RuleProbeState.captchaRequired &&
              probe?.verifyUrl != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    probe!.message,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                KonekoChip(
                  label: '去验证',
                  height: 28,
                  fontSize: 12,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  onPressed: () =>
                      _verifyRule(rule.id, rule.name, probe.verifyUrl!),
                ),
              ],
            )
          else if (state == RuleProbeState.error ||
              state == RuleProbeState.noResult)
            Text(
              probe?.message ?? '',
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    PlaybackStatus status,
    PlaybackSession? session,
    bool offline,
    EdgeInsets safe,
  ) {
    final duration = status.duration.inSeconds;
    final position = status.position.inSeconds;
    final max = math.max(1, duration).toDouble();
    final value = (_scrub ?? position.toDouble()).clamp(0.0, max);
    final canAdvance = _choices.any(
      (episode) => episode.number == _episode + 1,
    );

    // Compact portrait non-fullscreen bottom bar: single ultra-slim row over soft gradient
    if (!_fullscreen) {
      return Container(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.76),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            _bareIcon(
              glyph: status.playing ? KonekoGlyphs.pause : KonekoGlyphs.play,
              tooltip: status.playing ? '暂停' : '播放',
              onPressed: !_loaded
                  ? null
                  : () {
                      session?.setPlaying(!status.playing);
                      _armHudAutoHide();
                    },
            ),
            Text(
              formatDurationShort(value.round()),
              style: _style(context, small: true),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Slider(
                  min: 0,
                  max: max,
                  value: value,
                  onChanged: duration > 0 && _loaded
                      ? (v) {
                          _hudTimer?.cancel();
                          setState(() => _scrub = v);
                        }
                      : null,
                  onChangeEnd: (v) {
                    setState(() => _scrub = null);
                    unawaited(session?.seek(Duration(seconds: v.round())));
                    _armHudAutoHide();
                  },
                ),
              ),
            ),
            Text(
              formatDurationShort(duration),
              style: _style(context, small: true),
            ),
            const SizedBox(width: 4),
            PressSurface(
              fill: Colors.transparent,
              shape: AppShape.full,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              onPressed: !_loaded
                  ? null
                  : () {
                      const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
                      setState(
                        () => _speed =
                            speeds[(speeds.indexOf(_speed) + 1) %
                                speeds.length],
                      );
                      unawaited(session?.setRate(_speed));
                      _armHudAutoHide();
                    },
              child: Text(
                '${_speed == _speed.roundToDouble() ? _speed.toStringAsFixed(0) : _speed}x',
                style: _style(context, small: true),
              ),
            ),
            _bareIcon(
              glyph: KonekoGlyphs.fullscreen,
              tooltip: '全屏播放',
              onPressed: () => unawaited(_setFullscreen(true)),
            ),
          ],
        ),
      );
    }

    // Rich fullscreen bottom bar
    return Container(
      padding: EdgeInsets.fromLTRB(
        safe.left + 14,
        18,
        safe.right + 14,
        safe.bottom + 10,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.78),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                formatDurationShort(value.round()),
                style: _style(context, small: true),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Slider(
                    min: 0,
                    max: max,
                    value: value,
                    onChanged: duration > 0 && _loaded
                        ? (v) {
                            _hudTimer?.cancel();
                            setState(() => _scrub = v);
                          }
                        : null,
                    onChangeEnd: (v) {
                      setState(() => _scrub = null);
                      unawaited(session?.seek(Duration(seconds: v.round())));
                      _armHudAutoHide();
                    },
                  ),
                ),
              ),
              Text(
                formatDurationShort(duration),
                style: _style(context, small: true),
              ),
            ],
          ),
          Row(
            spacing: 4,
            children: [
              _bareIcon(
                glyph: status.playing ? KonekoGlyphs.pause : KonekoGlyphs.play,
                tooltip: status.playing ? '暂停' : '播放',
                onPressed: !_loaded
                    ? null
                    : () {
                        session?.setPlaying(!status.playing);
                        _armHudAutoHide();
                      },
              ),
              if (!offline)
                _bareIcon(
                  glyph: KonekoGlyphs.skipNext,
                  tooltip: '下一话',
                  onPressed: canAdvance && !_loading
                      ? () => _openEpisode(_episode + 1, ruleId: _ruleId)
                      : null,
                ),
              const Spacer(),
              _HudAction(
                label: '${_speed.toStringAsFixed(2)}x',
                active: _speed != 1,
                onTap: !_loaded
                    ? null
                    : () {
                        const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
                        setState(
                          () => _speed =
                              speeds[(speeds.indexOf(_speed) + 1) %
                                  speeds.length],
                        );
                        unawaited(session?.setRate(_speed));
                        _armHudAutoHide();
                      },
              ),
              _HudAction(
                label: '超分',
                active: _upscale,
                onTap: !_loaded ? null : () => _setUpscale(!_upscale),
              ),
              _bareIcon(
                glyph: KonekoGlyphs.fullscreenExit,
                tooltip: '退出全屏',
                onPressed: () => unawaited(_setFullscreen(false)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    List<RulePluginMeta> rules,
    bool offline,
  ) {
    final lines = _choices.where((item) => item.number == _episode).toList();
    final uniqueEpisodes = <int, SourceEpisode>{};
    for (final item in _choices) {
      uniqueEpisodes.putIfAbsent(item.number, () => item);
    }
    final episodes = uniqueEpisodes.keys.toList()..sort();

    return _GlassPill(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedControl<_DrawerTab>(
                  segments: const [
                    (_DrawerTab.episodes, '选集'),
                    (_DrawerTab.sources, '切源'),
                    (_DrawerTab.danmaku, '弹幕'),
                  ],
                  value: _drawer,
                  onChanged: (tab) => setState(() => _drawer = tab),
                ),
              ),
              _bareIcon(
                glyph: Glyphs.close,
                tooltip: '关闭面板',
                onPressed: () => setState(() => _drawerOpen = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (_drawer) {
              _DrawerTab.episodes =>
                episodes.isEmpty
                    ? Center(
                        child: Text(
                          offline ? '正在播放已缓存的第 $_episode 话' : '匹配播放源后即可选集',
                          style: _style(context),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 1.32,
                            ),
                        itemCount: episodes.length,
                        itemBuilder: (context, index) {
                          final number = episodes[index];
                          return _HudAction(
                            label: '$number',
                            active: number == _episode,
                            onTap: () => unawaited(
                              _openEpisode(
                                number,
                                ruleId: _ruleId.isEmpty ? null : _ruleId,
                                autoSelectFastest: _ruleId.isEmpty,
                              ),
                            ),
                          );
                        },
                      ),
              _DrawerTab.sources => ListView(
                children: [
                  if (offline)
                    Text('离线播放中', style: _style(context))
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(
                        '播放源',
                        style: _style(context, small: true).copyWith(
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                    for (final rule in rules.where((rule) => rule.enabled))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _HudAction(
                          label: () {
                            final probe = _probes[rule.id];
                            final suffix = switch (probe?.state) {
                              RuleProbeState.found =>
                                ' (${probe!.hits.length})',
                              RuleProbeState.noResult => ' (无)',
                              RuleProbeState.captchaRequired => ' (需验证)',
                              RuleProbeState.error => ' (失败)',
                              _ => '',
                            };
                            return '${rule.name}$suffix';
                          }(),
                          active: _ruleId == rule.id,
                          onTap: () {
                            final probe = _probes[rule.id];
                            if (probe?.state ==
                                    RuleProbeState.captchaRequired &&
                                probe?.verifyUrl != null) {
                              unawaited(
                                _verifyRule(
                                  rule.id,
                                  rule.name,
                                  probe!.verifyUrl!,
                                ),
                              );
                            } else if (probe?.state == RuleProbeState.found &&
                                probe != null &&
                                probe.hits.isNotEmpty) {
                              unawaited(
                                _openHit(rule.id, rule.name, probe.hits.first),
                              );
                            } else {
                              unawaited(
                                _openEpisode(_episode, ruleId: rule.id),
                              );
                            }
                          },
                        ),
                      ),
                    if (lines.isNotEmpty) ...[
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(
                          _ruleName.isNotEmpty
                              ? '播放线路 · $_ruleName'
                              : '播放线路',
                          style: _style(context, small: true).copyWith(
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                      for (final line in lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _HudAction(
                            label: line.line,
                            active:
                                line.line == _source?.line &&
                                line.page == _source?.page,
                            onTap: () => unawaited(
                              _openEpisode(
                                _episode,
                                ruleId: line.ruleId,
                                choice: line,
                              ),
                            ),
                          ),
                        ),
                    ],
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    _HudAction(
                      label: '管理规则',
                      onTap: () => BaseNavigator.push<void>(
                        context,
                        const RulesPage(showBack: true),
                      ),
                    ),
                  ],
                ],
              ),
              _DrawerTab.danmaku => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Text(
                    _danmakuError ??
                        (_danmaku.isEmpty ? '当前话暂无弹幕' : _danmakuSummary()),
                    style: _style(context),
                  ),
                  _HudAction(
                    label: _showDanmaku ? '隐藏弹幕' : '显示弹幕',
                    active: _showDanmaku,
                    onTap: () {
                      setState(() => _showDanmaku = !_showDanmaku);
                      if (_showDanmaku) unawaited(_loadDanmaku());
                    },
                  ),
                  _HudAction(
                    label: '弹幕设置',
                    onTap: () async {
                      setState(() => _drawerOpen = false);
                      await _setFullscreen(false);
                      if (context.mounted) {
                        unawaited(openKonekoDanmakuSettingsPage(context));
                      }
                    },
                  ),
                  _HudAction(label: '重新加载弹幕', onTap: _loadDanmaku),
                  _HudAction(
                    label: '手动匹配弹幕',
                    onTap: () async {
                      setState(() => _drawerOpen = false);
                      await _setFullscreen(false);
                      if (mounted) unawaited(_openDanmakuSearchSheet());
                    },
                  ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }

  TextStyle _style(BuildContext context, {bool small = false}) =>
      (small ? AppTextStyle.caption1 : AppTextStyle.subheadline)
          .of(context, emphasized: !small)
          .copyWith(
            color: small
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          );

  Widget _bareIcon({
    required Glyph glyph,
    required String tooltip,
    VoidCallback? onPressed,
    bool active = false,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 34,
      height: 34,
      child: PressSurface(
        fill: active
            ? context.colorScheme.primary.withValues(alpha: 0.78)
            : Colors.transparent,
        shape: AppShape.full,
        onPressed: onPressed,
        child: Center(
          child: GlyphIcon(
            glyph,
            size: 17,
            color: onPressed == null
                ? Colors.white.withValues(alpha: 0.36)
                : Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _EpisodeChipButton extends StatelessWidget {
  const _EpisodeChipButton({
    required this.number,
    required this.current,
    required this.watched,
    required this.onPressed,
  });

  final int number;
  final bool current;
  final bool watched;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final bg = current
        ? colorScheme.primary
        : watched
        ? colorScheme.primary.withValues(alpha: 0.14)
        : SurfaceLevel.block.colorOf(colorScheme);
    final fg = current
        ? colorScheme.onPrimary
        : watched
        ? colorScheme.primary
        : colorScheme.onSurface;
    return SizedBox(
      width: 56,
      height: 38,
      child: PressSurface(
        fill: bg,
        shape: AppShape.md,
        clipsChild: true,
        onPressed: onPressed,
        child: Center(
          child: Text(
            '$number',
            style: AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
      ),
    );
  }
}

class _HudAction extends StatelessWidget {
  const _HudAction({required this.label, this.active = false, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = active
        ? context.colorScheme.primary.withValues(alpha: .88)
        : Colors.white.withValues(alpha: .16);
    return PressSurface(
      fill: fill,
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onPressed: onTap,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(
                color: onTap == null
                    ? Colors.white.withValues(alpha: 0.38)
                    : Colors.white,
              ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: AppRadius.all(18),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .54),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
