import 'package:feed_reminder/models/backup_document.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/repositories/feed_repository.dart';
import 'package:feed_reminder/services/backup_service.dart';
import 'package:feed_reminder/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage extends StorageService {
  _MemoryStorage(this.saved);

  List<FeedRecord> saved;
  int writes = 0;

  @override
  Future<bool> hasFeedHistory() async => true;
  @override
  Future<List<FeedRecord>> getFeedHistory() async => List.of(saved);
  @override
  Future<void> saveFeedState(List<FeedRecord> records) async {
    writes++;
    saved = records;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 3);
  List<FeedRecord> records(
    int count, {
    int offset = 0,
    bool largeIds = false,
  }) => List.generate(
    count,
    (i) => FeedRecord(
      id: '${largeIds ? '奶' * 240 : 'record'}-${i + offset}',
      time: now,
      milkAmountMl: 120,
    ),
  );

  test(
    'two individually valid backups cannot exceed merged record capacity',
    () {
      final local = records(30000);
      final incoming = records(30000, offset: 30000);
      const service = BackupService();
      expect(
        service.decodeJson(service.encodeJson(local, now: now)).records,
        hasLength(30000),
      );
      expect(
        service.decodeJson(service.encodeJson(incoming, now: now)).records,
        hasLength(30000),
      );
      expect(
        () => BackupDocument.mergeForRestore(
          localRecords: local,
          incoming: incoming,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'reason',
            contains('恢复后超过备份容量（50,000 条）'),
          ),
        ),
      );
    },
  );

  test(
    'repository rejects merged byte overflow without changing memory or disk',
    () async {
      final local = records(7000, largeIds: true);
      final incoming = records(7000, offset: 7000, largeIds: true);
      const service = BackupService();
      expect(
        service.decodeJson(service.encodeJson(local, now: now)).records,
        hasLength(7000),
      );
      expect(
        service.decodeJson(service.encodeJson(incoming, now: now)).records,
        hasLength(7000),
      );
      final storage = _MemoryStorage(local);
      final repository = FeedRepository(storage);
      await repository.load();
      final before = repository.records;
      await expectLater(
        repository.merge(incoming),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'reason',
            contains('恢复后超过备份容量（10 MiB）'),
          ),
        ),
      );
      expect(repository.records, same(before));
      expect(storage.saved, same(local));
      expect(storage.writes, 0);
    },
  );

  test(
    'commit checks current history after an earlier capacity preview',
    () async {
      final local = records(BackupDocument.maxRecords - 1);
      final incoming = records(1, offset: BackupDocument.maxRecords);
      expect(
        BackupDocument.mergeForRestore(localRecords: local, incoming: incoming),
        hasLength(BackupDocument.maxRecords),
      );
      final storage = _MemoryStorage(local);
      final repository = FeedRepository(storage);
      await repository.load();
      await repository.add(now, milkAmountMl: 90);
      final before = repository.records;
      await expectLater(repository.merge(incoming), throwsFormatException);
      expect(repository.records, same(before));
      expect(storage.saved, same(before));
      expect(storage.writes, 1);
    },
  );

  test(
    'existing oversized history keeps ordinary recording and no-op restores',
    () async {
      final local = records(BackupDocument.maxRecords);
      final storage = _MemoryStorage(local);
      final repository = FeedRepository(storage);
      await repository.load();
      await repository.add(now, milkAmountMl: 90);
      expect(repository.records, hasLength(BackupDocument.maxRecords + 1));
      final before = repository.records;
      expect(await repository.merge([local.first]), 0);
      expect(
        await repository.merge([
          FeedRecord(id: local.first.id, time: now, milkAmountMl: 180),
        ]),
        0,
      );
      expect(repository.records, same(before));
      expect(storage.writes, 1);
    },
  );
}
