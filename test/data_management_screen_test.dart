import 'dart:async';
import 'dart:convert';

import 'package:feed_reminder/models/backup_document.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/feed_provider.dart';
import 'package:feed_reminder/screens/data_management_screen.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:feed_reminder/services/backup_service.dart';
import 'package:feed_reminder/services/data_file_service.dart';
import 'package:feed_reminder/services/notification_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:feed_reminder/theme/app_theme.dart';
import 'package:feed_reminder/utils/constants.dart';
import 'package:feed_reminder/widgets/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudio extends AudioService {
  @override
  Future<void> playReminder({bool loop = true}) async {}
  @override
  Future<void> stopReminder() async {}
}

class _SilentNotifications extends NotificationService {
  @override
  Future<void> showFeedReminder({bool playSound = true}) async {}
  @override
  Future<void> scheduleFeedReminder(
    DateTime when, {
    bool playSound = true,
  }) async {}
  @override
  Future<void> cancelAll() async {}
}

class _Storage extends StorageService {
  bool failWrites = false;
  int saves = 0;
  Completer<void>? pendingWrite;
  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    saves++;
    await pendingWrite?.future;
    if (failWrites) throw StateError('full');
    await super.saveFeedState(records);
  }
}

class _Files extends DataFileService {
  DataFile? file;
  Object? failure;
  String? savedContent;
  String? savedExtension;
  Completer<bool>? pendingSave;
  bool saved = true;
  int picks = 0;
  int writes = 0;

  @override
  Future<DataFile?> pickBackup() async {
    picks++;
    if (failure != null) throw failure!;
    return file;
  }

  @override
  Future<bool> saveFile({
    required String suggestedName,
    required String content,
    required String extension,
    required String mimeType,
  }) async {
    writes++;
    savedContent = content;
    savedExtension = extension;
    if (failure != null) throw failure!;
    return pendingSave == null ? saved : await pendingSave!.future;
  }
}

final _now = DateTime(2026, 10, 3, 12);
final _local = FeedRecord(
  id: 'local',
  time: _now.subtract(const Duration(hours: 4)),
  milkAmountMl: 100,
);
final _new = FeedRecord(
  id: 'new',
  time: _now.subtract(const Duration(hours: 1)),
  milkAmountMl: 120,
);

Future<FeedProvider> _provider({
  List<FeedRecord>? records,
  _Storage? storage,
  bool corrupt = false,
}) async {
  SharedPreferences.setMockInitialValues({
    StorageKeys.feedHistory: corrupt
        ? '{bad'
        : jsonEncode((records ?? [_local]).map((r) => r.toJson()).toList()),
  });
  final provider = FeedProvider(
    storage: storage ?? _Storage(),
    audioService: _SilentAudio(),
    notificationService: _SilentNotifications(),
    startTimer: false,
    clock: () => _now,
  );
  await provider.ready;
  addTearDown(provider.dispose);
  return provider;
}

Widget _app(
  FeedProvider provider,
  _Files files, {
  double scale = 1,
  bool dark = false,
  Widget? home,
}) => ChangeNotifierProvider.value(
  value: provider,
  child: MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home ?? DataManagementScreen(fileService: files),
  ),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Widget _dataManagementEntry(_Files files) => Scaffold(
  body: Builder(
    builder: (context) => AppButton(
      key: const ValueKey('open-data-management'),
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DataManagementScreen(fileService: files),
        ),
      ),
      child: const Text('打开数据管理'),
    ),
  ),
);

