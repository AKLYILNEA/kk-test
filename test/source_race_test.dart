import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koneko/features/player/source_race.dart';

void main() {
  test('a verified candidate wins while a slow candidate is pending', () async {
    final slow = Completer<void>();
    final fast = Completer<void>();
    final cancelled = Completer<void>();
    final selection = racePlaybackSources<String>([
      (offer) async {
        await slow.future;
        offer('slow', verified: true);
      },
      (offer) async {
        await fast.future;
        offer('fast', verified: true);
      },
    ], cancelled.future);

    fast.complete();
    expect(await selection, 'fast');
    slow.complete();
    cancelled.complete();
  });

  test('a resolved stream can play when other sources stall', () async {
    final slow = Completer<void>();
    final cancelled = Completer<void>();
    final selection = racePlaybackSources<String>(
      [(_) => slow.future, (offer) async => offer('fallback', verified: false)],
      cancelled.future,
      fallbackDelay: Duration.zero,
    );
    expect(await selection, 'fallback');
    slow.complete();
    cancelled.complete();
  });

  test('selection ends at the deadline when every source stalls', () async {
    final slow = Completer<void>();
    final cancelled = Completer<void>();
    final selection = racePlaybackSources<String>(
      [(_) => slow.future],
      cancelled.future,
      timeout: Duration.zero,
    );
    expect(await selection, isNull);
    slow.complete();
    cancelled.complete();
  });

  test(
    'manual selection cancels auto selection and ignores a late result',
    () async {
      final slow = Completer<void>();
      final cancelled = Completer<void>();
      final selection = racePlaybackSources<String>([
        (offer) async {
          await slow.future;
          offer('late', verified: true);
        },
      ], cancelled.future);
      cancelled.complete();
      expect(await selection, isNull);
      slow.complete();
    },
  );
}
