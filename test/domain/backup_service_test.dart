import 'dart:convert';
import 'dart:typed_data';

import 'package:feed_reminder/models/backup_document.dart';
import 'package:feed_reminder/models/feed_record.dart';
import 'package:feed_reminder/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BackupService();
  final now = DateTime.utc(2026, 10, 3, 10);
  final first = FeedRecord(
    id: 'older',
    time: now.subtract(const Duration(hours: 3)),
    milkAmountMl: 120,
  );
  final second = FeedRecord(id: 'latest', time: now, milkAmountMl: 0);

  Map<String, dynamic> payload() =>
      jsonDecode(service.encodeJson([first, second], now: now))
          as Map<String, dynamic>;

  test('portable backup keeps identities, instants, zero and amount', () {
    final encoded = service.encodeJson([first, second], now: now);
    final result = service.decodeBytes(
      Uint8List.fromList(utf8.encode(encoded)),
    );
    expect(result.createdAt, now);
    expect(result.records.map((r) => r.id), ['older', 'latest']);
    expect(result.records.map((r) => r.time.millisecondsSinceEpoch), [
      first.time.millisecondsSinceEpoch,
      second.time.millisecondsSinceEpoch,
    ]);
    expect(result.records.map((r) => r.milkAmountMl), [120, 0]);
    expect(encoded, isNot(contains('intervalFromPrevious')));
    expect(() => result.records.clear(), throwsUnsupportedError);
    expect(service.decodeJson('\uFEFF$encoded').records.length, 2);
  });

  test('empty backup remains a valid portable backup', () {
    final result = service.decodeJson(service.encodeJson([], now: now));
    expect(result.records, isEmpty);
    expect(result.firstRecordTime, isNull);
    expect(result.lastRecordTime, isNull);
  });

  test(
    'preview compares time at the same millisecond precision as storage',
    () {
      final live = FeedRecord(
        id: 'just-saved',
        time: now.add(const Duration(microseconds: 123)),
        milkAmountMl: 80,
      );
      final document = service.decodeJson(service.encodeJson([live], now: now));
      final plan = BackupImportPlan(
        document: document,
        localRecords: [live],
        now: now,
      );
      expect(plan.duplicateCount, 1);
      expect(plan.conflictCount, 0);
    },
  );

  test('future records keep their instant and are counted in preview', () {
    final future = FeedRecord(
      id: 'future',
      time: now.add(const Duration(days: 1)),
    );
    final document = service.decodeJson(
      service.encodeJson([first, second, future], now: now),
    );
    final plan = BackupImportPlan(
      document: document,
      localRecords: [
        first,
        FeedRecord(id: second.id, time: second.time, milkAmountMl: 50),
      ],
      now: now,
    );
    expect(plan.addedCount, 1);
    expect(plan.duplicateCount, 1);
    expect(plan.conflictCount, 1);
    expect(plan.futureCount, 1);
    expect(document.firstRecordTime!.isAtSameMomentAs(first.time), isTrue);
    expect(document.lastRecordTime!.isAtSameMomentAs(future.time), isTrue);
  });

  for (final corruption in <String, void Function(Map<String, dynamic>)>{
    'app identity': (p) => p['app'] = 'other',
    'future schema': (p) => p['schemaVersion'] = 2,
    'fractional schema': (p) => p['schemaVersion'] = 1.0,
    'creation date': (p) => p['createdAt'] = '2026-02-31T00:00:00.000Z',
    'missing records': (p) => p.remove('records'),
    'duplicate identity': (p) => p['records'][1]['id'] = 'older',
    'empty identity': (p) => p['records'][1]['id'] = '  ',
    'missing identity': (p) => p['records'][1].remove('id'),
    'fractional time': (p) => p['records'][1]['time'] = 1.5,
    'invalid time': (p) =>
        p['records'][1]['time'] = BackupDocument.maxTimestamp + 1,
    'missing amount': (p) => p['records'][1].remove('milkAmountMl'),
    'fractional amount': (p) => p['records'][1]['milkAmountMl'] = 1.2,
    'negative amount': (p) => p['records'][1]['milkAmountMl'] = -1,
    'large amount': (p) => p['records'][1]['milkAmountMl'] = 2001,
  }.entries) {
    test('entire backup rejects ${corruption.key}', () {
      final data = payload();
      corruption.value(data);
      expect(() => service.decodeJson(jsonEncode(data)), throwsFormatException);
    });
  }

  test('malformed JSON, UTF-8, oversized files and batches are rejected', () {
    expect(() => service.decodeJson('{bad'), throwsFormatException);
    expect(
      () => service.decodeBytes(Uint8List.fromList([0xc3, 0x28])),
      throwsFormatException,
    );
    expect(
      () => service.decodeBytes(Uint8List(BackupDocument.maxBytes + 1)),
      throwsFormatException,
    );
    final data = payload();
    data['records'] = List.filled(BackupDocument.maxRecords + 1, {});
    expect(() => service.decodeJson(jsonEncode(data)), throwsFormatException);
  });

  test(
    'CSV carries BOM, local offset, recomputed intervals and unrecorded marker',
    () {
      final csv = service.encodeCsv([first, second]);
      expect(utf8.encode(csv).take(3), [0xef, 0xbb, 0xbf]);
      expect(csv, contains('未记录'));
      expect(csv, contains('"180"'));
      expect(csv, contains('"120"'));
      expect(csv, matches(RegExp(r'[+-]\d{2}:\d{2}')));
      expect(csv, endsWith('\r\n'));
    },
  );

  test(
    'CSV guards formulas after whitespace and quotes embedded delimiters',
    () {
      for (final id in [
        '=1+1',
        '+SUM(A1)',
        '-1',
        '@cmd',
        '  =2',
        '\ttext',
        '\rtext',
      ]) {
        final csv = service.encodeCsv([FeedRecord(id: id, time: now)]);
        expect(csv, contains('"\'$id"'));
      }
      final csv = service.encodeCsv([FeedRecord(id: '中文,"值"\n一', time: now)]);
      expect(csv, contains('"中文,""值""\n一"'));
    },
  );
}
