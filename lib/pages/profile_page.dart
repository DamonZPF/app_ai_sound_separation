// 我的页面 — 用户协议、隐私政策、常见问题
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../l10n/app_localizations.dart';
import 'webview_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mineTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          _MenuItem(
            icon: Icons.description_outlined,
            title: l10n.mineTermsOfService,
            onTap: () => _openWebView(
              context,
              title: l10n.mineTermsOfService,
              url: 'https://miniapp.brightworld.work/user_agreement',
            ),
          ),
          _MenuItem(
            icon: Icons.privacy_tip_outlined,
            title: l10n.minePrivacyPolicy,
            onTap: () => _openWebView(
              context,
              title: l10n.minePrivacyPolicy,
              url: 'https://miniapp.brightworld.work/privacy_policy',
            ),
          ),
          _MenuItem(
            icon: Icons.help_outline,
            title: l10n.mineFaq,
            onTap: () {
              final locale = Localizations.localeOf(context);
              final faqAsset = locale.languageCode == 'zh'
                  ? 'assets/html/faq.html'
                  : 'assets/html/faq_en.html';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _LocalHtmlPage(
                    title: l10n.mineFaq,
                    assetPath: faqAsset,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openWebView(BuildContext context,
      {required String title, required String url}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewPage(url: url, title: title),
      ),
    );
  }
}

/// 加载本地 HTML 资源的页面
class _LocalHtmlPage extends StatefulWidget {
  final String title;
  final String assetPath;

  const _LocalHtmlPage({required this.title, required this.assetPath});

  @override
  State<_LocalHtmlPage> createState() => _LocalHtmlPageState();
}

class _LocalHtmlPageState extends State<_LocalHtmlPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..loadFlutterAsset(widget.assetPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: WebViewWidget(controller: _controller),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }
}
