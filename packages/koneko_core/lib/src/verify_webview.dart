import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:koneko_contract/koneko_contract.dart';

/// Session handle exposed by [InteractiveVerifyWebView] so the verification UI
/// can reload the page, submit a user-entered image-captcha code, and harvest
/// cookies/User-Agent once the user completes verification.
class VerifyWebViewSession {
  VerifyWebViewSession({
    required this.harvest,
    required this.reload,
    required this.submitCaptchaCode,
  });

  final Future<({String cookies, String userAgent})> Function() harvest;
  final Future<void> Function() reload;
  final Future<void> Function(String code) submitCaptchaCode;
}

/// Interactive in-app WebView supporting both:
/// 1. Kazumi-style native image-captcha preview/submission (when [verifyHint]
///    provides image/input/button XPaths so the user can view the captcha image
///    cleanly and type their answer natively without zooming a desktop page).
/// 2. Full interactive webpage verification (when [verifyHint] is null or the
///    user switches to webpage mode).
class InteractiveVerifyWebView extends StatefulWidget {
  const InteractiveVerifyWebView({
    super.key,
    required this.initialUrl,
    required this.onSessionReady,
    this.verifyHint,
    this.onProgress,
    this.onCaptchaImage,
    this.onCaptchaResolved,
  });

  final Uri initialUrl;
  final ValueChanged<VerifyWebViewSession> onSessionReady;
  final RuleVerifyHint? verifyHint;
  final ValueChanged<double>? onProgress;
  final ValueChanged<String>? onCaptchaImage;
  final VoidCallback? onCaptchaResolved;

  @override
  State<InteractiveVerifyWebView> createState() =>
      _InteractiveVerifyWebViewState();
}

class _InteractiveVerifyWebViewState extends State<InteractiveVerifyWebView> {
  static const _defaultUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  InAppWebViewController? _controller;
  bool _captchaSeen = false;
  bool _userSubmitted = false;
  bool _resolvedNotified = false;

  bool get _hasImageHint => widget.verifyHint?.supportsImageCaptcha ?? false;

