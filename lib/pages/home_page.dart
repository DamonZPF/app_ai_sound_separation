// 首页 — 分离类型选择
// 对应原 mini-program 的 index/index.tsx
import 'package:flutter/material.dart';
import 'upload_page.dart';

/// 分离类型定义
class StemType {
  final String id;
  final String name;
  final String icon; // emoji
  final IconData materialIcon;
  final List<Color> gradientColors;

  const StemType({
    required this.id,
    required this.name,
    required this.icon,
    required this.materialIcon,
    required this.gradientColors,
  });
}

/// 与小程序保持一致的 10 种分离类型
const List<StemType> separationTypes = [
  StemType(
    id: 'vocals',
    name: '提取人声与伴奏',
    icon: '🎵',
    materialIcon: Icons.mic,
    gradientColors: [Color(0xFF667eea), Color(0xFF764ba2)],
  ),
  StemType(
    id: 'noise',
    name: '去除背景噪音',
    icon: '🎙️',
    materialIcon: Icons.noise_aware,
    gradientColors: [Color(0xFF6a11cb), Color(0xFF2575fc)],
  ),
  StemType(
    id: 'drums',
    name: '提取鼓点音轨',
    icon: '🥁',
    materialIcon: Icons.music_note,
    gradientColors: [Color(0xFFf093fb), Color(0xFFf5576c)],
  ),
  StemType(
    id: 'bass',
    name: '提取贝斯音轨',
    icon: '🎸',
    materialIcon: Icons.graphic_eq,
    gradientColors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
  ),
  StemType(
    id: 'acoustic',
    name: '提取原声吉他音轨',
    icon: '🪕',
    materialIcon: Icons.queue_music,
    gradientColors: [Color(0xFF43e97b), Color(0xFF38f9d7)],
  ),
  StemType(
    id: 'electric',
    name: '提取电吉他音轨',
    icon: '🎸',
    materialIcon: Icons.electric_bolt,
    gradientColors: [Color(0xFFfa709a), Color(0xFFfee140)],
  ),
  StemType(
    id: 'piano',
    name: '提取钢琴音轨',
    icon: '🎹',
    materialIcon: Icons.piano,
    gradientColors: [Color(0xFFa18cd1), Color(0xFFfbc2eb)],
  ),
  StemType(
    id: 'synth',
    name: '提取合成器音轨',
    icon: '🎛️',
    materialIcon: Icons.tune,
    gradientColors: [Color(0xFFfad0c4), Color(0xFFffd1ff)],
  ),
  StemType(
    id: 'strings',
    name: '提取弦乐音轨',
    icon: '🎻',
    materialIcon: Icons.surround_sound,
    gradientColors: [Color(0xFFf6d365), Color(0xFFfda085)],
  ),
  StemType(
    id: 'wind',
    name: '提取管乐器音轨',
    icon: '🎺',
    materialIcon: Icons.air,
    gradientColors: [Color(0xFF89f7fe), Color(0xFF66a6ff)],
  ),
];

class HomePage extends StatefulWidget {
  final VoidCallback? switchToHistory;
  const HomePage({super.key, this.switchToHistory});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ---- 分离类型卡片网格 ----
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final st = separationTypes[index];
                    return _StemTypeCard(
                      stemType: st,
                      onTap: () => _navigateToUpload(context, st),
                    );
                  },
                  childCount: separationTypes.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToUpload(BuildContext context, StemType st) {
    if (_isNavigating) return;
    _isNavigating = true;
    Navigator.of(context)
        .push<String>(
          MaterialPageRoute(
            builder: (_) => UploadPage(stem: st.id),
          ),
        )
        .then((result) {
          _isNavigating = false;
          if (result == 'go_history') {
            widget.switchToHistory?.call();
          }
        });
  }
}

/// 分离类型卡片
class _StemTypeCard extends StatelessWidget {
  final StemType stemType;
  final VoidCallback onTap;

  const _StemTypeCard({
    required this.stemType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: stemType.gradientColors,
          ),
          boxShadow: [
            BoxShadow(
              color: stemType.gradientColors.first.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 背景装饰
            Positioned(
              right: -12,
              top: -12,
              child: Icon(
                stemType.materialIcon,
                size: 64,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            // 主内容
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stemType.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    stemType.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
