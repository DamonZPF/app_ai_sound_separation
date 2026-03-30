// App 入口
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  // 2. 初始化 Supabase
  await initSupabase();

  // 3. 设备 ID 匿名登录
  await signInWithDeviceId();

  // 4. 初始化待处理任务存储（从 SharedPreferences 恢复）
  await PendingTaskStore.instance.init();

  // 5. 初始化后台上传通道（监听 iOS 原生上传事件）
  BackgroundUploadChannel.instance.init();

  // 6. 恢复上传任务队列（从 SharedPreferences 恢复）
  await UploadTaskQueue.instance.init();

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

/// 底部导航壳
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  late final List<Widget> _pages = <Widget>[
    HomePage(switchToHistory: () => setState(() => _currentIndex = 1)),
    const HistoryPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
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
}
