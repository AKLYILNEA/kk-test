import 'dart:async';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NativePlayback implements PlaybackSession {
  NativePlayback() : _player = Player() {
    _video = VideoController(_player);
    final stream = _player.stream;
    for (final events in <Stream<dynamic>>[
      stream.playing,
      stream.position,
      stream.duration,
      stream.buffering,
      stream.completed,
    ]) {
      _subscriptions.add(events.listen((_) => _publish()));
    }
    _subscriptions.add(
      stream.error.listen((error) {
        _error = error;
        _publish();
      }),
    );
  }

  static void initialize() => MediaKit.ensureInitialized();

  final Player _player;
  late final VideoController _video;
  final _changes = StreamController<PlaybackStatus>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _operations = Future<void>.value();
  bool _disposed = false;
  String? _error;

  @override
  Stream<PlaybackStatus> get changes => _changes.stream;
  @override
  PlaybackStatus get status {
    final state = _player.state;
    return PlaybackStatus(
      position: state.position,
      duration: state.duration,
      playing: state.playing,
      buffering: state.buffering,
      completed: state.completed,
      error: _error,
    );
  }

  void _publish() {
    if (!_disposed) _changes.add(status);
  }

  @override
  Future<void> open(PlayableMedia media, {Duration startAt = Duration.zero}) =>
      _run(() async {
        _error = null;
        await _player.open(
          Media(
            media.uri.toString(),
            httpHeaders: media.headers,
            start: startAt > Duration.zero ? startAt : null,
          ),
        );
        _publish();
      });

  Future<void> _run(Future<void> Function() action) {
    return _operations = _operations.onError((Object _, StackTrace _) {}).then((
      _,
    ) async {
      if (!_disposed) await action();
    });
  }

  @override
  Future<void> seek(Duration position) => _run(() => _player.seek(position));

  @override
  Future<void> setPlaying(bool playing) =>
      _run(playing ? _player.play : _player.pause);

  @override
  Future<void> setRate(double rate) => _run(() => _player.setRate(rate));

  @override
  Future<void> setUpscaling(bool enabled) => _run(() async {
    final native = _player.platform;
    if (native is! NativePlayer) throw UnsupportedError('当前播放器不支持 Anime4K');
    if (!enabled) {
      await native.command(['change-list', 'glsl-shaders', 'clr', '']);
      return;
    }
    const filename = 'Anime4K_Upscale_CNN_x2_S.glsl';
    final root = await getApplicationSupportDirectory();
    final directory = await Directory(
      p.join(root.path, 'anime_shaders'),
    ).create(recursive: true);
    final shader = File(p.join(directory.path, filename));
    if (!await shader.exists()) {
      final data = await rootBundle.load(
        'packages/koneko_core/assets/$filename',
      );
      await shader.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    await native.command(['change-list', 'glsl-shaders', 'set', shader.path]);
  });

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _operations.onError((Object _, StackTrace _) {});
    await _player.dispose();
    await _changes.close();
  }

  static Widget viewport(PlaybackSession session) => session is NativePlayback
      ? Video(controller: session._video, controls: NoVideoControls)
      : const SizedBox.shrink();
}

class NativeDanmaku extends StatefulWidget {
  const NativeDanmaku({super.key, required this.items, required this.status});

  final List<DanmakuItem> items;
  final PlaybackStatus status;

  @override
  State<NativeDanmaku> createState() => _NativeDanmakuState();
}

class _NativeDanmakuState extends State<NativeDanmaku> {
  canvas.DanmakuController<void>? _controller;
  double _previous = -1;
  int _next = 0;

  @override
  void didUpdateWidget(covariant NativeDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _previous = -1;
    // The controller owns a child state. Update it after this frame's build.
    _scheduleUpdate();
  }

  bool _scheduled = false;
  void _scheduleUpdate() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _render();
    });
  }

  void _render() {
    final controller = _controller;
    if (controller == null) return;
    final status = widget.status;
    final now = status.position.inMilliseconds / 1000;
    final items = widget.items;
    if (_previous < 0 || now < _previous || now - _previous > 2) {
      controller.clear();
      var start = 0;
      var end = items.length;
      while (start < end) {
        final mid = (start + end) ~/ 2;
        if (items[mid].timeSeconds < now - 0.25) {
          start = mid + 1;
        } else {
          end = mid;
        }
      }
      _next = start;
    }
    final playing = status.playing && !status.buffering;
    if (playing != controller.running) {
      playing ? controller.resume() : controller.pause();
    }
    if (playing) {
      var emitted = 0;
      while (_next < items.length && items[_next].timeSeconds <= now) {
        final item = items[_next++];
        if (emitted++ >= 18) continue;
        controller.addDanmaku(
          canvas.DanmakuContentItem<void>(
            item.text,
            color: Color(item.colorHex),
          ),
        );
      }
    }
    _previous = now;
  }

  @override
  Widget build(BuildContext context) => canvas.DanmakuScreen<void>(
    option: const canvas.DanmakuOption(area: .62, fontSize: 18, opacity: .85),
    createdController: (controller) {
      _controller = controller;
      _scheduleUpdate();
    },
  );
}
