// 波形可视化组件 — 替换 Slider 进度条
// 适配自 music_go_phone 的 stem_waveform_player.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audio_decoder/audio_decoder.dart';
import 'package:path_provider/path_provider.dart';

// ─── 全局波形缓存 ────────────────────────────────

final Map<String, List<double>> _waveformCache = {};
Directory? _waveformCacheDir;

Future<Directory> _getWaveformCacheDir() async {
  if (_waveformCacheDir != null) return _waveformCacheDir!;
  final appDir = await getApplicationSupportDirectory();
  final dir = Directory('${appDir.path}/waveform_cache');
  if (!await dir.exists()) await dir.create(recursive: true);
  _waveformCacheDir = dir;
  return dir;
}

String _cacheKeyForUrl(String url) {
  final uri = Uri.tryParse(url);
  final stableUrl = uri != null ? uri.path : url;
  return '${stableUrl.hashCode.toUnsigned(32).toRadixString(16)}.json';
}

Future<List<double>?> _loadFromDisk(String url) async {
  try {
    final dir = await _getWaveformCacheDir();
    final file = File('${dir.path}/${_cacheKeyForUrl(url)}');
    if (!await file.exists()) return null;
    final json = await file.readAsString();
    final list = (jsonDecode(json) as List).cast<num>();
    return list.map((e) => e.toDouble()).toList();
  } catch (_) {
    return null;
  }
}

Future<void> _saveToDisk(String url, List<double> amps) async {
  try {
    final dir = await _getWaveformCacheDir();
    final file = File('${dir.path}/${_cacheKeyForUrl(url)}');
    await file.writeAsString(jsonEncode(amps));
  } catch (_) {}
}

// ─── 波形条组件 ─────────────────────────────────

/// 替代 Slider 的波形可视化进度条
/// 当 [isActive] 为 true 时显示播放进度高亮（金色），
/// 否则显示灰色静态波形。
class WaveformBar extends StatefulWidget {
  final String url;

  /// 是否是当前正在播放的轨道
  final bool isActive;

  /// 当前播放进度 0.0~1.0（当 isActive 时由外部驱动）
  final double progress;

  /// 当前播放位置文本，如 "1:23"
  final String? currentTimeText;

  /// 拖拽/点击 seek 回调（返回 0.0~1.0）
  final ValueChanged<double>? onSeek;

  /// 波形区高度
  final double height;

  const WaveformBar({
    super.key,
    required this.url,
    this.isActive = false,
    this.progress = 0.0,
    this.currentTimeText,
    this.onSeek,
    this.height = 40,
  });

  @override
  State<WaveformBar> createState() => _WaveformBarState();
}

class _WaveformBarState extends State<WaveformBar> {
  List<double>? _amplitudes;
  bool _loading = false;
  bool _isDragging = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(covariant WaveformBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _loadWaveform();
  }

  String _guessFormat(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'mp3';
    final path = uri.path.toLowerCase();
    if (path.endsWith('.wav')) return 'wav';
    if (path.endsWith('.flac')) return 'flac';
    if (path.endsWith('.ogg')) return 'ogg';
    if (path.endsWith('.m4a')) return 'm4a';
    if (path.endsWith('.aac')) return 'aac';
    return 'mp3';
  }

