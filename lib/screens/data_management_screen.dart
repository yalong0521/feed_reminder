import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/backup_document.dart';
import '../models/feed_record.dart';
import '../providers/feed_provider.dart';
import '../services/backup_service.dart';
import '../services/data_file_service.dart';
import '../theme/app_typography.dart';
import '../utils/constants.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_message_dialog.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_surface.dart';
import '../widgets/feed_load_failure.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key, this.fileService});

  final DataFileService? fileService;

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  static const _backup = BackupService();
  late final _files = widget.fileService ?? DataFileService();
  bool _busy = false;
  bool _previewOpen = false;
  String? _status;
  final _statusKey = GlobalKey();

  void _setStatus(String message) {
    setState(() => _status = message);
    _revealCompletedStatus();
  }

  void _revealCompletedStatus() {
    final message = _status;
    if (message == null || _busy || _previewOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _busy ||
          _previewOpen ||
          _status != message ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final statusContext = _statusKey.currentContext;
      if (statusContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          statusContext,
          alignment: 0,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: MediaQuery.disableAnimationsOf(statusContext)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        ),
      );
    });
  }

  Future<void> _export({required bool csv}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final provider = context.read<FeedProvider>();
      final now = provider.referenceTime;
      final content = csv
          ? _backup.encodeCsv(provider.feedHistory)
          : _backup.encodeJson(provider.feedHistory, now: now);
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}_'
          '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      final saved = await _files.saveFile(
        suggestedName:
            'naidianji_${csv ? 'records' : 'backup'}_$stamp.${csv ? 'csv' : 'json'}',
        content: content,
        extension: csv ? 'csv' : 'json',
        mimeType: csv ? 'text/csv' : 'application/json',
      );
      if (mounted && saved) {
        _setStatus(
          kIsWeb
              ? '${csv ? 'CSV' : '备份'}已交给浏览器下载，请在下载列表查看。'
              : csv
              ? 'CSV 已保存，可用表格软件打开。'
              : '备份已保存，可用于恢复喂奶记录。',
        );
      }
    } catch (error) {
      if (mounted) showAppNotice(context, _errorMessage(error, saving: true));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _revealCompletedStatus();
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final file = await _files.pickBackup();
      if (file == null || !mounted) return;
      final document = _backup.decodeJson(file.content);
      setState(() => _previewOpen = true);
      await _preview(file.name, document);
    } catch (error) {
      if (mounted) showAppNotice(context, _errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _previewOpen = false;
        });
        _revealCompletedStatus();
      }
    }
  }

  Future<void> _preview(String filename, BackupDocument document) async {
    final provider = context.read<FeedProvider>();
    final errorKey = GlobalKey();
    var saving = false;
    var closing = false;
    void close(BuildContext dialogContext) {
      if (closing || ModalRoute.of(dialogContext)?.isCurrent != true) return;
      closing = true;
      Navigator.of(dialogContext).pop();
    }

    String? error;
    List<FeedRecord>? checkedRecords;
    BackupImportPlan? checkedPlan;
    String? capacityError;
    final route = createAppMessageDialogRoute<void>(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AnimatedBuilder(
          animation: provider,
          builder: (context, _) {
            // Timer notifications do not change the immutable history.
            // Only re-encode the proposed merge when that history changes.
            if (!identical(checkedRecords, provider.feedHistory)) {
              checkedRecords = provider.feedHistory;
              checkedPlan = BackupImportPlan(
                document: document,
                localRecords: provider.feedHistory,
                now: provider.referenceTime,
              );
              capacityError = null;
              try {
                BackupDocument.mergeForRestore(
                  localRecords: provider.feedHistory,
                  incoming: document.records,
                );
              } on FormatException catch (failure) {
                capacityError = failure.message;
              }
            }
            final plan = checkedPlan!;
            final now = provider.referenceTime;
            final futureCount = document.records
                .where((record) => record.time.isAfter(now))
                .length;
            return PopScope(
              canPop: !saving,
              child: AppMessageDialog(
                title: '恢复前确认',
                icon: CupertinoIcons.doc_text_search,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(filename, style: AppTypography.label(context)),
                    const SizedBox(height: 8),
                    Text('备份时间：${_dateTime(document.createdAt)}'),
                    Text('记录范围：${_range(document.records)}'),
                    const SizedBox(height: 16),
                    Text('备份共 ${document.records.length} 条'),
                    Text('将新增 ${plan.addedCount} 条'),
                    Text(
                      '重复 ${plan.duplicateCount} 条 · 冲突 ${plan.conflictCount} 条',
                    ),
                    const SizedBox(height: 12),
                    const Text('重复记录会跳过，冲突记录保留本机版本。现有记录不会清空，设备设置保持不变。'),
                    if (futureCount > 0) ...[
                      const SizedBox(height: 12),
                      Text('含 $futureCount 条晚于当前时间的记录，将保留原时间；到达该时间后才计入统计。'),
                    ],
                    if (plan.addedCount == 0) ...[
                      const SizedBox(height: 12),
                      const Text('没有需要新增的记录。'),
                    ],
                    if (capacityError != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          capacityError!,
                          key: const ValueKey('backup-capacity-error'),
                          style: AppTypography.body(
                            context,
                          ).copyWith(color: AppPalette.of(context).alert),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        key: errorKey,
                        liveRegion: true,
                        child: Text(
                          error!,
                          key: const ValueKey('backup-restore-error'),
                          style: AppTypography.body(
                            context,
                          ).copyWith(color: AppPalette.of(context).alert),
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  AppButton(
                    key: const ValueKey('backup-preview-cancel'),
                    onPressed: saving
                        ? null
                        : () {
                            if (!saving) close(dialogContext);
                          },
                    child: Text(plan.addedCount == 0 ? '关闭' : '取消'),
                  ),
                  if (plan.addedCount > 0)
                    AppButton(
                      key: const ValueKey('backup-confirm-restore'),
                      filled: true,
                      onPressed:
                          saving || provider.isSaving || capacityError != null
                          ? null
                          : () async {
                              // Activation can repeat before disabled controls
                              // rebuild, including through accessibility actions.
                              if (saving ||
                                  closing ||
                                  provider.isSaving ||
                                  capacityError != null ||
                                  ModalRoute.of(dialogContext)?.isCurrent !=
                                      true) {
                                return;
                              }
                              updateDialog(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                final added = await provider.importFeedRecords(
                                  document.records,
                                );
                                if (dialogContext.mounted) {
                                  close(dialogContext);
                                }
                                if (mounted) {
                                  _setStatus(
                                    '恢复完成，新增 $added 条记录。现有 ${provider.feedHistory.length} 条。',
                                  );
                                }
                              } catch (failure) {
                                if (dialogContext.mounted) {
                                  updateDialog(() {
                                    saving = false;
                                    error = failure is FormatException
                                        ? failure.message
                                        : '恢复未完成，现有记录保持不变。请重试。';
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!dialogContext.mounted) return;
                                    final errorContext =
                                        errorKey.currentContext;
                                    if (errorContext == null) return;
                                    // A long preview can leave the new error
                                    // below the fixed confirmation buttons.
                                    unawaited(
                                      Scrollable.ensureVisible(
                                        errorContext,
                                        alignment: 1,
                                        alignmentPolicy:
                                            ScrollPositionAlignmentPolicy
                                                .keepVisibleAtEnd,
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              errorContext,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 180),
                                      ),
                                    );
                                  });
                                }
                              }
                            },
                      child: saving
                          ? const _ProgressLabel('正在恢复')
                          : Text('合并 ${plan.addedCount} 条记录'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push<void>(route);
    // Wait for the closing transition too, so completion feedback is revealed
    // after the preview has stopped covering the page.
    await route.completed;
  }

  @override
  Widget build(BuildContext context) {
    final records = context.select<FeedProvider, List<FeedRecord>>(
      (p) => p.feedHistory,
    );
    final initialized = context.select<FeedProvider, bool>(
      (p) => p.isInitialized,
    );
    final saving = context.select<FeedProvider, bool>((p) => p.isSaving);
    final available = context.select<FeedProvider, bool>((p) => p.isAvailable);
    final enabled = available && !saving && !_busy;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        body: AppBackdrop(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final padding = AppPageLayout.contentPadding(
                  constraints.maxWidth,
                );
                return SingleChildScrollView(
                  key: const PageStorageKey('data-management-scroll'),
                  padding: EdgeInsets.fromLTRB(padding, 8, padding, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppButton(
                        key: const ValueKey('data-management-back'),
                        surface: false,
                        compact: true,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        onPressed: _busy
                            ? null
                            : () {
                                if (!_busy &&
                                    ModalRoute.of(context)?.isCurrent == true) {
                                  Navigator.of(context).pop();
                                }
                              },
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.back, size: 18),
                            SizedBox(width: 6),
                            Text('返回设置'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppPageHeader(
                        title: '数据管理',
                        subtitle: '把每一餐的记录好好保存。',
                        compact: AppPageLayout.compact(context),
                      ),
                      const SizedBox(height: 24),
                      if (!initialized)
                        const _ProgressLabel('正在读取记录')
                      else if (!available)
                        const FeedLoadFailure()
                      else ...[
                        Text(
                          '本机共 ${records.length} 条记录',
                          style: AppTypography.sectionTitle(context),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _range(records),
                          style: AppTypography.supporting(context),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '备份仅包含喂奶记录。提醒、外观和授权设置保留在本机。',
                        style: AppTypography.supporting(context),
                      ),
                      if ((_busy && !_previewOpen) || _status != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          key: _statusKey,
                          liveRegion: true,
                          child: _busy
                              ? const _ProgressLabel('正在处理，请稍候')
                              : Text(
                                  _status!,
                                  key: const ValueKey('data-management-status'),
                                  style: AppTypography.body(context),
                                ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _ActionCard(
                        title: '备份记录',
                        description: '保存为 JSON 文件，换设备或重新安装后可用它恢复记录。',
                        icon: CupertinoIcons.archivebox,
                        button: AppButton(
                          key: const ValueKey('backup-export-json'),
                          filled: true,
                          onPressed: enabled ? () => _export(csv: false) : null,
                          child: const Text('保存备份'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ActionCard(
                        title: '从备份恢复',
                        description: '选择奶点记 JSON 备份，先查看预览，再合并新增记录。',
                        icon: CupertinoIcons.arrow_down_doc,
                        button: AppButton(
                          key: const ValueKey('backup-import-json'),
                          onPressed: enabled ? _restore : null,
                          child: const Text('选择备份'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ActionCard(
                        title: '导出 CSV',
                        description: '用表格软件阅读和整理。奶量未填写会标为“未记录”。CSV 不能用于恢复。',
                        icon: CupertinoIcons.table,
                        button: AppButton(
                          key: const ValueKey('backup-export-csv'),
                          onPressed: enabled ? () => _export(csv: true) : null,
                          child: const Text('导出表格'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static String _errorMessage(Object error, {bool saving = false}) {
    if (error is FormatException) return error.message;
    if (error is MissingPluginException || error is UnsupportedError) {
      return '此环境暂时无法打开系统文件选择器，请在已安装的应用中重试。';
    }
    if (error is PlatformException) {
      if (error.code.toLowerCase() == 'file_too_large') {
        return '文件超过 10 MiB，请选择较小的备份';
      }
      if (error.code == 'invalid_encoding') {
        return '文件不是有效的 UTF-8 备份';
      }
      if (error.code == 'ability_unavailable' ||
          error.code == 'file_picker_busy') {
        return '系统文件选择器暂不可用，请返回应用后重试。';
      }
    }
    return saving ? '文件未能保存。请检查可用空间和保存位置后重试。' : '无法读取这个文件。请确认文件可访问，再重新选择。';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${_two(local.month)}/${_two(local.day)}';
  }

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${_date(local)} ${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _range(List<FeedRecord> records) {
    if (records.isEmpty) return '暂无喂奶记录';
    var oldest = records.first.time;
    var newest = oldest;
    for (final record in records.skip(1)) {
      if (record.time.isBefore(oldest)) oldest = record.time;
      if (record.time.isAfter(newest)) newest = record.time;
    }
    return '${_date(oldest)} — ${_date(newest)}';
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.button,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget button;

  @override
  Widget build(BuildContext context) => AppSurface(
    radius: 24,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: 24,
                color: AppPalette.of(context).primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: AppTypography.sectionTitle(context)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(description, style: AppTypography.supporting(context)),
        const SizedBox(height: 18),
        button,
      ],
    ),
  );
}

class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CupertinoActivityIndicator(),
      const SizedBox(width: 10),
      Flexible(child: Text(label)),
    ],
  );
}
