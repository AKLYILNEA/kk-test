import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Presents a Kazumi-aligned FlClash verification sheet:
/// - When [verifyHint] describes an image captcha, extracts the captcha image
///   cleanly into a native card so the user can read and type the characters
///   directly (with one-tap "换一张" refresh, auto-completion detection, and a
///   fallback switch to full webpage mode).
/// - Otherwise displays a polished in-app WebView with loading progress and
///   unified animated reload.
Future<bool?> showRuleVerifySheet({
  required BuildContext context,
  required String ruleId,
  required String ruleName,
  required Uri verifyUrl,
  RuleVerifyHint? verifyHint,
}) {
  final hasImageFlow = verifyHint?.supportsImageCaptcha ?? false;
  return showKonekoSheet<bool>(
    context: context,
    title: '站点验证 · $ruleName',
    subtitle: hasImageFlow ? '输入图片中的验证码，通过后自动继续检索' : '完成人机验证后点击底部确认',
    detents: hasImageFlow ? const [0.64, 0.90] : const [0.78, 0.94],
    bodyBuilder: (sheetContext) => _RuleVerifySheetBody(
      ruleId: ruleId,
      ruleName: ruleName,
      verifyUrl: verifyUrl,
      verifyHint: verifyHint,
    ),
  );
}

class _RuleVerifySheetBody extends ConsumerStatefulWidget {
  const _RuleVerifySheetBody({
    required this.ruleId,
    required this.ruleName,
    required this.verifyUrl,
    this.verifyHint,
  });

  final String ruleId;
  final String ruleName;
  final Uri verifyUrl;
  final RuleVerifyHint? verifyHint;

  @override
  ConsumerState<_RuleVerifySheetBody> createState() =>
      _RuleVerifySheetBodyState();
}

class _RuleVerifySheetBodyState extends ConsumerState<_RuleVerifySheetBody> {
  VerifySessionCallbacks? _session;
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  late bool _webpageMode = !(widget.verifyHint?.supportsImageCaptcha ?? false);
  double _progress = 0;
  Uint8List? _captchaBytes;
  String? _imageError;
  String? _inputError;
  bool _reloading = false;
  bool _submitting = false;
  bool _saving = false;
  bool _verifiedDone = false;
  int _imageRevision = 0;
  Timer? _imageTimeout;
  Timer? _submitTimeout;

  bool get _supportsImageFlow =>
      widget.verifyHint?.supportsImageCaptcha ?? false;

  @override
  void initState() {
    super.initState();
    if (!_webpageMode) {
      _armImageTimeout();
    }
  }