  Future<({String cookies, String userAgent})> _harvestSession() async {
    final controller = _controller;
    final parts = <String, String>{};
    var ua = _defaultUa;

    try {
      final currentUrl =
          await controller?.getUrl() ?? WebUri(widget.initialUrl.toString());
      final nativeCookies = await CookieManager.instance().getCookies(
        url: currentUrl,
      );
      for (final c in nativeCookies) {
        if (c.name.isNotEmpty) {
          parts[c.name] = '${c.value ?? ''}';
        }
      }
    } on Object {
      // Fallback to document.cookie below.
    }

    if (controller != null) {
      try {
        final docCookie = await controller.evaluateJavascript(
          source: 'document.cookie',
        );
        if (docCookie is String && docCookie.isNotEmpty) {
          for (final item in docCookie.split(';')) {
            final eq = item.indexOf('=');
            if (eq <= 0) continue;
            final name = item.substring(0, eq).trim();
            final value = item.substring(eq + 1).trim();
            if (name.isNotEmpty) parts[name] = value;
          }
        }
        final webUa = await controller.evaluateJavascript(
          source: 'navigator.userAgent',
        );
        if (webUa is String && webUa.trim().isNotEmpty) {
          ua = webUa.trim();
        }
      } on Object {
        // Keep whatever native cookies we already captured.
      }
    }

    final cookieHeader = parts.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
    return (cookies: cookieHeader, userAgent: ua);
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    _captchaSeen = false;
    _userSubmitted = false;
    _resolvedNotified = false;
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.initialUrl.toString())),
    );
  }

  Future<void> _submitCaptchaCode(String code) async {
    final controller = _controller;
    final hint = widget.verifyHint;
    if (controller == null || hint == null || !hint.supportsImageCaptcha) {
      return;
    }
    _userSubmitted = true;
    final jsInput = jsonEncode(hint.inputXpath);
    final jsButton = jsonEncode(hint.buttonXpath);
    final jsCode = jsonEncode(code);
    await controller.evaluateJavascript(
      source:
          '''
(function() {
  function byXpath(xp) {
    try {
      return document.evaluate(xp, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
    } catch (e) { return null; }
  }
  var input = byXpath($jsInput);
  var btn = byXpath($jsButton);
  if (input) {
    input.focus();
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
    if (setter && setter.set) {
      setter.set.call(input, $jsCode);
    } else {
      input.value = $jsCode;
    }
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }
  if (btn) {
    btn.click();
  } else if (input && input.form) {
    input.form.submit();
  }
})();
''',
    );
  }

  Future<void> _injectImageCaptchaObserver(
    InAppWebViewController controller,
  ) async {
    final hint = widget.verifyHint;
    if (hint == null || !hint.supportsImageCaptcha) return;
    final jsImg = jsonEncode(hint.imageXpath);
    final jsInput = jsonEncode(hint.inputXpath);
    await controller.evaluateJavascript(
      source:
          '''
(function() {
  if (window.__konekoCaptchaAttached) return;
  window.__konekoCaptchaAttached = true;
  var imgXpath = $jsImg;
  var inputXpath = $jsInput;
  var found = false;
  var sentSrc = '';

  function byXpath(xp) {
    try {
      return document.evaluate(xp, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
    } catch (e) { return null; }
  }

  function capture(img) {
    function draw() {
      try {
        var w = img.naturalWidth || img.width || 120;
        var h = img.naturalHeight || img.height || 44;
        if (w <= 0 || h <= 0) return;
        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        canvas.getContext('2d').drawImage(img, 0, 0);
        var dataUrl = canvas.toDataURL('image/png');
        if (dataUrl && dataUrl !== sentSrc) {
          sentSrc = dataUrl;
          window.flutter_inappwebview.callHandler('KonekoCaptchaImage', dataUrl);
        }
      } catch (e) {}
    }
    if (img.complete && img.naturalWidth > 0) {
      draw();
    } else {
      img.addEventListener('load', draw, { once: true });
    }
  }

  function poll() {
    var img = byXpath(imgXpath);
    if (img) {
      found = true;
      capture(img);
      return true;
    }
    if (found) {
      window.flutter_inappwebview.callHandler('KonekoCaptchaGone', '');
      return false;
    }
    return false;
  }

  var input = byXpath(inputXpath);
  if (input && typeof input.focus === 'function') {
    try { input.focus(); } catch (e) {}
  }

  var tries = 0;
  var timer = setInterval(function() {
    tries++;
    var img = byXpath(imgXpath);
    if (img) {
      found = true;
      capture(img);
    } else if (found) {
      clearInterval(timer);
      window.flutter_inappwebview.callHandler('KonekoCaptchaGone', '');
    } else if (tries > 60) {
      clearInterval(timer);
    }
  }, 250);

  poll();
})();
''',
    );
  }

  void _notifyResolved() {
    if (_resolvedNotified || !mounted) return;
    _resolvedNotified = true;
    widget.onCaptchaResolved?.call();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl.toString())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        userAgent: _defaultUa,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        if (_hasImageHint) {
          controller.addJavaScriptHandler(
            handlerName: 'KonekoCaptchaImage',
            callback: (args) {
              final dataUrl = args.isNotEmpty ? '${args.first}' : '';
              if (dataUrl.isNotEmpty && mounted) {
                _captchaSeen = true;
                widget.onCaptchaImage?.call(dataUrl);
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'KonekoCaptchaGone',
            callback: (_) {
              if (_captchaSeen && _userSubmitted) {
                _notifyResolved();
              }
            },
          );
        }
        widget.onSessionReady(
          VerifyWebViewSession(
            harvest: _harvestSession,
            reload: _reload,
            submitCaptchaCode: _submitCaptchaCode,
          ),
        );
      },
      onProgressChanged: (_, progress) {
        widget.onProgress?.call((progress / 100.0).clamp(0.0, 1.0));
      },
      onLoadStop: (controller, _) async {
        widget.onProgress?.call(1.0);
        if (!_hasImageHint) return;
        final hint = widget.verifyHint!;
        if (_userSubmitted) {
          // Check whether captcha element is now absent after user submission.
          final jsImg = jsonEncode(hint.imageXpath);
          final stillPresent = await controller.evaluateJavascript(
            source:
                '''
(function() {
  try {
    return document.evaluate($jsImg, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue != null;
  } catch (e) { return false; }
})()
''',
          );
          if (stillPresent == false) {
            _notifyResolved();
            return;
          }
        }
        await _injectImageCaptchaObserver(controller);
      },
    );
  }
}