void main() {
  testWidgets('picker cancellation is quiet and corrupt import never writes', (
    tester,
  ) async {
    final storage = _Storage();
    final provider = await _provider(storage: storage);
    final files = _Files();
    await tester.pumpWidget(_app(provider, files));
    await _tap(tester, 'backup-import-json');
    expect(find.text('恢复前确认'), findsNothing);
    expect(find.byKey(const ValueKey('app-notice-dialog')), findsNothing);
    files.file = const DataFile(name: 'broken.json', content: '{bad');
    await _tap(tester, 'backup-import-json');
    expect(find.text('文件内容损坏，请选择完整的 JSON 备份'), findsOneWidget);
    expect(storage.saves, 0);
    expect(provider.feedHistory.single.id, 'local');
  });

  testWidgets(
    'preview merges once, preserves local conflicts and confirms actual added count',
    (tester) async {
      final storage = _Storage();
      final provider = await _provider(storage: storage);
      final files = _Files()
        ..file = DataFile(
          name: 'backup.json',
          content: const BackupService().encodeJson([
            FeedRecord(id: 'local', time: _local.time, milkAmountMl: 180),
            _new,
          ], now: _now),
        );
      await tester.pumpWidget(_app(provider, files));
      await _tap(tester, 'backup-import-json');
      expect(find.text('将新增 1 条'), findsOneWidget);
      expect(find.text('重复 0 条 · 冲突 1 条'), findsOneWidget);
      expect(storage.saves, 0);
      await _tap(tester, 'backup-confirm-restore');
      expect(provider.feedHistory.length, 2);
      expect(provider.feedHistory.last.milkAmountMl, 100);
      expect(storage.saves, 1);
      expect(find.text('恢复完成，新增 1 条记录。现有 2 条。'), findsOneWidget);
      await _tap(tester, 'backup-import-json');
      expect(find.text('没有需要新增的记录。'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('backup-confirm-restore')),
        findsNothing,
      );
      expect(storage.saves, 1);
    },
  );

  testWidgets('restore failure retains preview and history then retries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _Storage()..failWrites = true;
    final provider = await _provider(storage: storage);
    final files = _Files()
      ..file = DataFile(
        name:
            'naidianji_backup_20261003_120000_from_previous_device_'
            'complete_feeding_history.json',
        content: const BackupService().encodeJson([_new], now: _now),
      );
    await tester.pumpWidget(_app(provider, files, scale: 2));
    await _tap(tester, 'backup-import-json');
    await _tap(tester, 'backup-confirm-restore');
    final error = find.byKey(const ValueKey('backup-restore-error'));
    final body = find.ancestor(of: error, matching: find.byType(Scrollable));
    expect(error.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(error).top,
      greaterThanOrEqualTo(tester.getRect(body).top - 1),
    );
    expect(
      tester.getRect(error).bottom,
      lessThanOrEqualTo(tester.getRect(body).bottom + 1),
    );
    expect(provider.feedHistory.single.id, 'local');
    expect(find.text('恢复前确认'), findsOneWidget);
    storage.failWrites = false;
    await _tap(tester, 'backup-confirm-restore');
    expect(provider.feedHistory.length, 2);
    expect(files.picks, 1);
    final status = find.byKey(const ValueKey('data-management-status'));
    final page = find.ancestor(of: status, matching: find.byType(Scrollable));
    expect(find.text('恢复前确认'), findsNothing);
    expect(find.text('恢复完成，新增 1 条记录。现有 2 条。'), findsOneWidget);
    expect(status.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(status).top,
      greaterThanOrEqualTo(tester.getRect(page).top - 1),
    );
    expect(
      tester.getRect(status).bottom,
      lessThanOrEqualTo(tester.getRect(page).bottom + 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid preview cancellation leaves data management open', (
    tester,
  ) async {
    final storage = _Storage();
    final provider = await _provider(storage: storage);
    final files = _Files()
      ..file = DataFile(
        name: 'backup.json',
        content: const BackupService().encodeJson([_new], now: _now),
      );
    await tester.pumpWidget(
      _app(provider, files, home: _dataManagementEntry(files)),
    );
    await _tap(tester, 'open-data-management');
    await _tap(tester, 'backup-import-json');
    final cancel = tester
        .widget<AppButton>(find.byKey(const ValueKey('backup-preview-cancel')))
        .onPressed!;
    cancel();
    cancel();
    await tester.pumpAndSettle();

    expect(find.text('恢复前确认'), findsNothing);
    expect(find.byType(DataManagementScreen), findsOneWidget);
    expect(provider.feedHistory.single.id, 'local');
    expect(storage.saves, 0);
    expect(tester.takeException(), isNull);
    await _tap(tester, 'backup-import-json');
    expect(find.text('恢复前确认'), findsOneWidget);
  });

  testWidgets(
    'rapid restore activation merges once and blocks stale cancel until saved',
    (tester) async {
      final storage = _Storage()..pendingWrite = Completer<void>();
      final provider = await _provider(storage: storage);
      final files = _Files()
        ..file = DataFile(
          name: 'backup.json',
          content: const BackupService().encodeJson([_new], now: _now),
        );
      await tester.pumpWidget(
        _app(provider, files, home: _dataManagementEntry(files)),
      );
      await _tap(tester, 'open-data-management');
      await _tap(tester, 'backup-import-json');
      final confirm = tester
          .widget<AppButton>(
            find.byKey(const ValueKey('backup-confirm-restore')),
          )
          .onPressed!;
      final cancel = tester
          .widget<AppButton>(
            find.byKey(const ValueKey('backup-preview-cancel')),
          )
          .onPressed!;
      confirm();
      confirm();
      cancel();
      await tester.pump();
      expect(find.text('恢复前确认'), findsOneWidget);
      expect(provider.feedHistory.single.id, 'local');
      expect(storage.saves, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('恢复前确认'), findsOneWidget);

      storage.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(provider.feedHistory, hasLength(2));
      expect(storage.saves, 1);
      expect(find.text('恢复完成，新增 1 条记录。现有 2 条。'), findsOneWidget);
      expect(find.text('恢复前确认'), findsNothing);
      expect(find.byType(DataManagementScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('capacity is refreshed after history changes during preview', (
    tester,
  ) async {
    final storage = _Storage();
    final local = List.generate(
      BackupDocument.maxRecords - 1,
      (index) => FeedRecord(id: 'local-$index', time: _local.time),
    );
    final provider = await _provider(records: local, storage: storage);
    final files = _Files()
      ..file = DataFile(
        name: 'one-more.json',
        content: const BackupService().encodeJson([_new], now: _now),
      );
    await tester.pumpWidget(_app(provider, files));
    await _tap(tester, 'backup-import-json');
    final confirm = find.byKey(const ValueKey('backup-confirm-restore'));
    expect(tester.widget<AppButton>(confirm).onPressed, isNotNull);
    await provider.addFeedRecordWithTime(_now, milkAmountMl: 90);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-capacity-error')), findsOneWidget);
    expect(find.textContaining('恢复后超过备份容量（50,000 条）'), findsOneWidget);
    expect(tester.widget<AppButton>(confirm).onPressed, isNull);
    expect(storage.saves, 1);
    expect(provider.feedHistory, hasLength(BackupDocument.maxRecords));
    await _tap(tester, 'backup-preview-cancel');
    expect(find.text('恢复前确认'), findsNothing);
    expect(storage.saves, 1);
  });

  testWidgets(
    'export reports success only after file write and prevents duplicate actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = await _provider();
      final files = _Files()..pendingSave = Completer<bool>();
      await tester.pumpWidget(_app(provider, files, scale: 2));
      final export = find.byKey(const ValueKey('backup-export-json'));
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('data-management-status')),
        findsNothing,
      );
      expect(tester.widget<AppButton>(export).onPressed, isNull);
      expect(files.writes, 1);
      expect(
        const BackupService().decodeJson(files.savedContent!).records.single.id,
        'local',
      );
      // Completion may arrive after the user or route restoration returns
      // the page to its top, with the status section still below the viewport.
      final pageScroll = find.descendant(
        of: find.byKey(const PageStorageKey('data-management-scroll')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(pageScroll).position;
      position.jumpTo(0);
      await tester.pump();
      expect(position.pixels, 0);
      files.pendingSave!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('备份已保存，可用于恢复喂奶记录。'), findsOneWidget);
      final status = find.byKey(const ValueKey('data-management-status'));
      final page = find.ancestor(of: status, matching: find.byType(Scrollable));
      expect(status.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(status).top,
        greaterThanOrEqualTo(tester.getRect(page).top - 1),
      );
      expect(
        tester.getRect(status).bottom,
        lessThanOrEqualTo(tester.getRect(page).bottom + 1),
      );
      files.pendingSave = null;
      files.saved = false;
      await _tap(tester, 'backup-export-csv');
      expect(files.savedExtension, 'csv');
      expect(files.savedContent, startsWith('\uFEFF'));
      expect(
        find.byKey(const ValueKey('data-management-status')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'pending file operation blocks system and page back until picker completes',
    (tester) async {
      final provider = await _provider();
      final files = _Files()..pendingSave = Completer<bool>();
      await tester.pumpWidget(
        _app(
          provider,
          files,
          home: Scaffold(
            body: Builder(
              builder: (context) => AppButton(
                key: const ValueKey('open-data-management'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => DataManagementScreen(fileService: files),
                  ),
                ),
                child: const Text('打开数据管理'),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, 'open-data-management');
      final export = find.byKey(const ValueKey('backup-export-json'));
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pump();
      final back = find.byKey(const ValueKey('data-management-back'));
      expect(tester.widget<AppButton>(back).onPressed, isNull);
      expect(files.writes, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(DataManagementScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('open-data-management')), findsNothing);
      files.pendingSave!.complete(false);
      await tester.pumpAndSettle();
      expect(tester.widget<AppButton>(back).onPressed, isNotNull);
      await _tap(tester, 'data-management-back');
      expect(find.byType(DataManagementScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('open-data-management')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid page back returns to its caller only once', (
    tester,
  ) async {
    final provider = await _provider();
    final files = _Files();
    await tester.pumpWidget(
      _app(provider, files, home: _dataManagementEntry(files)),
    );
    await _tap(tester, 'open-data-management');
    final back = tester
        .widget<AppButton>(find.byKey(const ValueKey('data-management-back')))
        .onPressed!;
    back();
    back();
    await tester.pumpAndSettle();
    expect(find.byType(DataManagementScreen), findsNothing);
    expect(find.byKey(const ValueKey('open-data-management')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unreadable local history cannot be exported as an empty backup',
    (tester) async {
      final provider = await _provider(corrupt: true);
      final files = _Files();
      await tester.pumpWidget(_app(provider, files));
      expect(provider.isAvailable, isFalse);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('backup-export-json')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('backup-import-json')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('记录暂时无法读取'), findsOneWidget);
      final retry = find.byKey(const ValueKey('retry-feed-loading'));
      expect(retry, findsOneWidget);
      expect(files.writes, 0);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageKeys.feedHistory,
        jsonEncode([_local.toJson()]),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(provider.isAvailable, isTrue);
      expect(find.text('本机共 1 条记录'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('backup-export-json')))
            .onPressed,
        isNotNull,
      );
    },
  );

  for (final size in [const Size(320, 640), const Size(700, 320)]) {
    testWidgets('page and restore preview scroll at 2x text $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = await _provider();
      final files = _Files()
        ..file = DataFile(
          name: 'naidianji_backup_20261003_120000.json',
          content: const BackupService().encodeJson([_new], now: _now),
        );
      await tester.pumpWidget(_app(provider, files, scale: 2, dark: true));
      await _tap(tester, 'backup-import-json');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'backup-preview-cancel');
      await _tap(tester, 'backup-export-csv');
      expect(tester.takeException(), isNull);
      expect(files.writes, 1);
    });
  }
}