  Future<void> _loadWaveform() async {
    if (widget.url.isEmpty) return;

    // 内存缓存
    if (_waveformCache.containsKey(widget.url)) {
      if (mounted) setState(() => _amplitudes = _waveformCache[widget.url]);
      return;
    }

    if (_loading) return;
    _loading = true;

    try {
      // 磁盘缓存
      final diskAmps = await _loadFromDisk(widget.url);
      if (diskAmps != null) {
        _waveformCache[widget.url] = diskAmps;
        if (mounted) setState(() => _amplitudes = diskAmps);
        return;
      }

      // 下载并解码
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200) return;

      final format = _guessFormat(widget.url);
      final waveform = await AudioDecoder.getWaveformBytes(
        response.bodyBytes,
        formatHint: format,
        numberOfSamples: 200,
      );

      final amps = waveform.map((e) => e.clamp(0.02, 1.0)).toList();
      _waveformCache[widget.url] = amps;
      if (mounted) setState(() => _amplitudes = amps);

      _saveToDisk(widget.url, amps);
    } catch (e) {
      debugPrint('Waveform extraction failed: $e');
    } finally {
      _loading = false;
    }
  }

  double? _calcProgress(double localX, double containerWidth) {
    if (containerWidth <= 0) return null;
    return (localX / containerWidth).clamp(0.0, 1.0);
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.isActive || widget.onSeek == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final ratio = _calcProgress(details.localPosition.dx, box.size.width);
    if (ratio != null) widget.onSeek!(ratio);
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.isActive || widget.onSeek == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final ratio = _calcProgress(details.localPosition.dx, box.size.width);
    if (ratio != null) {
      setState(() {
        _isDragging = true;
        _dragProgress = ratio;
      });
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final ratio = _calcProgress(details.localPosition.dx, box.size.width);
    if (ratio != null) setState(() => _dragProgress = ratio);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    widget.onSeek?.call(_dragProgress);
    setState(() => _isDragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        _isDragging ? _dragProgress : widget.progress.clamp(0.0, 1.0);

    return GestureDetector(
      onTapUp: _handleTapUp,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            CustomPaint(
              painter: _WaveformPainter(
                progress: progress,
                amplitudes: _amplitudes,
                seed: widget.url.hashCode,
                isActive: widget.isActive,
                currentTimeText: widget.isActive ? widget.currentTimeText : null,
              ),
              size: Size.infinite,
            ),
            // 加载中 shimmer 效果
            if (_loading && _amplitudes == null)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const _WaveformLoadingIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 波形绘制器 ─────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final double progress;
  final List<double>? amplitudes;
  final int seed;
  final bool isActive;
  final String? currentTimeText;

  _WaveformPainter({
    required this.progress,
    this.amplitudes,
    required this.seed,
    required this.isActive,
    this.currentTimeText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 1.5;
    final barCount = (size.width / 2.5).floor();
    if (barCount <= 1) return;
    final gap = (size.width - barCount * barWidth) / (barCount - 1);

    // 始终预留顶部空间，避免活跃/非活跃切换时波形跳动
    const topPadding = 12.0;
    final waveHeight = size.height - topPadding;
    final centerY = topPadding + waveHeight / 2;

    final playedColor = const Color(0xFFE5A825);
    final unplayedColor = isActive
        ? Colors.grey[500]!.withValues(alpha: 0.7)
        : Colors.grey[600]!.withValues(alpha: 0.35);

    final amps = _getAmplitudes(barCount);
    final playedIndex = (progress * barCount).floor();

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      final amp = amps[i];
      final height = amp * (waveHeight * 0.88);

      final paint = Paint()
        ..color = i <= playedIndex ? playedColor : unplayedColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
          Offset(x, centerY - 1), Offset(x, centerY - height / 2), paint);
      canvas.drawLine(
          Offset(x, centerY + 1), Offset(x, centerY + height / 2), paint);
    }

    // 中心线
    final linePaint = Paint()
      ..color = Colors.grey[700]!.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), linePaint);

    // 进度指示器
    if (isActive && progress > 0) {
      final posX = progress * size.width;
      final posPaint = Paint()
        ..color = playedColor
        ..strokeWidth = 1.5;
      canvas.drawLine(
          Offset(posX, topPadding), Offset(posX, size.height), posPaint);
      canvas.drawCircle(Offset(posX, centerY), 2.5, Paint()..color = playedColor);

      // 当前时间文字
      if (currentTimeText != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: currentTimeText,
            style: const TextStyle(
              color: Color(0xFFE5A825),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        double textX = posX - tp.width / 2;
        if (textX < 0) textX = 0;
        if (textX + tp.width > size.width) textX = size.width - tp.width;
        tp.paint(canvas, Offset(textX, 0));
      }
    }
  }

  List<double> _getAmplitudes(int barCount) {
    if (amplitudes == null || amplitudes!.isEmpty) {
      return _fallbackWaveform(barCount, seed);
    }
    final src = amplitudes!;
    final result = List<double>.filled(barCount, 0.0);
    final ratio = src.length / barCount;
    for (int i = 0; i < barCount; i++) {
      final srcStart = (i * ratio).floor();
      final srcEnd = min(((i + 1) * ratio).ceil(), src.length);
      double peak = 0;
      for (int j = srcStart; j < srcEnd; j++) {
        if (src[j] > peak) peak = src[j];
      }
      result[i] = peak;
    }
    return result;
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isActive != isActive ||
        oldDelegate.amplitudes != amplitudes;
  }
}

List<double> _fallbackWaveform(int count, int seed) {
  final rand = Random(seed);
  final list = List.generate(count, (_) {
    return (rand.nextDouble() * 0.6 + rand.nextDouble() * 0.4).clamp(0.05, 1.0);
  });
  for (int i = 1; i < list.length - 1; i++) {
    list[i] = (list[i - 1] + list[i] * 2 + list[i + 1]) / 4;
  }
  return list;
}

// ─── 波形加载动画 ────────────────────────────────

class _WaveformLoadingIndicator extends StatefulWidget {
  const _WaveformLoadingIndicator();

  @override
  State<_WaveformLoadingIndicator> createState() =>
      _WaveformLoadingIndicatorState();
}

class _WaveformLoadingIndicatorState extends State<_WaveformLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ShimmerBarsPainter(progress: _controller.value),
          child: Center(
            child: Text(
              '波形分析中...',
              style: TextStyle(
                fontSize: 9,
                color:
                    Colors.grey[400]!.withValues(alpha: 0.5 + _controller.value * 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerBarsPainter extends CustomPainter {
  final double progress;
  _ShimmerBarsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = (size.width / 3).floor();
    final barWidth = 1.5;
    final gap = (size.width - barCount * barWidth) / (barCount - 1);
    final centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      final phase = (i / barCount + progress) % 1.0;
      final opacity = (sin(phase * 3.14159 * 2) * 0.3 + 0.3).clamp(0.1, 0.6);
      final height =
          sin(phase * 3.14159) * size.height * 0.3 + size.height * 0.1;

      final paint = Paint()
        ..color = const Color(0xFFE5A825).withValues(alpha: opacity)
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ShimmerBarsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
