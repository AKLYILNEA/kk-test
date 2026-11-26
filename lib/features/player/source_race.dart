import 'dart:async';

/// Gives verified streams priority and a resolved stream a short head start
/// over waiting for every other candidate to finish.
Future<T?> racePlaybackSources<T extends Object>(
  Iterable<Future<void> Function(void Function(T, {required bool verified}))>
  jobs,
  Future<void> cancelled, {
  Duration timeout = const Duration(seconds: 12),
  Duration fallbackDelay = const Duration(milliseconds: 900),
}) {
  final candidates = jobs.toList();
  final result = Completer<T?>();
  T? fallback;
  Timer? grace;
  var remaining = candidates.length;

  void finish(T? selection) {
    if (!result.isCompleted) result.complete(selection);
  }

  void offer(T selection, {required bool verified}) {
    if (result.isCompleted) return;
    if (verified) {
      finish(selection);
    } else if (fallback == null) {
      fallback = selection;
      grace = Timer(fallbackDelay, () => finish(fallback));
    }
  }

  final deadline = Timer(timeout, () => finish(fallback));
  unawaited(cancelled.then((_) => finish(null)));
  if (candidates.isEmpty) finish(null);
  for (final job in candidates) {
    unawaited(
      Future<void>.sync(
        () => job(offer),
      ).onError((Object _, StackTrace _) {}).whenComplete(() {
        if (--remaining == 0) finish(fallback);
      }),
    );
  }
  return result.future.whenComplete(() {
    deadline.cancel();
    grace?.cancel();
  });
}
