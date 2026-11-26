import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

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
  late int _episode = widget.initialEpisode;
  late String _ruleId = widget.initialRuleId;
  late String _ruleName = widget.initialRuleName;
  PlaybackSession? _session;
  PlaybackStatus _status = const PlaybackStatus();
  StreamSubscription<PlaybackStatus>? _subscription;
  Timer? _saveTimer;
  Timer? _brightnessTimer;
  SourceEpisode? _source;
  List<SourceEpisode> _choices = const [];
  List<DanmakuItem> _danmaku = const [];
  bool _loading = true;
  bool _loaded = false;
  bool _pageActive = true;
  bool _showHud = true;
  bool _showDanmaku = true;
  bool _drawerOpen = false;
  bool _upscale = false;
  double _speed = 1;
  double _brightness = 1;
  double? _scrub;
  bool _changingBrightness = false;
  _DrawerTab _drawer = _DrawerTab.episodes;
  String? _error;
  String? _danmakuError;
  int _request = 0;
  int _danmakuRequest = 0;
  int _lastCheckpoint = -1;
  bool _lastCompleted = false;

  AnimeSubject? get _subject =>
      ref.read(catalogRepositoryProvider).getSubjectById(widget.subjectId);

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
    WidgetsBinding.instance.removeObserver(this);
    _request++;
    _danmakuRequest++;
    _saveTimer?.cancel();
    _brightnessTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_session?.dispose());
    super.dispose();
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
        await _openEpisode(_episode);
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
    setState(() => _status = status);
    if (completed) _checkpoint();
  }

  bool _isCurrent(int request) => mounted && request == _request;

  Duration _resumeAt(int episode) {
    final history = ref
        .read(historyProvider.notifier)
        .positionFor(widget.subjectId, episode);
    if (history == null || history.isCompleted) return Duration.zero;
    return Duration(seconds: history.positionSeconds);
  }

  Future<void> _startOffline(Uri uri) async {
    final request = ++_request;
    final session = _session!;
    setState(() {
      _loading = true;
      _error = null;
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
      _loadDanmaku();
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
      _error = null;
      _scrub = null;
      _danmaku = const [];
    });
    try {
      await session.setPlaying(false);
      final resolver = ref.read(playbackSourcesProvider);
      if (resolver == null) throw StateError('规则播放服务不可用');
      var subject = _subject;
      if (subject == null) {
        await ref.read(onlineCatalogProvider)?.loadSubject(widget.subjectId);
        if (!_isCurrent(request)) return;
        subject = _subject;
      }
      if (subject == null) throw StateError('未能加载番剧资料');

      final rules = ref
          .read(rulesProvider)
          .where((rule) => rule.enabled)
          .toList();
      if (rules.isEmpty) throw StateError('请先添加并启用一条 Kazumi 规则');
      final ids = (ruleId != null
          ? [ruleId]
          : {
              if (_ruleId.isNotEmpty && rules.any((rule) => rule.id == _ruleId))
                _ruleId,
              ...rules.map((rule) => rule.id),
            }.toList());
      Object? problem;
      for (final id in ids.take(4)) {
        if (!_isCurrent(request)) return;
        try {
          final options = await resolver.lookup(subject, id);
          if (!_isCurrent(request)) return;
          final available = options
              .where((item) => item.number == episode)
              .toList();
          if (available.isEmpty) throw StateError('这条规则没有第 $episode 话');
          setState(() {
            _choices = options;
            _ruleId = id;
            _ruleName = options.first.ruleName;
          });
          final currentLine = _source?.line;
          final episodeSource =
              choice ??
              available.where((item) => item.line == currentLine).firstOrNull ??
              available.first;
          final media = await resolver.resolve(episodeSource);
          if (!_isCurrent(request)) return;
          await session.open(media, startAt: initialPosition);
          if (!_isCurrent(request)) return;
          if (!_pageActive) await session.setPlaying(false);
          if (!_isCurrent(request)) return;
          setState(() {
            _episode = episode;
            _source = episodeSource;
            _ruleId = episodeSource.ruleId;
            _ruleName = episodeSource.ruleName;
            _status = session.status;
            _loading = false;
            _loaded = true;
            _lastCheckpoint = -1;
            _lastCompleted = false;
          });
          _loadDanmaku();
          return;
        } on Object catch (error) {
          problem = error;
        }
      }
      throw problem ?? StateError('暂时没有可播放的线路');
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _error = featureError(error, '无法播放这一话，请切换线路或规则');
      });
    }
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

  Future<void> _loadDanmaku() async {
    final token = ++_danmakuRequest;
    if (!_showDanmaku) return;
    final subject = _subject;
    final source = ref.read(danmakuProvider);
    if (source == null || subject == null) return;
    try {
      final items = await source.load(subject, _episode);
      if (mounted && token == _danmakuRequest) {
        setState(() {
          _danmaku = items;
          _danmakuError = null;
        });
      }
    } on Object catch (error) {
      if (mounted && token == _danmakuRequest) {
        setState(() => _danmakuError = featureError(error, '暂时取不到弹幕'));
      }
    }
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

  void _drawerTo(_DrawerTab tab) => setState(() {
    _drawer = tab;
    _drawerOpen = true;
  });

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogUpdatesProvider);
    ref.watch(loadCatalogSubjectProvider(widget.subjectId));
    final subject = _subject;
    final title = subject?.title ?? widget.offline?.subjectTitle ?? 'Koneko';
    final rules = ref.watch(rulesProvider);
    final session = _session;
    final viewport = ref.watch(videoViewportProvider);
    final overlay = ref.watch(danmakuViewportProvider);
    final safe = MediaQuery.paddingOf(context);
    final status = _status;
    final error =
        _error ??
        (_loaded && status.duration == Duration.zero && status.error != null
            ? '媒体播放失败，请切换线路'
            : null);
    final offline = widget.offline != null;

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _checkpoint();
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                if (_drawerOpen) {
                  _drawerOpen = false;
                } else {
                  _showHud = !_showHud;
                }
              }),
              onVerticalDragUpdate: (event) =>
                  _adjustBrightness(-event.delta.dy * .004),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (session != null && viewport != null)
                    IgnorePointer(child: viewport(session))
                  else if (subject != null)
                    Opacity(
                      opacity: .35,
                      child: KonekoPosterArt(subject: subject),
                    ),
                  if (_brightness < 1)
                    IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 1 - _brightness),
                      ),
                    ),
                  if (_showDanmaku && _danmaku.isNotEmpty && overlay != null)
                    IgnorePointer(child: overlay(_danmaku, status)),
                ],
              ),
            ),
            if (_loading || (_loaded && status.buffering))
              const Center(child: ActivityIndicator(color: Colors.white)),
            if (error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _GlassPill(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: _style(context),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _HudAction(label: '重试', onTap: _start),
                            if (!offline)
                              _HudAction(
                                label: rules.any((rule) => rule.enabled)
                                    ? '选择播放源'
                                    : '添加规则',
                                onTap: () async {
                                  if (rules.any((rule) => rule.enabled)) {
                                    _drawerTo(_DrawerTab.sources);
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
                top: safe.top + 75,
                left: 16,
                right: 16,
                child: Center(
                  child: _GlassPill(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 9,
                    ),
                    child: Text(
                      '亮度 ${(_brightness * 100).round()}%',
                      style: _style(context),
                    ),
                  ),
                ),
              ),
            if (_showHud)
              Positioned(
                top: safe.top + 12,
                left: 12,
                right: 12,
                child: _GlassPill(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    spacing: 6,
                    children: [
                      _round(
                        glyph: Glyphs.backFor(Theme.of(context).platform),
                        tooltip: '返回',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$title · 第 $_episode 话',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(context),
                            ),
                            Text(
                              offline
                                  ? '离线缓存'
                                  : (_ruleName.isEmpty ? '等待匹配线路' : _ruleName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(context, small: true),
                            ),
                          ],
                        ),
                      ),
                      _round(
                        glyph: KonekoGlyphs.danmaku,
                        tooltip: _showDanmaku ? '关闭弹幕' : '开启弹幕',
                        active: _showDanmaku,
                        onPressed: () {
                          setState(() => _showDanmaku = !_showDanmaku);
                          _loadDanmaku();
                        },
                      ),
                      _round(
                        glyph: KonekoGlyphs.layers,
                        tooltip: '选集与播放源',
                        onPressed: () =>
                            setState(() => _drawerOpen = !_drawerOpen),
                      ),
                    ],
                  ),
                ),
              ),
            if (_showHud)
              Positioned(
                left: 12,
                right: 12,
                bottom: safe.bottom + 14,
                child: _controls(context, status, session, offline),
              ),
            AnimatedPositioned(
              duration: context.motionDuration(
                const Duration(milliseconds: 230),
              ),
              curve: Curves.easeOutCubic,
              top: safe.top + 12,
              bottom: safe.bottom + 12,
              right: _drawerOpen ? 12 : -360,
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
        ),
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    PlaybackStatus status,
    PlaybackSession? session,
    bool offline,
  ) {
    final duration = status.duration.inSeconds;
    final position = status.position.inSeconds;
    final max = math.max(1, duration).toDouble();
    final value = (_scrub ?? position.toDouble()).clamp(0.0, max);
    final canAdvance = _choices.any(
      (episode) => episode.number == _episode + 1,
    );
    return _GlassPill(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Slider(
                    min: 0,
                    max: max,
                    value: value,
                    onChanged: duration > 0 && _loaded
                        ? (value) => setState(() => _scrub = value)
                        : null,
                    onChangeEnd: (value) {
                      setState(() => _scrub = null);
                      unawaited(
                        session?.seek(Duration(seconds: value.round())),
                      );
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
            spacing: 5,
            children: [
              _round(
                glyph: status.playing ? KonekoGlyphs.pause : KonekoGlyphs.play,
                tooltip: status.playing ? '暂停' : '播放',
                onPressed: !_loaded
                    ? null
                    : () => session?.setPlaying(!status.playing),
              ),
              if (!offline)
                _round(
                  glyph: KonekoGlyphs.skipNext,
                  tooltip: '下一话',
                  onPressed: canAdvance && !_loading
                      ? () => _openEpisode(_episode + 1)
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
                      },
              ),
              _HudAction(
                label: '超分',
                active: _upscale,
                onTap: !_loaded ? null : () => _setUpscale(!_upscale),
              ),
              if (!offline)
                _round(
                  glyph: KonekoGlyphs.importFile,
                  tooltip: '离线缓存当前话',
                  onPressed: _loaded && _source != null ? _download : null,
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
              _round(
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
                            onTap: _loading
                                ? null
                                : () => _openEpisode(number, ruleId: _ruleId),
                          );
                        },
                      ),
              _DrawerTab.sources => ListView(
                children: [
                  if (offline)
                    Text('当前正在离线播放', style: _style(context))
                  else ...[
                    for (final rule in rules.where((rule) => rule.enabled))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: _HudAction(
                          label: rule.name,
                          active: _ruleId == rule.id,
                          onTap: _loading
                              ? null
                              : () => _openEpisode(_episode, ruleId: rule.id),
                        ),
                      ),
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: _HudAction(
                          label: line.line,
                          active: line.page == _source?.page,
                          onTap: _loading
                              ? null
                              : () => _openEpisode(
                                  _episode,
                                  ruleId: line.ruleId,
                                  choice: line,
                                ),
                        ),
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
              _DrawerTab.danmaku => ListView(
                children: [
                  Text(
                    _danmakuError ?? '当前弹幕 ${_danmaku.length} 条',
                    style: _style(context),
                  ),
                  const SizedBox(height: 8),
                  _HudAction(label: '重新加载弹幕', onTap: _loadDanmaku),
                  const SizedBox(height: 6),
                  _HudAction(
                    label: '弹幕服务与屏蔽词',
                    onTap: () async {
                      await BaseNavigator.push<void>(
                        context,
                        const ServiceSettingsPage(),
                      );
                      if (mounted) await _loadDanmaku();
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

  Widget _round({
    required Glyph glyph,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    return KonekoCircleButton(
      glyph: glyph,
      tooltip: tooltip,
      size: 34,
      iconSize: 17,
      fillColor: active
          ? context.colorScheme.primary
          : Colors.white.withValues(alpha: .14),
      foregroundColor: Colors.white.withValues(
        alpha: onPressed == null ? .35 : 1,
      ),
      onPressed: onPressed,
    );
  }

  TextStyle _style(BuildContext context, {bool small = false}) =>
      (small ? AppTextStyle.caption1 : AppTextStyle.subheadline)
          .of(context, emphasized: !small)
          .copyWith(color: Colors.white.withValues(alpha: small ? .78 : 1));
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: AppRadius.all(24),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: ColoredBox(
        color: const Color(0xaf101321),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class _HudAction extends StatelessWidget {
  const _HudAction({
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => ElasticPress(
    enabled: onTap != null,
    child: PressSurface(
      fill: active
          ? context.colorScheme.primary
          : Colors.white.withValues(alpha: .14),
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      onPressed: onTap,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTextStyle.caption1
            .of(context, emphasized: true)
            .copyWith(
              color: Colors.white.withValues(alpha: onTap == null ? .48 : 1),
            ),
      ),
    ),
  );
}
