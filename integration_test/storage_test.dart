import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/providers/settings_provider.dart';
import 'package:feed_reminder/repositories/feed_repository.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Use the real native preferences plugin, isolated from the user's keys.
const _testPrefix = 'feed_reminder.integration.storage.';

Future<StorageService> _reopenStorage() async {
  SharedPreferences.resetStatic();
  SharedPreferences.setPrefix(_testPrefix);
  final storage = StorageService();
  await storage.init();
  return storage;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await _reopenStorage();
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      await prefs.remove(key);
    }
  });

  tearDown(() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      await prefs.remove(key);
    }
  });

  testWidgets('native storage reload preserves large history and settings', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 27, 15);
    final original = FeedRepository.normalize([
      for (var index = 0; index < 240; index++)
        FeedRecord(
          id: 'native-$index',
          time: now.subtract(Duration(minutes: index * 90)),
        ),
    ]);
    final storage = StorageService();
    await storage.saveFeedState(original);
    await storage.setAcknowledgedFeedTime(now);
    final settings = SettingsProvider(storage: storage);
    await settings.ready;
    await settings.updateSettings(
      themeMode: ThemeMode.dark,
      feedIntervalMinutes: 95,
      nightModeEnabled: true,
      nightStartTime: '21:30',
      nightEndTime: '06:15',
      soundEnabled: false,
      soundLoopEnabled: false,
      burnInProtectionEnabled: false,
    );
    settings.dispose();

    // Discard the Dart cache so these reads must cross the platform channel.
    final reopened = await _reopenStorage();
    final repository = FeedRepository(reopened);
    await repository.load();
    expect(
      repository.records.map((r) => r.toJson()),
      original.map((r) => r.toJson()),
    );
    expect(await reopened.getAcknowledgedFeedTime(), now);
    final restored = SettingsProvider(storage: reopened);
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.isAvailable, isTrue);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.feedIntervalMinutes, 95);
    expect(restored.nightModeEnabled, isTrue);
    expect(restored.nightStartTime, '21:30');
    expect(restored.nightEndTime, '06:15');
    expect(restored.soundEnabled, isFalse);
    expect(restored.soundLoopEnabled, isFalse);
    expect(restored.burnInProtectionEnabled, isFalse);

    await repository.remove(repository.records.first);
    await repository.add(now.subtract(const Duration(days: 30)));
    final afterEdit = FeedRepository(await _reopenStorage());
    await afterEdit.load();
    expect(afterEdit.records, hasLength(240));
    expect(afterEdit.records.any((r) => r.id == 'native-0'), isFalse);
    expect(afterEdit.lastFeedTime, original[1].time);
    expect(afterEdit.records.last.time, now.subtract(const Duration(days: 30)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native legacy migration and deleting all records survive reload',
    (tester) async {
      final time = DateTime(2026, 9, 27, 12, 30);
      await StorageService().setLastFeedTime(time);
      final migrated = FeedRepository(await _reopenStorage());
      await migrated.load();
      expect(migrated.records, hasLength(1));
      expect(migrated.lastFeedTime, time);
      await migrated.remove(migrated.records.single);
      final empty = FeedRepository(await _reopenStorage());
      await empty.load();
      expect(empty.records, isEmpty);
      expect(empty.lastFeedTime, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
