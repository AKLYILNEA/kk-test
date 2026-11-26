import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Interactive in-app WebView allowing the user themselves to complete
/// human verification on a rule site and hand back the resulting session cookies.
class InteractiveVerifyWebView extends StatefulWidget {
  const InteractiveVerifyWebView({
    super.key,
    required this.initialUrl,
    required this.onControllerReady,
  });

  final Uri initialUrl;
  final ValueChanged<Future<({String cookies, String userAgent})> Function()>
  onControllerReady;

  @override
  State<InteractiveVerifyWebView> createState() =>
      _InteractiveVerifyWebViewState();
}

class _InteractiveVerifyWebViewState extends State<InteractiveVerifyWebView> {
  InAppWebViewController? _controller;

  Future<({String cookies, String userAgent})> _harvestSession() async {
    final controller = _controller;
    final parts = <String, String>{};
    var ua =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

    try {
      final currentUrl = await controller?.getUrl() ??
          WebUri(widget.initialUrl.toString());
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

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl.toString())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onControllerReady(_harvestSession);
      },
    );
  }
}
