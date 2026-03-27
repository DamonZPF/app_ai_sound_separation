// 历史记录页面
// 合并展示：本地队列任务（上传中/处理中/失败）+ 远程已完成结果
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../services/stem_api_service.dart';
import '../services/audio_player_service.dart';
import '../services/upload_task_queue.dart';
import '../models/stem_task.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _stemApi = StemApiService();
  final _audio = AudioPlayerService.instance;
  final _queue = UploadTaskQueue.instance;
  List<StemResultItem> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _audio.stop();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final results = await _stemApi.getHistory();
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _deleteResult(String resultId) async {
    final ok = await _stemApi.deleteResult(resultId);
    if (ok) {
      setState(() {
        _results.removeWhere((r) => r.id == resultId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: ValueListenableBuilder<List<StemTask>>(
                valueListenable: _queue.tasksNotifier,
                builder: (context, queueTasks, _) {
                  // 过滤掉已完成的队列任务（它们会出现在远程历史中）
                  final activeTasks =
                      queueTasks.where((t) => !t.isCompleted).toList();
                  final totalCount = activeTasks.length + _results.length;

                  if (totalCount == 0) {
                    return _buildEmpty(context);
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: totalCount,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      // 队列任务在前
                      if (i < activeTasks.length) {
                        return _QueueTaskCard(
                          task: activeTasks[i],
                          onRetry: () =>
                              _queue.retryTask(activeTasks[i].stemTaskId),
                          onRemove: () =>
                              _queue.removeTask(activeTasks[i].stemTaskId),
                        );
                      }
                      // 远程历史在后
                      final ri = i - activeTasks.length;
                      return _ResultCard(
                        result: _results[ri],
                        audioService: _audio,
                        onDelete: () => _deleteResult(_results[ri].id),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      // 需要 ListView 以支持 RefreshIndicator
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history,
                  size: 64,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(l10n.historyEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.45),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// 队列任务卡片（上传中 / 处理中 / 失败）
// ──────────────────────────────────────────────
class _QueueTaskCard extends StatelessWidget {
  final StemTask task;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _QueueTaskCard({
    required this.task,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final isFailed = task.isFailed;
    final statusColor = isFailed ? Colors.red : theme.colorScheme.primary;

    String statusText;
    if (task.status == 'uploading') {
      statusText = l10n.historyStatusUploading;
    } else if (task.status == 'processing') {
      statusText = l10n.historyStatusProcessing;
    } else if (isFailed) {
      statusText = l10n.historyStatusFailed;
    } else {
      statusText = task.status;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.trackTitle.isNotEmpty ? task.trackTitle : task.stem,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            // 进度条（非失败状态）
            if (!isFailed) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress / 100,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${task.progress}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],

            // 错误信息
            if (isFailed && task.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                task.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // 操作按钮
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isFailed)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.historyRetry,
                        style: const TextStyle(fontSize: 12)),
                  ),
                TextButton.icon(
                  onPressed: onRemove,
                  icon:
                      Icon(Icons.close, size: 18, color: Colors.grey),
                  label: Text(l10n.historyDelete,
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 远程结果卡片（与原实现一致）
// ──────────────────────────────────────────────
class _ResultCard extends StatefulWidget {
  final StemResultItem result;
  final AudioPlayerService audioService;
  final VoidCallback onDelete;

  const _ResultCard({
    required this.result,
    required this.audioService,
    required this.onDelete,
  });

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _downloading = false;

  String get _title {
    if (widget.result.trackTitle?.isNotEmpty == true) {
      return widget.result.trackTitle!;
    }
    if (widget.result.displayLabel.isNotEmpty) return widget.result.displayLabel;
    return widget.result.stemType;
  }

  String get _dateStr {
    final ca = widget.result.createdAt;
    if (ca == null || ca.isEmpty) return '';
    return ca.length >= 10 ? ca.substring(0, 10) : ca;
  }

  Future<void> _playAudio() async {
    if (widget.result.url.isEmpty) return;
    try {
      await widget.audioService.play(widget.result.url);
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.playFailed)),
        );
      }
    }
  }

  Future<void> _downloadAndShare() async {
    if (widget.result.url.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _downloading = true);

    try {
      final dir = await getTemporaryDirectory();
      final ext = widget.result.outputFormat ?? 'mp3';
      final fileName = '${_title.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), '_')}.$ext';
      final savePath = '${dir.path}/$fileName';

      await Dio().download(widget.result.url, savePath);

      if (!mounted) return;

      // 使用系统分享
      await Share.shareXFiles([XFile(savePath)]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.downloadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final url = widget.result.url;
    final hasUrl = url.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── 标题行 ───
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.result.displayLabel.isNotEmpty
                        ? widget.result.displayLabel
                        : widget.result.stemType,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            if (_dateStr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _dateStr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],

            // ─── 播放器区域（仅当前播放项展示） ───
            if (hasUrl)
              StreamBuilder<PlayerState>(
                stream: widget.audioService.playerStateStream,
                builder: (context, snapshot) {
                  final isThisPlaying =
                      widget.audioService.currentUrl == url;
                  if (!isThisPlaying) return const SizedBox.shrink();

                  final playing =
                      snapshot.data?.playing ?? false;

                  return Column(
                    children: [
                      const SizedBox(height: 12),
                      StreamBuilder<Duration>(
                        stream: widget.audioService.positionStream,
                        builder: (context, posSnap) {
                          final position = posSnap.data ?? Duration.zero;
                          final total =
                              widget.audioService.duration ?? Duration.zero;
                          final progress = total.inMilliseconds > 0
                              ? position.inMilliseconds /
                                  total.inMilliseconds
                              : 0.0;
                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: progress.clamp(0.0, 1.0),
                                  onChanged: (v) {
                                    if (total.inMilliseconds > 0) {
                                      widget.audioService.seek(Duration(
                                          milliseconds:
                                              (v * total.inMilliseconds)
                                                  .toInt()));
                                    }
                                  },
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(position),
                                        style: theme.textTheme.bodySmall),
                                    Text(_formatDuration(total),
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              size: 36,
                              color: theme.colorScheme.primary,
                            ),
                            onPressed: () {
                              if (playing) {
                                widget.audioService.pause();
                              } else {
                                widget.audioService.resume();
                              }
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.stop_circle_outlined,
                                size: 28,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5)),
                            onPressed: () => widget.audioService.stop(),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),

            // ─── 操作按钮 ───
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (hasUrl)
                  TextButton.icon(
                    onPressed: _playAudio,
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: Text(l10n.historyPlay,
                        style: const TextStyle(fontSize: 12)),
                  ),
                if (hasUrl)
                  _downloading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton.icon(
                          onPressed: _downloadAndShare,
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: Text(l10n.historyDownload,
                              style: const TextStyle(fontSize: 12)),
                        ),
                TextButton.icon(
                  onPressed: widget.onDelete,
                  icon:
                      Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  label: Text(l10n.historyDelete,
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
