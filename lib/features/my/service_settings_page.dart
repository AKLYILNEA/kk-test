import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_image.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Kazumi-parity Bangumi & WebDAV sync settings in pure FlClash style:
/// zero bare inline text fields — every credential edits through prism_ui's
/// native floating [InputDialog], and conflict strategy uses [KonekoOptionsItem].
class ServiceSettingsPage extends ConsumerStatefulWidget {
  const ServiceSettingsPage({super.key});

  @override
  ConsumerState<ServiceSettingsPage> createState() =>
      _ServiceSettingsPageState();
}

class _ServiceSettingsPageState extends ConsumerState<ServiceSettingsPage>
    with RouteMotionHoldMixin<ServiceSettingsPage> {
  SecretSettings _secrets = const SecretSettings();
  bool _loading = true;
  bool _busy = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    SecretSettings? loaded;
    var failed = false;
    try {
      loaded = await ref.read(secretsProvider)?.read();
    } on Object {
      failed = true;
    }
    if (!mounted) return;
    showFirstContent(() {
      if (!mounted) return;
      if (loaded != null) _secrets = loaded;
      if (failed) {
        showKonekoBanner(context, '无法读取同步设置', level: BannerLevel.error);
      }
      setState(() => _loading = false);
    });
  }

  Future<void> _saveSecrets(
    SecretSettings next, {
    String? successMessage,
    bool refreshProfile = false,
  }) async {
    final vault = ref.read(secretsProvider);
    if (vault == null) return;
    setState(() => _busy = true);
    try {
      await vault.write(next);
      if (!mounted) return;
      setState(() => _secrets = next);
      if (refreshProfile) ref.invalidate(bangumiProfileProvider);
      if (successMessage != null) {
        showKonekoBanner(context, successMessage, level: BannerLevel.success);
      }
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '保存失败'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editBangumiToken() async {
    final value = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: 'Bangumi Access Token',
        value: _secrets.bangumiToken,
        hintText: '粘贴个人访问令牌',
        obscureText: true,
        resetValue: '',
      ),
    );
    if (!mounted || value == null) return;
    final trimmed = value.trim();
    final updated = SecretSettings(
      bangumiToken: trimmed,
      webdavUrl: _secrets.webdavUrl,
      webdavUser: _secrets.webdavUser,
      webdavPassword: _secrets.webdavPassword,
      danmakuAppId: _secrets.danmakuAppId,
      danmakuKey: _secrets.danmakuKey,
      blockedDanmaku: _secrets.blockedDanmaku,
    );
    await _saveSecrets(
      updated,
      successMessage: trimmed.isEmpty ? '已清除 Bangumi 令牌' : 'Bangumi 令牌已保存',
      refreshProfile: true,
    );
    if (trimmed.isEmpty && mounted) {
      ref
          .read(syncSettingsProvider.notifier)
          .update((s) => s.copyWith(bangumiAutoSync: false));
    }
  }

  Future<void> _editWebDavUrl() async {
    final value = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: 'WebDAV 服务器地址',
        value: _secrets.webdavUrl,
        hintText: 'https://dav.example.com/koneko/',
        keyboardType: TextInputType.url,
        resetValue: '',
        validator: (raw) {
          final text = raw?.trim() ?? '';
          if (text.isEmpty) return null;
          final uri = Uri.tryParse(text);
          if (uri == null ||
              !(uri.scheme == 'https' || uri.scheme == 'http') ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            return '请输入有效的 HTTP 或 HTTPS 地址';
          }
          return null;
        },
      ),
    );
    if (!mounted || value == null) return;
    final trimmed = value.trim();
    final updated = SecretSettings(
      bangumiToken: _secrets.bangumiToken,
      webdavUrl: trimmed,
      webdavUser: _secrets.webdavUser,
      webdavPassword: _secrets.webdavPassword,
      danmakuAppId: _secrets.danmakuAppId,
      danmakuKey: _secrets.danmakuKey,
      blockedDanmaku: _secrets.blockedDanmaku,
    );
    await _saveSecrets(
      updated,
      successMessage: trimmed.isEmpty ? '已清除 WebDAV 地址' : 'WebDAV 地址已保存',
    );
    if (trimmed.isEmpty && mounted) {
      ref
          .read(syncSettingsProvider.notifier)
          .update((s) => s.copyWith(webdavEnabled: false));
    }
  }

  Future<void> _editWebDavUser() async {
    final value = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: 'WebDAV 用户名',
        value: _secrets.webdavUser,
        hintText: '输入云盘账号',
        resetValue: '',
      ),
    );
    if (!mounted || value == null) return;
    final updated = SecretSettings(
      bangumiToken: _secrets.bangumiToken,
      webdavUrl: _secrets.webdavUrl,
      webdavUser: value.trim(),
      webdavPassword: _secrets.webdavPassword,
      danmakuAppId: _secrets.danmakuAppId,
      danmakuKey: _secrets.danmakuKey,
      blockedDanmaku: _secrets.blockedDanmaku,
    );
    await _saveSecrets(updated, successMessage: 'WebDAV 用户名已保存');
  }

  Future<void> _editWebDavPassword() async {
    final value = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: 'WebDAV 密码',
        value: _secrets.webdavPassword,
        hintText: '输入密码或应用专用密码',
        obscureText: true,
        resetValue: '',
      ),
    );
    if (!mounted || value == null) return;
    final updated = SecretSettings(
      bangumiToken: _secrets.bangumiToken,
      webdavUrl: _secrets.webdavUrl,
      webdavUser: _secrets.webdavUser,
      webdavPassword: value,
      danmakuAppId: _secrets.danmakuAppId,
      danmakuKey: _secrets.danmakuKey,
      blockedDanmaku: _secrets.blockedDanmaku,
    );
    await _saveSecrets(updated, successMessage: 'WebDAV 密码已保存');
  }

  Future<void> _runAction(
    String actionId,
    Future<String> Function() task,
    String fallbackError,
  ) async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _busyAction = actionId;
    });
    try {
      final message = await task();
      if (!mounted) return;
      showKonekoBanner(context, message, level: BannerLevel.success);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, fallbackError),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyAction = null;
        });
      }
    }
  }

  Future<void> _importKazumiBackup(TrackingSync sync) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json', 'jsonl', 'tmp', 'hive', 'txt'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    await _runAction(
      'import',
      () async {
        final bytes = await File(path).readAsBytes();
        final count = await sync.importKazumi(bytes);
        return '已从 Kazumi 备份导入 $count 条记录';
      },
      '无法解析所选备份文件',
    );
  }

  String _maskToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return '未配置';
    if (trimmed.length <= 6) return '已配置';
    return '已配置 (••••${trimmed.substring(trimmed.length - 4)})';
  }

  String _hostLabel(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '未配置';
    final host = Uri.tryParse(trimmed)?.host ?? '';
    return host.isEmpty ? trimmed : host;
  }

  Widget _buildActionRow(
    BuildContext context, {
    required String secondaryLabel,
    required bool secondaryLoading,
    required VoidCallback? onSecondary,
    required String primaryLabel,
    required Glyph primaryGlyph,
    required bool primaryLoading,
    required VoidCallback? onPrimary,
  }) {
    final colorScheme = context.colorScheme;
    return Row(
      spacing: 10,
      children: [
        PressSurface(
          fill: SurfaceLevel.card.colorOf(colorScheme),
          shape: AppShape.full,
          clipsChild: true,
          onPressed: onSecondary,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  if (secondaryLoading)
                    const SizedBox.square(
                      dimension: 14,
                      child: ActivityIndicator(size: 14),
                    )
                  else
                    GlyphIcon(
                      KonekoGlyphs.speed,
                      size: 14.5,
                      color: onSecondary == null
                          ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
                          : colorScheme.onSurface,
                    ),
                  Text(
                    secondaryLabel,
                    style: AppTextStyle.footnote
                        .of(context, emphasized: true)
                        .copyWith(
                          color: onSecondary == null
                              ? colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.45,
                                )
                              : colorScheme.onSurface,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: PressSurface(
            fill: onPrimary != null
                ? colorScheme.primary
                : colorScheme.primary.withValues(alpha: 0.36),
            shape: AppShape.full,
            clipsChild: true,
            onPressed: onPrimary,
            child: SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  if (primaryLoading)
                    SizedBox.square(
                      dimension: 14,
                      child: ActivityIndicator(
                        size: 14,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  else
                    GlyphIcon(
                      primaryGlyph,
                      size: 15,
                      color: colorScheme.onPrimary,
                    ),
                  Text(
                    primaryLabel,
                    style: AppTextStyle.subheadline
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final sync = ref.watch(trackingSyncProvider);
    final syncPrefs = ref.watch(syncSettingsProvider);
    final syncPrefsNotifier = ref.read(syncSettingsProvider.notifier);
    final profile = ref.watch(bangumiProfileProvider).value;

    final hasBangumi = _secrets.bangumiToken.trim().isNotEmpty;
    final hasWebDav = _secrets.webdavUrl.trim().isNotEmpty;

    return ArrivalHold(
      ready: !_loading,
      child: KonekoScaffold(
        title: '同步设置',
        showBack: true,
        loading: _busy,
        body: _loading
            ? const Center(child: ActivityIndicator.page())
            : ArrivalCacheExtentBuilder(
                builder: (context, cacheExtent) => CustomScrollView(
                  scrollCacheExtent: cacheExtent,
                  slivers: [
                    const KonekoScrollStart(),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        32 + MediaQuery.paddingOf(context).bottom,
                      ),
                      sliver: SliverList.list(
                        children: [
                          // ---------------------------------------------------
                          // Bangumi 追番同步
                          // ---------------------------------------------------
                          const ListHeader(title: 'Bangumi 追番同步'),
                          KonekoCard(
                            corner: 24,
                            padding: const EdgeInsets.all(14),
                            onPressed: _busy ? null : _editBangumiToken,
                            child: Row(
                              spacing: 12,
                              children: [
                                if (profile != null &&
                                    profile.avatarUrl.isNotEmpty)
                                  KonekoAvatar(
                                    name: profile.nickname,
                                    avatarUrl: profile.avatarUrl,
                                    size: 42,
                                  )
                                else
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: ShapeDecoration(
                                      color: const Color(
                                        0xFFE84C7F,
                                      ).withValues(alpha: 0.14),
                                      shape: AppShape.circle,
                                    ),
                                    child: const Center(
                                      child: GlyphIcon(
                                        KonekoGlyphs.user,
                                        size: 19,
                                        color: Color(0xFFE84C7F),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: 2,
                                    children: [
                                      Text(
                                        profile != null &&
                                                profile.nickname.isNotEmpty
                                            ? profile.nickname
                                            : 'Bangumi 账号',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyle.headline
                                            .of(context, emphasized: true)
                                            .copyWith(
                                              color: colorScheme.onSurface,
                                            ),
                                      ),
                                      Text(
                                        profile != null &&
                                                profile.username.isNotEmpty
                                            ? '@${profile.username} · 同步想看、在看、看过与进度'
                                            : '同步想看、在看、看过状态与剧集进度',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyle.caption1
                                            .of(context)
                                            .copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                KonekoChip(
                                  label: hasBangumi ? '已配置' : '未配置',
                                  height: 22,
                                  fontSize: 11,
                                  backgroundColor: hasBangumi
                                      ? colorScheme.successContainer
                                      : SurfaceLevel.block.colorOf(colorScheme),
                                  foregroundColor: hasBangumi
                                      ? colorScheme.onSuccessContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          KonekoGroup(
                            items: [
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.code,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('Access Token'),
                                subtitle: Text(
                                  _maskToken(_secrets.bangumiToken),
                                ),
                                trailing: const GlyphIcon(
                                  Glyphs.chevronForward,
                                ),
                                onPressed: _busy ? null : _editBangumiToken,
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.externalLink,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('获取 Access Token'),
                                subtitle: const Text(
                                  '前往 next.bgm.tv 生成个人令牌',
                                ),
                                trailing: const GlyphIcon(
                                  Glyphs.chevronForward,
                                ),
                                onPressed: () => launchUrl(
                                  Uri.parse(
                                    'https://next.bgm.tv/demo/access-token',
                                  ),
                                  mode: LaunchMode.externalApplication,
                                ),
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.sync,
                                  color: hasBangumi
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('自动同步追番与进度'),
                                subtitle: Text(
                                  hasBangumi
                                      ? '标记追番或看完剧集时自动推送至 Bangumi'
                                      : '请先填写 Access Token',
                                ),
                                trailing: Switch(
                                  value: hasBangumi && syncPrefs.bangumiAutoSync,
                                  onChanged: !hasBangumi || _busy
                                      ? null
                                      : (v) => syncPrefsNotifier.update(
                                          (s) => s.copyWith(
                                            bangumiAutoSync: v,
                                          ),
                                        ),
                                ),
                                onPressed: !hasBangumi || _busy
                                    ? null
                                    : () => syncPrefsNotifier.update(
                                        (s) => s.copyWith(
                                          bangumiAutoSync: !s.bangumiAutoSync,
                                        ),
                                      ),
                              ),
                              KonekoOptionsItem<BangumiSyncPriority>(
                                leading: GlyphIcon(
                                  KonekoGlyphs.tune,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('冲突解决策略'),
                                subtitle: Text(
                                  syncPrefs.bangumiPriority.description,
                                ),
                                options: BangumiSyncPriority.values,
                                value: syncPrefs.bangumiPriority,
                                textBuilder: (p) => p.label,
                                onChanged: (p) => syncPrefsNotifier.update(
                                  (s) => s.copyWith(bangumiPriority: p),
                                ),
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.info,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('同步结果提示'),
                                subtitle: const Text('追番同步后显示结果横幅'),
                                trailing: Switch(
                                  value: syncPrefs.bangumiSyncToast,
                                  onChanged: _busy
                                      ? null
                                      : (v) => syncPrefsNotifier.update(
                                          (s) => s.copyWith(
                                            bangumiSyncToast: v,
                                          ),
                                        ),
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => syncPrefsNotifier.update(
                                        (s) => s.copyWith(
                                          bangumiSyncToast: !s.bangumiSyncToast,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildActionRow(
                            context,
                            secondaryLabel: '测试连接',
                            secondaryLoading: _busyAction == 'test_bgm',
                            onSecondary: _busy || !hasBangumi || sync == null
                                ? null
                                : () => _runAction(
                                    'test_bgm',
                                    () async {
                                      final name = await sync.testBangumi();
                                      ref.invalidate(bangumiProfileProvider);
                                      return 'Bangumi 连接成功 · $name';
                                    },
                                    'Bangumi 连接失败，请检查令牌与网络',
                                  ),
                            primaryLabel: _busyAction == 'sync_bgm'
                                ? '正在同步…'
                                : '立即同步追番',
                            primaryGlyph: KonekoGlyphs.sync,
                            primaryLoading: _busyAction == 'sync_bgm',
                            onPrimary: _busy || !hasBangumi || sync == null
                                ? null
                                : () => _runAction(
                                    'sync_bgm',
                                    () async {
                                      final count = await sync.syncBangumi(
                                        priority: syncPrefs.bangumiPriority,
                                      );
                                      ref.invalidate(bangumiProfileProvider);
                                      return 'Bangumi 同步完成（共 $count 条记录）';
                                    },
                                    'Bangumi 同步失败，请检查配置与网络',
                                  ),
                          ),

                          const SizedBox(height: 18),

                          // ---------------------------------------------------
                          // WebDAV 多设备同步
                          // ---------------------------------------------------
                          const ListHeader(title: 'WebDAV 多设备同步'),
                          KonekoGroup(
                            items: [
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.cloud,
                                  color: colorScheme.primary,
                                ),
                                title: const Text('服务器地址'),
                                subtitle: Text(_hostLabel(_secrets.webdavUrl)),
                                trailing: const GlyphIcon(
                                  Glyphs.chevronForward,
                                ),
                                onPressed: _busy ? null : _editWebDavUrl,
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.user,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('用户名'),
                                subtitle: Text(
                                  _secrets.webdavUser.trim().isEmpty
                                      ? '未配置'
                                      : _secrets.webdavUser.trim(),
                                ),
                                trailing: const GlyphIcon(
                                  Glyphs.chevronForward,
                                ),
                                onPressed: _busy ? null : _editWebDavUser,
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.code,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('密码'),
                                subtitle: Text(
                                  _secrets.webdavPassword.isEmpty
                                      ? '未配置'
                                      : '已设置',
                                ),
                                trailing: const GlyphIcon(
                                  Glyphs.chevronForward,
                                ),
                                onPressed: _busy ? null : _editWebDavPassword,
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.sync,
                                  color: hasWebDav
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('启用 WebDAV'),
                                subtitle: Text(
                                  hasWebDav
                                      ? '跨设备同步收藏、观看记录与设置'
                                      : '请先配置服务器地址',
                                ),
                                trailing: Switch(
                                  value: hasWebDav && syncPrefs.webdavEnabled,
                                  onChanged: !hasWebDav || _busy
                                      ? null
                                      : (v) => syncPrefsNotifier.update(
                                          (s) => s.copyWith(webdavEnabled: v),
                                        ),
                                ),
                                onPressed: !hasWebDav || _busy
                                    ? null
                                    : () => syncPrefsNotifier.update(
                                        (s) => s.copyWith(
                                          webdavEnabled: !s.webdavEnabled,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          KonekoGroup(
                            items: [
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.history,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('同步观看记录'),
                                subtitle: const Text('播放进度与多源历史记录'),
                                trailing: Switch(
                                  value: syncPrefs.webdavSyncHistory,
                                  onChanged: !hasWebDav || _busy
                                      ? null
                                      : (v) => syncPrefsNotifier.update(
                                          (s) =>
                                              s.copyWith(webdavSyncHistory: v),
                                        ),
                                ),
                                onPressed: !hasWebDav || _busy
                                    ? null
                                    : () => syncPrefsNotifier.update(
                                        (s) => s.copyWith(
                                          webdavSyncHistory:
                                              !s.webdavSyncHistory,
                                        ),
                                      ),
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.heart,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('同步追番收藏'),
                                subtitle: const Text('所有追番分类与观看集数'),
                                trailing: Switch(
                                  value: syncPrefs.webdavSyncCollect,
                                  onChanged: !hasWebDav || _busy
                                      ? null
                                      : (v) => syncPrefsNotifier.update(
                                          (s) =>
                                              s.copyWith(webdavSyncCollect: v),
                                        ),
                                ),
                                onPressed: !hasWebDav || _busy
                                    ? null
                                    : () => syncPrefsNotifier.update(
                                        (s) => s.copyWith(
                                          webdavSyncCollect:
                                              !s.webdavSyncCollect,
                                        ),
                                      ),
                              ),
                              DecorationListItem(
                                leading: GlyphIcon(
                                  KonekoGlyphs.danmaku,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('同步弹幕屏蔽词'),
                                subtitle: const Text('跨设备保留屏蔽关键词'),
                                trailing: Switch(
                                  value: syncPrefs.webdavSyncShield,
                                  onChanged: !hasWebDav || _busy
                                      ? null
                                      : (v) => syncPrefsNotifier.update(
                                          (s) =>
                                              s.copyWith(webdavSyncShield: v),
                                        ),
                                ),
                                onPressed: !hasWebDav || _busy
                                    ? null
                                    : () => syncPrefsNotifier.update(
                                        (s) => s.copyWith(
                                          webdavSyncShield: !s.webdavSyncShield,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildActionRow(
                            context,
                            secondaryLabel: '测试连接',
                            secondaryLoading: _busyAction == 'test_dav',
                            onSecondary: _busy || !hasWebDav || sync == null
                                ? null
                                : () => _runAction(
                                    'test_dav',
                                    () async {
                                      await sync.testWebDav();
                                      return 'WebDAV 服务器连接正常';
                                    },
                                    'WebDAV 连接失败，请检查地址与账号密码',
                                  ),
                            primaryLabel: _busyAction == 'sync_dav'
                                ? '正在同步…'
                                : '立即同步 WebDAV',
                            primaryGlyph: KonekoGlyphs.cloud,
                            primaryLoading: _busyAction == 'sync_dav',
                            onPrimary: _busy || !hasWebDav || sync == null
                                ? null
                                : () => _runAction(
                                    'sync_dav',
                                    () async {
                                      final count = await sync.syncWebDav(
                                        syncHistory:
                                            syncPrefs.webdavSyncHistory,
                                        syncCollect:
                                            syncPrefs.webdavSyncCollect,
                                      );
                                      return 'WebDAV 同步完成（共 $count 条记录）';
                                    },
                                    'WebDAV 同步失败，请检查服务器配置与网络',
                                  ),
                          ),

                          if (sync != null) ...[
                            const SizedBox(height: 18),
                            const ListHeader(title: '数据迁移'),
                            KonekoGroup(
                              items: [
                                DecorationListItem(
                                  leading: GlyphIcon(
                                    KonekoGlyphs.importFile,
                                    color: colorScheme.primary,
                                  ),
                                  title: const Text('从 Kazumi 备份导入'),
                                  subtitle: const Text(
                                    '兼容 Kazumi JSON 与旧版 Hive 备份文件',
                                  ),
                                  trailing: _busyAction == 'import'
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: ActivityIndicator(size: 16),
                                        )
                                      : const GlyphIcon(Glyphs.chevronForward),
                                  onPressed: _busy
                                      ? null
                                      : () => _importKazumiBackup(sync),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
