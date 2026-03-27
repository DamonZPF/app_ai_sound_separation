import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/supabase_service.dart';
import 'webview_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final userId = getCachedUserId() ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mineTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ─── 用户头像区 ───
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.person,
                      size: 40, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  userId.isNotEmpty ? '${userId.substring(0, 8)}...' : '未登录',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.mineAnonymousUser,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ─── 菜单项 ───
          _MenuItem(
            icon: Icons.info_outline,
            title: l10n.mineAbout,
            onTap: () => _showAbout(context, l10n),
          ),
          _MenuItem(
            icon: Icons.language,
            title: l10n.mineLanguage,
            onTap: () {
              // TODO: 语言切换
            },
          ),
          _MenuItem(
            icon: Icons.privacy_tip_outlined,
            title: l10n.mineUsageGuide,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WebViewPage(
                    url: 'https://miniapp.brightworld.work/user_agreement',
                    title: l10n.mineUsageGuide,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context, AppLocalizations l10n) {
    showAboutDialog(
      context: context,
      applicationName: l10n.homeTitle,
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2024 AI Sound Separation',
      children: [
        const SizedBox(height: 16),
        Text(l10n.homeSubtitle),
      ],
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
