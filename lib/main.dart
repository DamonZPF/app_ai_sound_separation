// App 入口
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'pages/home_page.dart';
import 'pages/history_page.dart';
import 'pages/profile_page.dart';
import 'services/supabase_service.dart';
import 'services/pending_task_store.dart';
import 'services/background_upload_channel.dart';
import 'services/upload_task_queue.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 加载 .env 环境变量
  await dotenv.load(fileName: '.env');

  // 2. 初始化 Supabase（仅配置，不需要网络）
  await initSupabase();

  // 3. 初始化待处理任务存储（从 SharedPreferences 恢复）
  await PendingTaskStore.instance.init();

  // 4. 初始化后台上传通道（监听 iOS 原生上传事件）
  BackgroundUploadChannel.instance.init();

  // 5. 恢复上传任务队列（从 SharedPreferences 恢复）
  await UploadTaskQueue.instance.init();

  // 注意：登录需要网络，移到 AppShell 中处理
  runApp(const AISoundApp());
}

class AISoundApp extends StatelessWidget {
  const AISoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Sound Separation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF667eea),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF667eea),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AppShell(),
    );
  }
}

/// 初始化状态
enum _InitStatus { checking, noNetwork, loginFailed, ready }

/// 底部导航壳 — 含网络检查和登录
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  _InitStatus _status = _InitStatus.checking;

  late final List<Widget> _pages = <Widget>[
    HomePage(switchToHistory: () => setState(() => _currentIndex = 1)),
    const HistoryPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkNetworkAndLogin();
  }

  /// 检查网络 → 登录
  Future<void> _checkNetworkAndLogin() async {
    setState(() => _status = _InitStatus.checking);

    // 1. 检查网络连接
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasNetwork = connectivityResult.any(
      (r) => r != ConnectivityResult.none,
    );

    if (!hasNetwork) {
      if (mounted) setState(() => _status = _InitStatus.noNetwork);
      return;
    }

    // 2. 有网络 → 执行登录
    try {
      await signInWithDeviceId();
      if (mounted) setState(() => _status = _InitStatus.ready);
    } catch (_) {
      if (mounted) setState(() => _status = _InitStatus.loginFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 网络检查/登录未完成时显示状态页
    if (_status != _InitStatus.ready) {
      return _buildStatusPage(context);
    }

    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.tabHistory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.tabMine,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 状态图标
              if (_status == _InitStatus.checking)
                const CircularProgressIndicator()
              else
                Icon(
                  _status == _InitStatus.noNetwork
                      ? Icons.wifi_off_rounded
                      : Icons.cloud_off_rounded,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
              const SizedBox(height: 24),

              // 标题
              Text(
                _status == _InitStatus.checking
                    ? l10n.networkCheckingTitle
                    : _status == _InitStatus.noNetwork
                        ? l10n.networkNoConnection
                        : l10n.networkLoginFailed,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // 说明文字
              if (_status != _InitStatus.checking)
                Text(
                  _status == _InitStatus.noNetwork
                      ? l10n.networkNoConnectionMessage
                      : l10n.networkLoginFailed,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 32),

              // 重试按钮
              if (_status != _InitStatus.checking)
                FilledButton.icon(
                  onPressed: _checkNetworkAndLogin,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.networkRetry),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
