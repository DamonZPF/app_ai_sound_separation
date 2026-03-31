// 上传页面 — 五种来源选择入口
// 对应截图设计：iTunes / 相机胶卷 / 文件 / 从 URL 导入 / WiFi 传输
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../services/upload_task_queue.dart';
import '../services/lan_upload_service.dart';

class UploadPage extends StatefulWidget {
  final String stem;
  const UploadPage({super.key, required this.stem});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  static const _itunesChannel = MethodChannel('com.app.itunesPicker');

  final _queue = UploadTaskQueue.instance;
  final _urlController = TextEditingController();

  bool _isPicking = false; // 防止多次并发调用原生选择器

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ─── 通用：加入队列后跳转历史页（非阻塞） ───
  Future<void> _enqueueFile(String filePath, String fileName) async {
    final localId = await _queue.addTask(
      filePath: filePath,
      fileName: fileName,
      stem: widget.stem,
    );
    _queue.startProcessing(localId);
    _goToHistory();
  }

  /// 跳转历史页
  void _goToHistory() {
    // pop 当前上传页，回到首页后切换到历史标签
    Navigator.pop(context, 'go_history');
  }

  // ─── 来源 1: iTunes (iOS 原生媒体库选择器) ───
  Future<void> _pickFromItunes() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final result = await _itunesChannel.invokeMethod('pickFromItunes');
      if (result == null) return; // 用户取消
      final Map<String, dynamic> data = Map<String, dynamic>.from(result);
      final path = data['path'] as String;
      final name = data['name'] as String;
      _enqueueFile(path, name);
    } on PlatformException catch (e) {
      _showError(e.message ?? '选取音频失败');
    } catch (e) {
      _showError(e.toString());
    } finally {
      _isPicking = false;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ─── 来源 2: 相机胶卷 (视频) ───
  Future<void> _pickFromCameraRoll() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      _enqueueFile(video.path, video.name);
    } catch (e) {
      _showError(e.toString());
    } finally {
      _isPicking = false;
    }
  }

  // ─── 来源 3: 文件管理器 (自定义类型) ───
  Future<void> _pickFromFiles() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'wma',
          'mp4', 'mov', 'avi', 'mkv', 'webm',
        ],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;
      _enqueueFile(file.path!, file.name);
    } catch (e) {
      _showError(e.toString());
    } finally {
      _isPicking = false;
    }
  }

  // ─── 来源 4: URL 导入 ───
  Future<void> _importFromUrl() async {
    final l10n = AppLocalizations.of(context)!;
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.uploadUrlDialogTitle),
          content: TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: l10n.uploadUrlHint,
              prefixIcon: const Icon(Icons.link),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final value = _urlController.text.trim();
                Navigator.pop(ctx, value.isEmpty ? null : value);
              },
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );

    if (url == null || url.isEmpty) return;

    final localId = _queue.addUrlTask(
      audioUrl: url,
      stem: widget.stem,
    );
    _queue.startProcessing(localId);
    _goToHistory();
  }

  // ─── 来源 5: WiFi 传输 ───
  void _openWifiTransfer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WifiTransferPage(
          stem: widget.stem,
          onFileReceived: (filePath, fileName) {
            // 先入队启动处理
            _enqueueFileOnly(filePath, fileName);
          },
          onGoHistory: () {
            // WiFi 页面关闭后，上传页也 pop 回首页历史标签
            _goToHistory();
          },
        ),
      ),
    );
  }

  /// 仅入队不跳转（供 WiFi 传输使用）
  Future<void> _enqueueFileOnly(String filePath, String fileName) async {
    final localId = await _queue.addTask(
      filePath: filePath,
      fileName: fileName,
      stem: widget.stem,
    );
    _queue.startProcessing(localId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.uploadTitle)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // ===== 五个来源卡片 =====
            Expanded(
              child: ListView(
                children: [
                  _SourceCard(
                    icon: Icons.star,
                    iconColor: Colors.purple,
                    iconBgColor: Colors.purple.shade900,
                    title: l10n.uploadSourceItunes,
                    subtitle: l10n.uploadSourceItunesDesc,
                    onTap: _isPicking ? null : _pickFromItunes,
                  ),
                  const SizedBox(height: 12),
                  _SourceCard(
                    icon: Icons.photo_library,
                    iconColor: Colors.white,
                    iconBgColor: Colors.brown.shade700,
                    title: l10n.uploadSourceCameraRoll,
                    subtitle: l10n.uploadSourceCameraRollDesc,
                    onTap: _isPicking ? null : _pickFromCameraRoll,
                  ),
                  const SizedBox(height: 12),
                  _SourceCard(
                    icon: Icons.folder,
                    iconColor: Colors.white,
                    iconBgColor: Colors.blue.shade700,
                    title: l10n.uploadSourceFiles,
                    subtitle: l10n.uploadSourceFilesDesc,
                    onTap: _isPicking ? null : _pickFromFiles,
                  ),
                  const SizedBox(height: 12),
                  _SourceCard(
                    icon: Icons.link,
                    iconColor: Colors.white,
                    iconBgColor: Colors.red.shade700,
                    title: l10n.uploadSourceUrl,
                    subtitle: l10n.uploadSourceUrlDesc,
                    onTap: _isPicking ? null : _importFromUrl,
                  ),
                  const SizedBox(height: 12),
                  _SourceCard(
                    icon: Icons.wifi,
                    iconColor: Colors.white,
                    iconBgColor: Colors.teal.shade700,
                    title: l10n.uploadSourceWifi,
                    subtitle: l10n.uploadSourceWifiDesc,
                    onTap: _openWifiTransfer,
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

/// 来源选择卡片 —— 匹配截图深色圆角设计
class _SourceCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SourceCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
            color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              // 标题 + 描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// WiFi 传输引导页面（全屏 Modal）
// ──────────────────────────────────────────────

class _WifiTransferPage extends StatefulWidget {
  final String stem;
  final void Function(String filePath, String fileName) onFileReceived;
  final VoidCallback onGoHistory;

  const _WifiTransferPage({
    required this.stem,
    required this.onFileReceived,
    required this.onGoHistory,
  });

  @override
  State<_WifiTransferPage> createState() => _WifiTransferPageState();
}

class _WifiTransferPageState extends State<_WifiTransferPage> {
  final _lanService = LanUploadService.instance;
  bool _starting = false;
  int _receivedCount = 0;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  @override
  void dispose() {
    _lanService.onFileReceived = null;
    _lanService.stop();
    super.dispose();
  }

  Future<void> _startServer() async {
    setState(() => _starting = true);

    _lanService.onFileReceived = (filePath, fileName) {
      if (!mounted) return;
      setState(() => _receivedCount++);
      widget.onFileReceived(filePath, fileName);

      // 弹窗询问：继续传输还是开始分离
      _showFileReceivedDialog(fileName);
    };

    final ok = await _lanService.start();
    if (mounted) {
      setState(() => _starting = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.wifiTransferNoWifi),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  /// 文件接收后弹窗：继续传输 or 开始分离
  void _showFileReceivedDialog(String fileName) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: Text(l10n.wifiTransferFileReceived),
        content: Text(
          l10n.wifiTransferFileReceivedMsg(fileName),
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.wifiTransferContinue),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.wifiTransferStartNow),
          ),
        ],
      ),
    ).then((startNow) {
      if (startNow == true && mounted) {
        // 关闭 WiFi 页面，跳转历史页
        _lanService.onFileReceived = null;
        _lanService.stop();
        Navigator.pop(context);
        widget.onGoHistory();
      }
      // startNow == false: 保持 LAN 服务，继续等待更多文件
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.wifiTransferTitle),
        actions: [
          if (_receivedCount > 0)
            TextButton(
              onPressed: () {
                _lanService.onFileReceived = null;
                _lanService.stop();
                Navigator.pop(context);
                widget.onGoHistory();
              },
              child: Text(l10n.wifiTransferStartNow),
            ),
        ],
      ),
      body: _starting
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<String?>(
              valueListenable: _lanService.serverUrl,
              builder: (context, url, _) {
                if (url == null) {
                  return Center(child: Text(l10n.wifiTransferNoWifi));
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ─── WiFi 图标动画 ───
                      Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.teal.shade400,
                                Colors.teal.shade800,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.teal.withValues(alpha: 0.3),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.wifi,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ─── 步骤引导 ───
                      _StepItem(
                        number: '1',
                        text: l10n.wifiTransferStep1,
                        icon: Icons.wifi_find,
                      ),
                      const SizedBox(height: 16),
                      _StepItem(
                        number: '2',
                        text: l10n.wifiTransferStep2,
                        icon: Icons.computer,
                      ),
                      const SizedBox(height: 16),
                      _StepItem(
                        number: '3',
                        text: l10n.wifiTransferStep3,
                        icon: Icons.upload_file,
                      ),

                      const SizedBox(height: 32),

                      // ─── URL 地址卡片 ───
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.teal.shade900.withValues(alpha: 0.6),
                              Colors.teal.shade700.withValues(alpha: 0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.teal.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '在电脑浏览器中输入',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              url,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已复制到剪贴板'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('复制地址'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Colors.white70,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ─── 已接收文件计数 ───
                      if (_receivedCount > 0)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade900.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade400, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '已接收 $_receivedCount 个文件',
                                style: TextStyle(
                                  color: Colors.green.shade300,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 32),

                      // ─── 停止按钮 ───
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _lanService.stop();
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: Text(l10n.wifiTransferClose),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(
                              color: theme.colorScheme.error.withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// 步骤引导项
class _StepItem extends StatelessWidget {
  final String number;
  final String text;
  final IconData icon;

  const _StepItem({
    required this.number,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.teal.withValues(alpha: 0.15),
            ),
            child: Icon(icon, size: 18, color: Colors.teal.shade300),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
