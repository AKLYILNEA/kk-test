import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class ServiceSettingsPage extends ConsumerStatefulWidget {
  const ServiceSettingsPage({super.key});

  @override
  ConsumerState<ServiceSettingsPage> createState() =>
      _ServiceSettingsPageState();
}

class _ServiceSettingsPageState extends ConsumerState<ServiceSettingsPage> {
  final _bangumi = TextEditingController();
  final _davUrl = TextEditingController();
  final _davUser = TextEditingController();
  final _davPassword = TextEditingController();
  SecretSettings _existingSecrets = const SecretSettings();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final secrets = await ref.read(secretsProvider)?.read();
      if (!mounted || secrets == null) return;
      _existingSecrets = secrets;
      _bangumi.text = secrets.bangumiToken;
      _davUrl.text = secrets.webdavUrl;
      _davUser.text = secrets.webdavUser;
      _davPassword.text = secrets.webdavPassword;
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '无法读取同步设置', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _bangumi.dispose();
    _davUrl.dispose();
    _davUser.dispose();
    _davPassword.dispose();
    super.dispose();
  }

  Future<void> _run(Future<int> Function()? sync, String service) async {
    if (_busy || _loading) return;
    final vault = ref.read(secretsProvider);
    if (vault == null) return;
    setState(() => _busy = true);
    try {
      final url = _davUrl.text.trim();
      if (url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !(uri.scheme == 'https' || uri.scheme == 'http') ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const FormatException('WebDAV 地址必须是有效的 HTTP 或 HTTPS 地址');
        }
      }
      final updated = SecretSettings(
        bangumiToken: _bangumi.text.trim(),
        webdavUrl: url,
        webdavUser: _davUser.text.trim(),
        webdavPassword: _davPassword.text,
        danmakuAppId: _existingSecrets.danmakuAppId,
        danmakuKey: _existingSecrets.danmakuKey,
        blockedDanmaku: _existingSecrets.blockedDanmaku,
      );
      await vault.write(updated);
      _existingSecrets = updated;
      ref.invalidate(bangumiProfileProvider);
      final count = await sync?.call();
      if (!mounted) return;
      showKonekoBanner(
        context,
        count == null ? '同步设置已保存' : '$service 同步完成（共 $count 条记录）',
        level: BannerLevel.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '$service 同步失败，请检查配置与网络'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    bool secret = false,
    TextInputType? keyboardType,
  }) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          label,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
        TextField(
          controller: controller,
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: !secret,
          keyboardType: keyboardType,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  Widget _buildStatusPill(BuildContext context, bool configured) {
    final colorScheme = context.colorScheme;
    return KonekoChip(
      label: configured ? '已配置' : '未配置',
      height: 22,
      fontSize: 11,
      backgroundColor: configured
          ? colorScheme.successContainer
          : SurfaceLevel.block.colorOf(colorScheme),
      foregroundColor: configured
          ? colorScheme.onSuccessContainer
          : colorScheme.onSurfaceVariant,
    );
  }

  Widget _buildPrimaryAction(
    BuildContext context, {
    required String label,
    required Glyph glyph,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = context.colorScheme;
    final enabled = onPressed != null;
    return PressSurface(
      fill: enabled
          ? colorScheme.primary
          : colorScheme.primary.withValues(alpha: 0.36),
      shape: AppShape.full,
      clipsChild: true,
      onPressed: onPressed,
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 6,
          children: [
            GlyphIcon(glyph, size: 15, color: colorScheme.onPrimary),
            Text(
              label,
              style: AppTextStyle.subheadline
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.onPrimary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final sync = ref.watch(trackingSyncProvider);
    final hasBangumi = _bangumi.text.trim().isNotEmpty;
    final hasWebDav = _davUrl.text.trim().isNotEmpty;

    return KonekoScaffold(
      title: '同步设置',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: Glyphs.check,
          tooltip: '保存设置',
          isLoading: _busy,
          onPressed: _loading ? null : () => _run(null, '设置'),
        ),
      ],
      body: _loading
          ? const Center(child: ActivityIndicator())
          : CustomScrollView(
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
                      const ListHeader(title: 'Bangumi'),
                      KonekoCard(
                        corner: 26,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 14,
                          children: [
                            Row(
                              spacing: 10,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFE84C7F,
                                    ).withValues(alpha: 0.14),
                                    borderRadius: AppRadius.all(12),
                                  ),
                                  child: const Center(
                                    child: GlyphIcon(
                                      KonekoGlyphs.user,
                                      size: 18,
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
                                        'Bangumi 账号',
                                        style: AppTextStyle.headline
                                            .of(context, emphasized: true)
                                            .copyWith(
                                              color: colorScheme.onSurface,
                                            ),
                                      ),
                                      Text(
                                        '同步个人资料、追番状态与观看进度',
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
                                _buildStatusPill(context, hasBangumi),
                              ],
                            ),
                            _buildField(
                              context,
                              controller: _bangumi,
                              label: 'Access Token',
                              hint: '粘贴个人访问令牌',
                              secret: true,
                            ),
                            Row(
                              spacing: 10,
                              children: [
                                KonekoChip(
                                  label: '获取令牌',
                                  height: 40,
                                  fontSize: 13,
                                  backgroundColor: SurfaceLevel.block.colorOf(
                                    colorScheme,
                                  ),
                                  foregroundColor: colorScheme.onSurface,
                                  leading: GlyphIcon(
                                    KonekoGlyphs.externalLink,
                                    size: 13.5,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  onPressed: () => launchUrl(
                                    Uri.parse('https://bgm.tv/dev/app'),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                ),
                                Expanded(
                                  child: _buildPrimaryAction(
                                    context,
                                    label: '同步收藏与进度',
                                    glyph: KonekoGlyphs.sync,
                                    onPressed: _busy || sync == null
                                        ? null
                                        : () =>
                                              _run(sync.syncBangumi, 'Bangumi'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const ListHeader(title: 'WebDAV'),
                      KonekoCard(
                        corner: 26,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 14,
                          children: [
                            Row(
                              spacing: 10,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: AppRadius.all(12),
                                  ),
                                  child: Center(
                                    child: GlyphIcon(
                                      KonekoGlyphs.cloud,
                                      size: 18,
                                      color: colorScheme.primary,
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
                                        'WebDAV 云盘',
                                        style: AppTextStyle.headline
                                            .of(context, emphasized: true)
                                            .copyWith(
                                              color: colorScheme.onSurface,
                                            ),
                                      ),
                                      Text(
                                        '跨设备备份追番收藏与历史记录',
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
                                _buildStatusPill(context, hasWebDav),
                              ],
                            ),
                            _buildField(
                              context,
                              controller: _davUrl,
                              label: '服务器地址',
                              hint: 'https://dav.example.com/koneko/',
                              keyboardType: TextInputType.url,
                            ),
                            _buildField(
                              context,
                              controller: _davUser,
                              label: '用户名',
                              hint: '输入账号',
                            ),
                            _buildField(
                              context,
                              controller: _davPassword,
                              label: '密码',
                              hint: '输入密码或应用专用密码',
                              secret: true,
                            ),
                            _buildPrimaryAction(
                              context,
                              label: '立即同步',
                              glyph: KonekoGlyphs.cloud,
                              onPressed: _busy || sync == null
                                  ? null
                                  : () => _run(sync.syncWebDav, 'WebDAV'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
