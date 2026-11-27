import 'dart:io';

import 'package:koneko_contract/koneko_contract.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/bangumi.dart';
import 'src/danmaku.dart';
import 'src/downloads.dart';
import 'src/playback_sources.dart';
import 'src/rules.dart';
import 'src/sync.dart';
import 'src/tracking.dart';

export 'src/app_release.dart' show findKonekoUpdate;
export 'src/player.dart' show NativePlayback, NativeDanmaku;
export 'src/verify_webview.dart'
    show InteractiveVerifyWebView, VerifyWebViewSession;

class KonekoCore {
  KonekoCore._({
    required this.catalog,
    required this.rules,
    required this.sources,
    required this.tracking,
    required this.settings,
    required this.sync,
    required this.danmaku,
    required this.offline,
  });

  final OnlineCatalog catalog;
  final ManagedRules rules;
  final PlaybackSources sources;
  final TrackingStore tracking;
  final SettingsVault settings;
  final TrackingSync sync;
  final DanmakuSource danmaku;
  final OfflineLibrary offline;

  static Future<KonekoCore> open() async {
    final preferences = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    final catalog = BangumiCatalog(preferences);
    final rules = KazumiRules(preferences);
    final sources = KazumiSources(rules, preferences: preferences);
    final tracking = LocalTracking(preferences);
    const settings = SecureSettings();
    return KonekoCore._(
      catalog: catalog,
      rules: rules,
      sources: sources,
      tracking: tracking,
      settings: settings,
      sync: KonekoSync(tracking, catalog, settings, preferences),
      danmaku: DandanplaySource(settings),
      offline: LocalOfflineLibrary(
        Directory(p.join(support.path, 'downloads')),
        preferences,
        sources,
      ),
    );
  }
}
