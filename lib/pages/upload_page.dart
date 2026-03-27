// 上传页面 — 四种来源选择入口
// 对应截图设计：iTunes / 相机胶卷 / 文件 / 从 URL 导入
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../services/upload_task_queue.dart';

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
  void _enqueueFile(String filePath, String fileName) {
    final localId = _queue.addTask(
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.uploadTitle)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // ===== 四个来源卡片 =====
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

