import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
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
  final _appId = TextEditingController();
  final _appKey = TextEditingController();
  final _shield = TextEditingController();
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
      _bangumi.text = secrets.bangumiToken;
      _davUrl.text = secrets.webdavUrl;
      _davUser.text = secrets.webdavUser;
      _davPassword.text = secrets.webdavPassword;
      _appId.text = secrets.danmakuAppId;
      _appKey.text = secrets.danmakuKey;
      _shield.text = secrets.blockedDanmaku.join('\n');
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '无法读取服务设置', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _bangumi,
      _davUrl,
      _davUser,
      _davPassword,
      _appId,
      _appKey,
      _shield,
    ]) {
      controller.dispose();
    }
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
      await vault.write(
        SecretSettings(
          bangumiToken: _bangumi.text.trim(),
          webdavUrl: url,
          webdavUser: _davUser.text.trim(),
          webdavPassword: _davPassword.text,
          danmakuAppId: _appId.text.trim(),
          danmakuKey: _appKey.text.trim(),
          blockedDanmaku: _shield.text
              .split(RegExp(r'[\n,，]+'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(),
        ),
      );
      final count = await sync?.call();
      if (!mounted) return;
      showKonekoBanner(
        context,
        count == null ? '服务设置已保存' : '$service 同步完成，读取 $count 条记录',
        level: BannerLevel.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '$service 操作失败，请检查连接和凭据'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextField(
      controller: controller,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      decoration: InputDecoration(hintText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(trackingSyncProvider);
    return KonekoScaffold(
      title: '服务与同步',
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
          : Builder(
              builder: (context) => ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  context.contentTopPadding,
                  16,
                  30 + context.bottomInset,
                ),
                children: [
                  KonekoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Bangumi',
                          style: AppTextStyle.headline.of(context),
                        ),
                        _field(_bangumi, 'Access Token', secret: true),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => launchUrl(
                                Uri.parse('https://bgm.tv/dev/app'),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: const Text('管理访问令牌'),
                            ),
                            FilledButton(
                              onPressed: _busy || sync == null
                                  ? null
                                  : () => _run(sync.syncBangumi, 'Bangumi'),
                              child: const Text('同步收藏与进度'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  KonekoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'WebDAV',
                          style: AppTextStyle.headline.of(context),
                        ),
                        _field(_davUrl, '服务器 URL'),
                        _field(_davUser, '用户名'),
                        _field(_davPassword, '密码或应用密码', secret: true),
                        Text(
                          '同步 Koneko 收藏与历史，并读取该服务器上的 Kazumi 备份。',
                          style: context.listSubtitleStyle,
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _busy || sync == null
                              ? null
                              : () => _run(sync.syncWebDav, 'WebDAV'),
                          child: const Text('同步 WebDAV'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  KonekoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '弹幕与屏蔽词（弹弹Play）',
                          style: AppTextStyle.headline.of(context),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '已内置 Kazumi 同款弹幕接口，开箱即用。下方 App ID 与密钥留空即可，仅在需要自定义密钥时填写。',
                          style: context.listSubtitleStyle,
                        ),
                        const SizedBox(height: 6),
                        _field(_appId, '自定义 App ID（留空使用内置默认）'),
                        _field(_appKey, '自定义 App 密钥（留空使用内置默认）', secret: true),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _shield,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: '弹幕屏蔽词，每行一个',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
