import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko_contract/koneko_contract.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (_) => throw StateError('目录服务尚未初始化'),
);
final ruleRepositoryProvider = Provider<RuleRepository>(
  (_) => throw StateError('规则服务尚未初始化'),
);

final trackingStoreProvider = Provider<TrackingStore?>((_) => null);
final secretsProvider = Provider<SettingsVault?>((_) => null);
final trackingSyncProvider = Provider<TrackingSync?>((_) => null);
final playbackSourcesProvider = Provider<PlaybackSources?>((_) => null);
final offlineLibraryProvider = Provider<OfflineLibrary?>((_) => null);
final danmakuProvider = Provider<DanmakuSource?>((_) => null);
final checkForUpdateProvider =
    Provider<Future<({String version, Uri url})?> Function(String)?>(
      (_) => null,
    );
final playbackFactoryProvider = Provider<PlaybackSession Function()?>(
  (_) => null,
);
final videoViewportProvider = Provider<Widget Function(PlaybackSession)?>(
  (_) => null,
);
final danmakuViewportProvider =
    Provider<
      Widget Function(List<DanmakuItem>, PlaybackStatus, DanmakuSettings)?
    >((_) => null);
typedef VerifySessionCallbacks = ({
  Future<({String cookies, String userAgent})> Function() harvest,
  Future<void> Function() reload,
  Future<void> Function(String code) submitCaptchaCode,
});

final verifyWebViewBuilderProvider =
    Provider<
      Widget Function({
        required Uri initialUrl,
        required ValueChanged<VerifySessionCallbacks> onReady,
        RuleVerifyHint? verifyHint,
        ValueChanged<double>? onProgress,
        ValueChanged<String>? onCaptchaImage,
        VoidCallback? onCaptchaResolved,
      })?
    >((_) => null);

final onlineCatalogProvider = Provider<OnlineCatalog?>((ref) {
  final catalog = ref.watch(catalogRepositoryProvider);
  return catalog is OnlineCatalog ? catalog : null;
});

final catalogUpdatesProvider = StreamProvider<int>((ref) async* {
  final changes = ref.watch(onlineCatalogProvider)?.changes;
  if (changes == null) return;
  var version = 0;
  await for (final _ in changes) {
    yield ++version;
  }
});

final catalogSubjectProvider = Provider.autoDispose.family<AnimeSubject?, int>((
  ref,
  id,
) {
  final catalog = ref.watch(catalogRepositoryProvider);
  return ref.watch(
    catalogUpdatesProvider.select((_) => catalog.getSubjectById(id)),
  );
});

final loadHomeCatalogProvider = FutureProvider<void>((ref) async {
  await ref.watch(onlineCatalogProvider)?.refresh();
});

final loadCatalogSubjectProvider = FutureProvider.autoDispose.family<void, int>(
  (ref, id) async {
    await ref
        .watch(onlineCatalogProvider)
        ?.loadSubject(id, includeExtras: false);
  },
);

final loadCatalogEpisodesProvider = FutureProvider.autoDispose
    .family<void, int>((ref, id) async {
      await ref.watch(onlineCatalogProvider)?.loadEpisodes(id);
    });

final subjectCommentsProvider = FutureProvider.autoDispose
    .family<SubjectCommentsPage, int>((ref, subjectId) async {
      final online = ref.watch(onlineCatalogProvider);
      if (online != null) {
        return online.loadComments(subjectId, offset: 0, limit: 20);
      }
      final mock = ref.watch(catalogRepositoryProvider).getComments(subjectId);
      return SubjectCommentsPage(
        items: mock,
        total: mock.length,
        hasMore: false,
      );
    });

final searchCatalogProvider = FutureProvider.autoDispose.family<void, String>((
  ref,
  query,
) async {
  final catalog = ref.watch(onlineCatalogProvider);
  if (catalog == null || query.trim().isEmpty) return;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 320));
  if (!disposed) await catalog.searchOnline(query);
});

final trackingUpdatesProvider = StreamProvider<TrackingSnapshot>((ref) {
  return ref.watch(trackingStoreProvider)?.changes ?? const Stream.empty();
});

final offlineUpdatesProvider = StreamProvider<List<OfflineEpisode>>((ref) {
  return ref.watch(offlineLibraryProvider)?.changes ?? const Stream.empty();
});

final bangumiProfileProvider = FutureProvider<BangumiProfile?>((ref) async {
  ref.watch(trackingUpdatesProvider);
  final secrets = await ref.watch(secretsProvider)?.read();
  final token = secrets?.bangumiToken.trim() ?? '';
  if (token.isEmpty) return null;
  return ref.watch(onlineCatalogProvider)?.loadProfile(token);
});

final loadTrackedSubjectsProvider = FutureProvider<void>((ref) async {
  final catalog = ref.watch(onlineCatalogProvider);
  if (catalog == null) return;
  final tracking =
      ref.watch(trackingUpdatesProvider).value ??
      ref.watch(trackingStoreProvider)?.current;
  if (tracking == null) return;
  final missing = {
    ...tracking.collections.map((entry) => entry.subjectId),
    ...tracking.history.map((entry) => entry.subjectId),
  }.where((id) => catalog.getSubjectById(id) == null).take(80).toList();
  for (var offset = 0; offset < missing.length; offset += 2) {
    await Future.wait(
      missing
          .skip(offset)
          .take(2)
          .map(
            (id) => catalog
                .loadSubject(id, includeExtras: false)
                .onError((Object _, StackTrace _) {}),
          ),
    );
  }
});
