import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'bangumi.dart';
import 'rules.dart';

class LocalOfflineLibrary implements OfflineLibrary {
  LocalOfflineLibrary(
    this._root,
    this._preferences,
    this._sources, {
    Dio? client,
  }) : _client = client ?? networkClient() {
    try {
      final raw = _preferences.getString(_key);
      if (raw != null) {
        for (final row in jsonList(jsonDecode(raw)).map(jsonObject)) {
          final id = jsonString(row['id']);
          final filename = jsonString(row['file']);
          if (!_validId.hasMatch(id)) continue;
          final file = filename.isNotEmpty && p.basename(filename) == filename
              ? File(p.join(_root.path, id, filename))
              : null;
          final ready = file?.existsSync() ?? false;
          _items[id] = OfflineEpisode(
            id: id,
            subjectId: jsonInt(row['subject']),
            subjectTitle: jsonString(row['title']),
            number: jsonInt(row['episode']),
            ruleId: jsonString(row['ruleId']),
            ruleName: jsonString(row['ruleName']),
            state: ready ? OfflineState.ready : OfflineState.failed,
            progress: ready ? 1 : null,
            media: ready ? file!.uri : null,
            error: ready ? null : '下载未完成，可以从播放页重试',
          );
        }
      }
    } on FormatException {
      // Invalid cached state does not take down playback or the library.
    }
  }

  static const _key = 'koneko_offline_v1';
  static final _validId = RegExp(r'^[a-z0-9]{32}$');
  final Directory _root;
  final SharedPreferences _preferences;
  final PlaybackSources _sources;
  final Dio _client;
  final _items = <String, OfflineEpisode>{};
  final _active = <String, CancelToken>{};
  final _finished = <String, Completer<void>>{};
  final _afterCancel = <String, Future<void>>{};
  final _changes = StreamController<List<OfflineEpisode>>.broadcast();
  Future<void> _saveQueue = Future.value();

  @override
  List<OfflineEpisode> get entries => _items.values.toList().reversed.toList();
  @override
  Stream<List<OfflineEpisode>> get changes => _changes.stream;

  @override
  Future<void> download(AnimeSubject subject, SourceEpisode episode) async {
    final id = sha256
        .convert(
          utf8.encode(
            '${subject.subjectId}:${episode.number}:${episode.ruleId}:${episode.line}',
          ),
        )
        .toString()
        .substring(0, 32);
    if (_active.containsKey(id)) return;
    final pendingRemoval = _afterCancel[id];
    if (pendingRemoval != null) await pendingRemoval;
    if (_active.containsKey(id) || _items[id]?.state == OfflineState.ready) {
      return;
    }
    if (_active.length >= 3) throw StateError('同时下载的剧集已达上限');
    final token = _active[id] = CancelToken();
    final finished = _finished[id] = Completer<void>();
    final job = Directory(p.join(_root.path, id));

    void update(
      OfflineState state, {
      double? progress,
      Uri? media,
      String? error,
    }) {
      if (_active[id] != token || token.isCancelled) return;
      _items[id] = OfflineEpisode(
        id: id,
        subjectId: subject.subjectId,
        subjectTitle: subject.title,
        number: episode.number,
        ruleId: episode.ruleId,
        ruleName: episode.ruleName,
        state: state,
        progress: progress,
        media: media,
        error: error,
      );
      _changes.add(entries);
    }

    update(OfflineState.downloading);
    try {
      await _persist();
      final media = await _sources.resolve(episode);
      _checkToken(token);
      if (await job.exists()) await job.delete(recursive: true);
      await job.create(recursive: true);
      final isHls = media.uri.path.toLowerCase().endsWith('.m3u8');
      final isDash = media.uri.path.toLowerCase().endsWith('.mpd');
      if (isDash) throw StateError('此 DASH 线路暂不能离线缓存，请改用其他线路');
      final String output;
      if (isHls) {
        output = await _downloadHls(
          job,
          media,
          token,
          (progress) => update(OfflineState.downloading, progress: progress),
        );
      } else {
        final ext = p.extension(media.uri.path).toLowerCase();
        final filename =
            'video${RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext) ? ext : '.mp4'}';
        output = p.join(job.path, filename);
        final partial = '$output.part';
        await _client.downloadUri(
          networkUri(media.uri.toString()),
          partial,
          options: Options(headers: media.headers),
          cancelToken: token,
          onReceiveProgress: (downloaded, total) => update(
            OfflineState.downloading,
            progress: total > 0 ? (downloaded / total).clamp(0.0, 1.0) : null,
          ),
        );
        _checkToken(token);
        await File(partial).rename(output);
      }
      update(OfflineState.ready, progress: 1, media: File(output).uri);
    } on Object catch (error) {
      if (!token.isCancelled) {
        update(
          OfflineState.failed,
          error: error is StateError ? error.message : '下载失败，请重试或切换线路',
        );
        if (await job.exists()) await job.delete(recursive: true);
      }
    } finally {
      try {
        await _persist();
      } finally {
        if (_active[id] == token) _active.remove(id);
        _finished.remove(id);
        finished.complete();
      }
    }
  }