  @override
  void dispose() {
    _imageTimeout?.cancel();
    _submitTimeout?.cancel();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _armImageTimeout() {
    _imageTimeout?.cancel();
    _imageTimeout = Timer(const Duration(seconds: 14), () {
      if (!mounted || _captchaBytes != null || _webpageMode || _verifiedDone) {
        return;
      }
      setState(() {
        _reloading = false;
        _imageError = '暂时没有获取到验证码，可重试或切换网页模式';
      });
    });
  }

  Future<void> _receiveCaptchaImage(String dataUrl) async {
    if (!mounted || _verifiedDone) return;
    final rev = ++_imageRevision;
    Uint8List? bytes;
    try {
      bytes = base64Decode(dataUrl.split(',').last);
      final codec = await ui.instantiateImageCodec(bytes);
      codec.dispose();
    } on Object {
      bytes = null;
    }
    if (!mounted || rev != _imageRevision) return;
    _imageTimeout?.cancel();
    setState(() {
      _captchaBytes = bytes;
      _reloading = false;
      _submitting = false;
      _imageError = bytes == null ? '验证码图片无法显示，可换一张或切换网页模式' : null;
    });
  }

  Future<void> _reloadPage() async {
    final session = _session;
    if (session == null || _saving || _verifiedDone) return;
    _imageTimeout?.cancel();
    _submitTimeout?.cancel();
    setState(() {
      _reloading = true;
      _submitting = false;
      _captchaBytes = null;
      _imageError = null;
      _inputError = null;
      _codeController.clear();
    });
    if (!_webpageMode) _armImageTimeout();
    try {
      await session.reload();
    } on Object {
      if (mounted) {
        setState(() {
          _reloading = false;
          _imageError = '刷新页面失败，请重试';
        });
      }
    }
  }

  Future<void> _submitCode() async {
    final session = _session;
    if (session == null || _submitting || _saving || _verifiedDone) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _inputError = '请输入图片中的字符');
      _codeFocus.requestFocus();
      return;
    }
    _codeFocus.unfocus();
    setState(() {
      _submitting = true;
      _inputError = null;
    });
    _submitTimeout?.cancel();
    _submitTimeout = Timer(const Duration(seconds: 9), () {
      if (!mounted || _verifiedDone || _saving) return;
      setState(() {
        _submitting = false;
        _inputError = '验证未通过或已超时，请核对后重试';
      });
    });
    try {
      await session.submitCaptchaCode(code);
    } on Object {
      _submitTimeout?.cancel();
      if (mounted) {
        setState(() {
          _submitting = false;
          _inputError = '提交失败，请重试或切换网页模式';
        });
      }
    }
  }

  Future<void> _complete({bool auto = false}) async {
    final session = _session;
    final sources = ref.read(playbackSourcesProvider);
    if (session == null || sources == null || _saving || _verifiedDone) return;
    _imageTimeout?.cancel();
    _submitTimeout?.cancel();
    setState(() => _saving = true);
    try {
      final result = await session.harvest();
      await sources.saveVerificationCookies(
        widget.ruleId,
        widget.verifyUrl,
        result.cookies,
        userAgent: result.userAgent,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submitting = false;
        _verifiedDone = true;
      });
      await Future<void>.delayed(
        Duration(milliseconds: auto ? 850 : 650),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        showKonekoBanner(context, '读取验证状态失败，请重试', level: BannerLevel.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final builder = ref.watch(verifyWebViewBuilderProvider);
    final colorScheme = context.colorScheme;

    if (builder == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              '当前环境不支持内嵌站点验证',
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final webView = builder(
      initialUrl: widget.verifyUrl,
      verifyHint: widget.verifyHint,
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          if (p >= 1.0 && _webpageMode) _reloading = false;
        });
      },
      onCaptchaImage: (dataUrl) => unawaited(_receiveCaptchaImage(dataUrl)),
      onCaptchaResolved: () => unawaited(_complete(auto: true)),
      onReady: (session) {
        if (mounted) setState(() => _session = session);
      },
    );

    if (_verifiedDone) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: KonekoCard(
          corner: 26,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: ShapeDecoration(
                  color: colorScheme.successContainer,
                  shape: AppShape.full,
                ),
                child: Center(
                  child: GlyphIcon(
                    Glyphs.check,
                    size: 28,
                    color: colorScheme.onSuccessContainer,
                  ),
                ),
              ),
              Text(
                '验证通过',
                style: AppTextStyle.title3
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurface),
              ),
              Text(
                '已保存 ${widget.ruleName} 会话，正在自动继续检索…',
                textAlign: TextAlign.center,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Keep the WebView mounted across Native Image <-> Webpage toggles so
        // cookies and captcha session state stay intact.
        Positioned.fill(
          child: _webpageMode
              ? _buildWebpageMode(context, webView)
              : IgnorePointer(
                  child: Opacity(opacity: 0.0, child: webView),
                ),
        ),
        if (!_webpageMode)
          Positioned.fill(child: _buildNativeCaptchaMode(context)),
      ],
    );
  }

  Widget _buildNativeCaptchaMode(BuildContext context) {
    final colorScheme = context.colorScheme;
    final canSubmit =
        _captchaBytes != null && !_submitting && !_saving && !_reloading;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        // Captcha preview card (aligned with Kazumi's clean native dialog)
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '图形验证码',
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                  KonekoRefreshChip(
                    label: '换一张',
                    loading: _reloading || (_captchaBytes == null && _imageError == null),
                    onPressed: _submitting ? null : () => unawaited(_reloadPage()),
                  ),
                ],
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 112),
                padding: const EdgeInsets.all(14),
                decoration: ShapeDecoration(
                  color: SurfaceLevel.block.colorOf(colorScheme),
                  shape: SuperellipseBorder(borderRadius: AppRadius.all(18)),
                ),
                child: Center(
                  child: _imageError != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 10,
                          children: [
                            Text(
                              _imageError!,
                              textAlign: TextAlign.center,
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                KonekoRefreshChip(
                                  label: '重新加载',
                                  prominent: true,
                                  onPressed: () => unawaited(_reloadPage()),
                                ),
                                KonekoChip(
                                  label: '切换网页模式',
                                  height: 30,
                                  fontSize: 12,
                                  onPressed: () =>
                                      setState(() => _webpageMode = true),
                                ),
                              ],
                            ),
                          ],
                        )
                      : _captchaBytes == null || _submitting || _saving
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 10,
                          children: [
                            const ActivityIndicator(),
                            Text(
                              _saving
                                  ? '正在保存验证状态…'
                                  : _submitting
                                  ? '正在等待站点响应…'
                                  : '正在加载验证码…',
                              style: AppTextStyle.footnote
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        )
                      : ClipRSuperellipse(
                          borderRadius: AppRadius.all(10),
                          child: ColoredBox(
                            color: Colors.white,
                            child: Image.memory(
                              _captchaBytes!,
                              height: 82,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Input card
        KonekoCard(
          corner: 22,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              TextField(
                controller: _codeController,
                focusNode: _codeFocus,
                enabled: !_submitting && !_saving,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                style: AppTextStyle.headline
                    .of(context)
                    .copyWith(color: colorScheme.onSurface, letterSpacing: 2),
                decoration: InputDecoration.collapsed(
                  hintText: '输入图片中的字符',
                  hintStyle: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.72,
                        ),
                        letterSpacing: 0,
                      ),
                ),
                onChanged: (_) {
                  if (_inputError != null) setState(() => _inputError = null);
                },
                onSubmitted: (_) => unawaited(_submitCode()),
              ),
              if (_inputError != null)
                Text(
                  _inputError!,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.error),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 10,
          children: [
            KonekoChip(
              label: '网页模式',
              height: 44,
              fontSize: 13,
              elevated: true,
              backgroundColor: SurfaceLevel.card.colorOf(colorScheme),
              foregroundColor: colorScheme.onSurface,
              onPressed: _submitting || _saving
                  ? null
                  : () => setState(() => _webpageMode = true),
            ),
            Expanded(
              child: PressSurface(
                fill: canSubmit
                    ? colorScheme.primary
                    : colorScheme.primary.withValues(alpha: 0.42),
                shape: AppShape.full,
                clipsChild: true,
                onPressed: canSubmit ? () => unawaited(_submitCode()) : null,
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 6,
                    children: [
                      if (_submitting || _saving)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: ActivityIndicator(color: Colors.white),
                        )
                      else
                        GlyphIcon(
                          Glyphs.check,
                          size: 16,
                          color: colorScheme.onPrimary,
                        ),
                      Text(
                        _submitting
                            ? '验证中…'
                            : _saving
                            ? '保存中…'
                            : '提交验证',
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
        ),
      ],
    );
  }

  Widget _buildWebpageMode(BuildContext context, Widget webView) {
    final colorScheme = context.colorScheme;
    final host = widget.verifyUrl.host;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: KonekoCard(
            corner: 18,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                GlyphIcon(
                  KonekoGlyphs.puzzle,
                  size: 14,
                  color: colorScheme.primary,
                ),
                Expanded(
                  child: Text(
                    host.isNotEmpty ? host : widget.verifyUrl.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                if (_supportsImageFlow)
                  KonekoChip(
                    label: '简洁模式',
                    height: 28,
                    fontSize: 11.5,
                    onPressed: () {
                      setState(() => _webpageMode = false);
                      if (_captchaBytes == null) _armImageTimeout();
                    },
                  ),
                KonekoRefreshChip(
                  label: '刷新',
                  height: 28,
                  fontSize: 11.5,
                  loading: _reloading || (_progress > 0 && _progress < 1),
                  onPressed: () => unawaited(_reloadPage()),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: KonekoCard(
              corner: 22,
              padding: EdgeInsets.zero,
              clip: true,
              child: Stack(
                children: [
                  Positioned.fill(child: webView),
                  if (_progress > 0 && _progress < 1)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        height: 2.5,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _progress.clamp(0.05, 1.0),
                            child: ColoredBox(color: colorScheme.primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            spacing: 10,
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              Expanded(
                child: PressSurface(
                  fill: _session == null || _saving
                      ? colorScheme.primary.withValues(alpha: 0.45)
                      : colorScheme.primary,
                  shape: AppShape.full,
                  clipsChild: true,
                  onPressed: _session == null || _saving
                      ? null
                      : () => unawaited(_complete()),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 6,
                      children: [
                        if (_saving)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: ActivityIndicator(color: Colors.white),
                          )
                        else
                          GlyphIcon(
                            Glyphs.check,
                            size: 16,
                            color: colorScheme.onPrimary,
                          ),
                        Text(
                          _saving ? '保存中…' : '已完成验证',
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
          ),
        ),
      ],
    );
  }
}
