// 历史记录页面
// 合并展示：本地队列任务（上传中/处理中/失败）+ 远程已完成结果
// 远程结果按任务分组（与小程序一致）：同一首歌的分轨结果聚合到一张卡片
// 增加轮询机制：页面可见时每 5 秒查询 PendingTaskStore 中的任务状态
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../services/stem_api_service.dart';
import '../services/audio_player_service.dart';
import '../services/upload_task_queue.dart';
import '../services/pending_task_store.dart';
import '../models/stem_task.dart';
import '../widgets/waveform_bar.dart';

/// 将后端 stemType / type 映射到国际化标签
String localizedStemLabel(AppLocalizations l10n, String stemType, String type) {
  if (type == 'back') return l10n.stemLabelAccompaniment;
  switch (stemType) {
    case 'vocals':
      return l10n.stemLabelVocals;
    case 'voice_clean':
      return l10n.stemLabelVoiceClean;
    case 'drum':
      return l10n.stemLabelDrum;
    case 'bass':
      return l10n.stemLabelBass;
    case 'acoustic_guitar':
      return l10n.stemLabelAcousticGuitar;
    case 'electric_guitar':
      return l10n.stemLabelElectricGuitar;
    case 'piano':
      return l10n.stemLabelPiano;
    case 'synthesizer':
      return l10n.stemLabelSynthesizer;
    case 'strings':
      return l10n.stemLabelStrings;
    case 'wind':
      return l10n.stemLabelWind;
    default:
      return l10n.stemLabelOther;
  }
}

/// 历史分组：同一首歌的所有分轨结果
class _HistoryGroup {
  final String trackTitle;
  final String stemType;
  final String date; // yyyy-MM-dd
  final List<StemResultItem> items;

  _HistoryGroup({
    required this.trackTitle,
    required this.stemType,
    required this.date,
    required this.items,
  });
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with WidgetsBindingObserver {
  final _stemApi = StemApiService();
  final _audio = AudioPlayerService.instance;
  final _queue = UploadTaskQueue.instance;
  final _pendingStore = PendingTaskStore.instance;

  List<_HistoryGroup> _groups = [];
  final bool _loading = false;

  /// 分页状态
  int _currentPage = 1;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// 所有已加载的原始结果（用于分组）
  List<StemResultItem> _allResults = [];

  /// 滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 轮询定时器
  Timer? _pollTimer;

  /// 避免并发轮询
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _queue.tasksNotifier.addListener(_onQueueChanged);
    _loadHistory();
    _startPollingIfNeeded();
  }