  static void _checkToken(CancelToken token) {
    if (token.isCancelled) throw token.cancelError!;
  }

  Future<String> _downloadHls(
    Directory target,
    PlayableMedia media,
    CancelToken token,
    void Function(double) progress,
  ) async {
    var url = media.uri;
    final options = Options(
      headers: media.headers,
      responseType: ResponseType.plain,
    );
    List<String> lines = [];
    for (var layer = 0; layer < 4; layer++) {
      final response = await _client.getUri<String>(
        networkUri(url.toString()),
        options: options,
        cancelToken: token,
      );
      url = response.realUri;
      final text = response.data ?? '';
      if (!text.trimLeft().startsWith('#EXTM3U')) throw StateError('媒体清单格式无效');
      lines = const LineSplitter()
          .convert(text)
          .map((line) => line.trim())
          .toList();
      final index = lines.indexWhere(
        (line) => line.startsWith('#EXT-X-STREAM-INF:'),
      );
      if (index < 0) break;
      final next = lines
          .skip(index + 1)
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .firstOrNull;
      if (next == null) throw StateError('媒体清单没有可下载线路');
      url = url.resolve(next);
    }
    if (!lines.contains('#EXT-X-ENDLIST')) throw StateError('只支持缓存已结束的点播线路');
    if (lines.any(
      (line) =>
          (line.startsWith('#EXT-X-KEY:') ||
              line.startsWith('#EXT-X-SESSION-KEY:')) &&
          !line.contains('METHOD=NONE'),
    )) {
      throw StateError('此加密线路暂不能离线缓存，请改用其他线路');
    }
    final segments = <Uri, String>{};
    String segmentName(String value) {
      final remote = networkUri(url.resolve(value).toString());
      return segments.putIfAbsent(remote, () {
        final extension = p.extension(remote.path).toLowerCase();
        final suffix = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)
            ? extension
            : '.ts';
        return 'part_${segments.length}$suffix';
      });
    }

    final mapped = [
      for (final line in lines)
        if (line.startsWith('#EXT-X-MAP:'))
          line.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (match) => 'URI="${segmentName(match.group(1)!)}"',
          )
        else if (!line.startsWith('#') && line.isNotEmpty)
          segmentName(line)
        else
          line,
    ];
    if (segments.isEmpty || segments.length > 6000) {
      throw StateError('媒体分段数量超出缓存范围');
    }
    var finished = 0;
    for (var offset = 0; offset < segments.length; offset += 4) {
      _checkToken(token);
      final current = segments.entries.skip(offset).take(4);
      await Future.wait(
        current.map((segment) async {
          await _client.downloadUri(
            segment.key,
            p.join(target.path, segment.value),
            options: Options(headers: media.headers),
            cancelToken: token,
          );
          progress(++finished / segments.length);
        }),
      );
    }
    _checkToken(token);
    final playlist = File(p.join(target.path, 'video.m3u8'));
    await playlist.writeAsString(mapped.join('\n'), flush: true);
    return playlist.path;
  }

  @override
  Future<void> remove(String id) async {
    if (!_validId.hasMatch(id)) return;
    if (_afterCancel[id] case final existing?) return existing;
    final job = _active.remove(id);
    job?.cancel('removed');
    _items.remove(id);
    _changes.add(entries);
    final pending = (_finished[id]?.future ?? Future<void>.value()).then(
      (_) => _removeFiles(id),
    );
    _afterCancel[id] = pending;
    try {
      await pending;
      await _persist();
    } finally {
      _afterCancel.remove(id);
    }
  }

  Future<void> _removeFiles(String id) async {
    final target = Directory(p.join(_root.path, id));
    if (await target.exists()) await target.delete(recursive: true);
  }

  Future<void> _persist() {
    final list = entries
        .map(
          (entry) => {
            'id': entry.id,
            'subject': entry.subjectId,
            'title': entry.subjectTitle,
            'episode': entry.number,
            'ruleId': entry.ruleId,
            'ruleName': entry.ruleName,
            'file': entry.media == null
                ? null
                : p.basename(entry.media!.toFilePath()),
          },
        )
        .toList();
    final data = jsonEncode(list);
    return _saveQueue = _saveQueue.onError((Object _, StackTrace _) {}).then((
      _,
    ) async {
      if (!await _preferences.setString(_key, data)) {
        throw StateError('无法保存离线缓存记录');
      }
    });
  }
}