  @override
  void dispose() {
    _stopPolling();
    _queue.tasksNotifier.removeListener(_onQueueChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _audio.stop();
    super.dispose();
  }

  /// 监听上传队列变化：有任务完成时刷新远程历史
  final Set<String> _seenCompletedIds = {};

  void _onQueueChanged() {
    final tasks = _queue.tasks;
    bool hasNewCompletion = false;
    for (final t in tasks) {
      if (t.status == 'completed' && !_seenCompletedIds.contains(t.stemTaskId)) {
        _seenCompletedIds.add(t.stemTaskId);
        hasNewCompletion = true;
      }
    }
    if (hasNewCompletion && mounted) {
      debugPrint('[HistoryPage] 🔄 检测到队列任务完成，刷新历史');
      _loadHistory(silent: true);
    }
  }

  /// 监听滚动到底部，加载下一页
  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore &&
        !_loading) {
      _loadMore();
    }
  }

  /// App 前后台切换时控制轮询
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPollingIfNeeded();
      _loadHistory(silent: true); // 回到前台时静默刷新，不显示 loading
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  /// 仅在有待处理任务时启动轮询
  void _startPollingIfNeeded() {
    if (_pendingStore.tasks.isEmpty) {
      debugPrint('[HistoryPage] 📭 无待处理任务，跳过轮询');
      return;
    }
    _stopPolling();
    _pollPendingTasks();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollPendingTasks();
    });
    debugPrint('[HistoryPage] ✅ 轮询已启动 (${_pendingStore.tasks.length} 个待处理)');
  }

  void _stopPolling() {
    if (_pollTimer == null) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('[HistoryPage] ⏹ 轮询已停止');
  }

  /// 轮询 PendingTaskStore 中所有待处理任务的服务端状态
  Future<void> _pollPendingTasks() async {
    if (_polling) return;
    final pending = _pendingStore.tasks;
    if (pending.isEmpty) return;

    _polling = true;
    bool anyCompleted = false;

    for (final task in List.of(pending)) {
      try {
        // 如果这个任务已在 UploadTaskQueue 内部轮询中，跳过避免双重轮询
        if (_queue.isInternallyProcessing(task.stemTaskId)) {
          debugPrint('[HistoryPage] ⏭ 跳过内部轮询中的任务: ${task.stemTaskId}');
          continue;
        }

        final data = await _stemApi.getTaskDetail(task.stemTaskId);
        final status = (data['status'] ?? '').toString();
        final progress = data['progress'];
        debugPrint(
            '[HistoryPage] 轮询 ${task.stemTaskId}: status=$status, progress=$progress');

        // 同步进度到队列任务（补偿 Dart 后台暂停期间丢失的进度更新）
        if (progress != null) {
          final queueProgress = 50 + ((progress as num).toInt() * 0.5).floor();
          _queue.updateProgressFromPoll(task.stemTaskId, queueProgress);
        }

        if (status == 'completed' || status == 'failed' || status == 'error') {
          await _pendingStore.removeTask(task.stemTaskId);
          anyCompleted = true;

          // 同步最终状态到队列
          if (status == 'completed') {
            _queue.markCompleted(task.stemTaskId);
          } else {
            _queue.markFailed(task.stemTaskId, data['error']?.toString() ?? 'error_processing_failed');
          }
        }
      } catch (e) {
        debugPrint('[HistoryPage] 轮询异常: ${task.stemTaskId}, $e');
      }
    }

    // 有任务完成时刷新远程历史列表
    if (anyCompleted && mounted) {
      await _loadHistory();
    }
    _polling = false;
  }

  /// 将扁平结果列表按 trackTitle + stemType + 日期 分组
  List<_HistoryGroup> _groupResults(List<StemResultItem> results) {
    final Map<String, _HistoryGroup> map = {};

    for (final item in results) {
      final title = item.trackTitle ?? '';
      final date =
          (item.createdAt != null && item.createdAt!.length >= 10)
              ? item.createdAt!.substring(0, 10)
              : '';
      final key = '$title|${item.stemType}|$date';

      if (map.containsKey(key)) {
        map[key]!.items.add(item);
      } else {
        map[key] = _HistoryGroup(
          trackTitle: title,
          stemType: item.stemType,
          date: date,
          items: [item],
        );
      }
    }

    return map.values.toList();
  }

  /// 加载历史记录（首次加载 / 下拉刷新 / 静默刷新）
  Future<void> _loadHistory({bool silent = false}) async {
    _currentPage = 1;
    final results = await _stemApi.getHistory(page: 1, pageSize: _pageSize);

    if (mounted) {
      setState(() {
        _allResults = results;
        _groups = _groupResults(results);
        _hasMore = results.length >= _pageSize;
      });
    }
  }

  /// 加载更多（下一页）
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    final nextPage = _currentPage + 1;
    final results = await _stemApi.getHistory(page: nextPage, pageSize: _pageSize);

    if (mounted) {
      setState(() {
        _currentPage = nextPage;
        _allResults.addAll(results);
        _groups = _groupResults(_allResults);
        _hasMore = results.length >= _pageSize;
        _loadingMore = false;
      });
      debugPrint('[HistoryPage] 📄 加载第 $nextPage 页，获取 ${results.length} 条，'
          '总计 ${_allResults.length} 条，hasMore=$_hasMore');
    }
  }

  /// 删除整组结果
  Future<void> _deleteGroup(_HistoryGroup group) async {
    for (final item in group.items) {
      await _stemApi.deleteResult(item.id);
    }
    if (mounted) {
      setState(() {
        _allResults.removeWhere(
            (r) => group.items.any((gi) => gi.id == r.id));
        _groups.remove(group);
      });
    }
  }

  /// 删除单条子轨道
  Future<void> _deleteSingleItem(_HistoryGroup group, StemResultItem item) async {
    final ok = await _stemApi.deleteResult(item.id);
    if (!ok || !mounted) return;
    setState(() {
      _allResults.removeWhere((r) => r.id == item.id);
      group.items.remove(item);
      if (group.items.isEmpty) {
        _groups.remove(group);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: RefreshIndicator(
              onRefresh: _loadHistory,
              child: ValueListenableBuilder<List<StemTask>>(
                valueListenable: _queue.tasksNotifier,
                builder: (context, queueTasks, _) {
                  // 过滤掉已完成的队列任务（它们会出现在远程历史中）
                  final activeTasks =
                      queueTasks.where((t) => !t.isCompleted).toList();
                  final totalCount = activeTasks.length + _groups.length;

                  if (totalCount == 0) {
                    return ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [_buildEmpty(context)],
                    );
                  }

                  // +1 用于底部加载更多指示器
                  final itemCount = totalCount + 1;

                  return ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
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

                      // 底部加载指示器
                      if (i >= activeTasks.length + _groups.length) {
                        return _buildFooter(l10n);
                      }

                      // 远程历史（分组卡片）
                      final gi = i - activeTasks.length;
                      return _GroupedResultCard(
                        group: _groups[gi],
                        audioService: _audio,
                        onDeleteGroup: () => _deleteGroup(_groups[gi]),
                        onDeleteItem: (item) =>
                            _deleteSingleItem(_groups[gi], item),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

  /// 底部加载更多指示器 / 已全部加载提示
  Widget _buildFooter(AppLocalizations l10n) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '— ${l10n.historyAllLoaded} —',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.35),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
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
    );
  }
}

// ──────────────────────────────────────────────
// 队列任务卡片（排队 / 上传中 / 处理中 / 失败）
// Flutter Expert: 动画 + 渐变进度条 + 状态过渡
// ──────────────────────────────────────────────
class _QueueTaskCard extends StatefulWidget {
  final StemTask task;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _QueueTaskCard({
    required this.task,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  State<_QueueTaskCard> createState() => _QueueTaskCardState();
}

class _QueueTaskCardState extends State<_QueueTaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant _QueueTaskCard old) {
    super.didUpdateWidget(old);
    if (old.task.status != widget.task.status) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    final isActive = widget.task.status == 'processing' ||
        widget.task.status == 'uploading';
    if (isActive) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final isFailed = widget.task.isFailed;
    final isProcessing = widget.task.status == 'processing';
    final isUploading = widget.task.status == 'uploading';
    final isQueued = widget.task.status == 'queued';
    final isActive = isProcessing || isUploading;

    // 状态颜色
    final Color statusColor;
    if (isFailed) {
      statusColor = Colors.red;
    } else if (isQueued) {
      statusColor = Colors.orange;
    } else {
      statusColor = theme.colorScheme.primary;
    }

    // 状态文本
    final String statusText;
    if (isUploading) {
      statusText = l10n.historyStatusUploading;
    } else if (isProcessing) {
      statusText = l10n.historyStatusProcessing;
    } else if (isFailed) {
      statusText = l10n.historyStatusFailed;
    } else if (isQueued) {
      statusText = l10n.historyStatusQueued;
    } else {
      statusText = widget.task.status;
    }

    // 状态图标
    final IconData statusIcon;
    if (isUploading) {
      statusIcon = Icons.cloud_upload_outlined;
    } else if (isProcessing) {
      statusIcon = Icons.auto_awesome;
    } else if (isFailed) {
      statusIcon = Icons.error_outline;
    } else if (isQueued) {
      statusIcon = Icons.hourglass_top;
    } else {
      statusIcon = Icons.check_circle_outline;
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseOpacity = isActive
            ? 0.04 + 0.04 * _pulseController.value
            : 0.0;

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: isFailed ? 1 : 2,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: isActive
                  ? Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                      width: 1,
                    )
                  : null,
              gradient: isActive
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        statusColor.withValues(alpha: pulseOpacity),
                        Colors.transparent,
                      ],
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
                  Row(
                    children: [
                      // 状态图标 + 动画
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          statusIcon,
                          key: ValueKey(statusIcon),
                          size: 20,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 标题
                      Expanded(
                        child: Text(
                          widget.task.trackTitle.isNotEmpty
                              ? widget.task.trackTitle
                              : widget.task.stem,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 分轨类型标签
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.task.stem,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 状态标签
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
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
                  if (!isFailed && !isQueued) ...[
                    const SizedBox(height: 14),
                    _AnimatedProgressBar(
                      progress: widget.task.progress / 100,
                      color: statusColor,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          isUploading
                              ? l10n.historyStatusUploading
                              : l10n.historyStatusProcessing,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${widget.task.progress}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 排队提示
                  if (isQueued) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.historyStatusQueued,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 错误信息
                  if (isFailed && widget.task.errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Colors.red),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              UploadTaskQueue.localizeError(
                                  widget.task.errorMessage, l10n),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.red, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // 操作按钮
                  if (isFailed) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: widget.onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text(l10n.historyRetry,
                              style: const TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: widget.onRemove,
                          icon: Icon(Icons.close, size: 16,
                              color: theme.colorScheme.outline),
                          label: Text(l10n.historyDelete,
                              style: TextStyle(
                                  color: theme.colorScheme.outline,
                                  fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            side: BorderSide(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.3)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 带动画的渐变进度条
class _AnimatedProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _AnimatedProgressBar({
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.7),
                      color,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 分组结果卡片（与小程序对齐）
// 一张卡片 = 一个分离任务 = 多条子轨道
// ──────────────────────────────────────────────
class _GroupedResultCard extends StatefulWidget {
  final _HistoryGroup group;
  final AudioPlayerService audioService;
  final VoidCallback onDeleteGroup;
  final void Function(StemResultItem item) onDeleteItem;

  const _GroupedResultCard({
    required this.group,
    required this.audioService,
    required this.onDeleteGroup,
    required this.onDeleteItem,
  });

  @override
  State<_GroupedResultCard> createState() => _GroupedResultCardState();
}

class _GroupedResultCardState extends State<_GroupedResultCard> {
  bool _expanded = false;

  /// 显示标题：优先 trackTitle，否则 stemType
  String get _title {
    final t = widget.group.trackTitle;
    return t.isNotEmpty ? t : widget.group.stemType;
  }

  /// 分离类型标签：使用国际化映射
  String _typeLabel(AppLocalizations l10n) {
    final first = widget.group.items.first;
    return localizedStemLabel(l10n, first.stemType, first.type);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final trackCount = widget.group.items.length;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── 标题行：歌曲名 + 展开/收起箭头 ───
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题 + 副标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.historyTrackCount(trackCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 展开/收起箭头（绿色）
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),

              // ─── 展开内容 ───
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── 类型标签 ───
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _typeLabel(l10n),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ─── 子轨道列表 ───
                      ...widget.group.items.map((item) => _TrackRow(
                            result: item,
                            audioService: widget.audioService,
                            onDeleteItem: () => widget.onDeleteItem(item),
                          )),
                    ],
                  ),
                ),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 单条子轨道行（嵌入分组卡片内）
// 布局：播放按钮 | 名称 | 分享 | 删除
// 下方始终显示进度条 + 时间
// ──────────────────────────────────────────────
class _TrackRow extends StatefulWidget {
  final StemResultItem result;
  final AudioPlayerService audioService;
  final VoidCallback onDeleteItem;

  const _TrackRow({
    required this.result,
    required this.audioService,
    required this.onDeleteItem,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _downloading = false;

  /// 显示名称：使用国际化映射
  String _label(AppLocalizations l10n) {
    return localizedStemLabel(l10n, widget.result.stemType, widget.result.type);
  }

  Future<void> _playAudio() async {
    final url = widget.result.url;
    if (url.isEmpty) return;
    try {
      await widget.audioService.play(url);
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
    final url = widget.result.url;
    if (url.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _downloading = true);

    try {
      final dir = await getTemporaryDirectory();
      final ext = widget.result.outputFormat ?? 'mp3';
      final safeName =
          _label(l10n).replaceAll(RegExp('[^\\w\u4e00-\u9fff]'), '_');
      final fileName = '$safeName.$ext';
      final savePath = '${dir.path}/$fileName';

      debugPrint('[Share] 开始下载: $url -> $savePath');

      await Dio().download(
        url,
        savePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      debugPrint('[Share] 下载完成, 准备分享');

      if (!mounted) return;

      // iPad 上必须提供 sharePositionOrigin，否则会报 PlatformException
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      await Share.shareXFiles(
        [XFile(savePath)],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      debugPrint('[Share] 下载/分享失败: $e');
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
    final url = widget.result.url;
    final hasUrl = url.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          // ─── 顶部行：播放 | 名称 | 分享 | 删除 ───
          Row(
            children: [
              // 播放/暂停按钮
              if (hasUrl)
              ValueListenableBuilder<String?>(
                  valueListenable: widget.audioService.currentUrlNotifier,
                  builder: (context, currentUrl, _) {
                    return StreamBuilder<PlayerState>(
                      stream: widget.audioService.playerStateStream,
                      builder: (context, snapshot) {
                        final isThis = currentUrl == url;
                        final playing =
                            isThis && (snapshot.data?.playing ?? false);
                        return GestureDetector(
                          onTap: () {
                            if (playing) {
                              widget.audioService.pause();
                            } else if (isThis) {
                              widget.audioService.resume();
                            } else {
                              _playAudio();
                            }
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              size: 20,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

              const SizedBox(width: 10),

              // 轨道名称
              Expanded(
                child: Text(
                  _label(AppLocalizations.of(context)!),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 分享按钮
              if (hasUrl)
                _downloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: _downloadAndShare,
                        icon: Icon(Icons.share_outlined,
                            size: 22,
                            color: theme.colorScheme.primary),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        tooltip: AppLocalizations.of(context)!.share,
                      ),

              // 删除按钮
              IconButton(
                onPressed: () async {
                  final l10n = AppLocalizations.of(context)!;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.historyDelete),
                      content: Text(l10n.historyDeleteConfirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.confirm,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    widget.onDeleteItem();
                  }
                },
                icon: Icon(Icons.delete_outline,
                    size: 22,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.4)),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: AppLocalizations.of(context)!.historyDelete,
              ),
            ],
          ),

          // ─── 波形进度条 + 时间（始终显示） ───
          if (hasUrl)
            ValueListenableBuilder<String?>(
              valueListenable: widget.audioService.currentUrlNotifier,
              builder: (context, currentUrl, _) {
                return StreamBuilder<PlayerState>(
                  stream: widget.audioService.playerStateStream,
                  builder: (context, _) {
                    final isThis = currentUrl == url;
                return StreamBuilder<Duration>(
                  stream: widget.audioService.positionStream,
                  builder: (context, posSnap) {
                    final position =
                        isThis ? (posSnap.data ?? Duration.zero) : Duration.zero;
                    final total = isThis
                        ? (widget.audioService.duration ?? Duration.zero)
                        : Duration.zero;
                    final progress = total.inMilliseconds > 0
                        ? position.inMilliseconds / total.inMilliseconds
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 波形可视化
                          WaveformBar(
                            url: url,
                            isActive: isThis,
                            progress: progress,
                            currentTimeText: isThis ? _fmt(position) : null,
                            height: 40,
                            onSeek: isThis
                                ? (v) {
                                    if (total.inMilliseconds > 0) {
                                      widget.audioService.seek(Duration(
                                          milliseconds:
                                              (v * total.inMilliseconds)
                                                  .toInt()));
                                    }
                                  }
                                : null,
                          ),
                          const SizedBox(height: 4),
                          // 时间标签
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmt(position),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                total.inMilliseconds > 0 ? _fmt(total) : '--:--',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
              },
            ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
