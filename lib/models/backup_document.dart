import 'dart:convert';

import 'feed_record.dart';

/// The portable data contract. Settings and derived intervals stay on device.
class BackupDocument {
  BackupDocument({
    required this.createdAt,
    required Iterable<FeedRecord> records,
  }) : records = List.unmodifiable(records) {
    validateRecords(this.records);
  }

  static const appId = 'feed_reminder';
  static const schemaVersion = 1;
  static const maxBytes = 10 * 1024 * 1024;
  static const maxRecords = 50000;
  static const minTimestamp = -62135596800000; // 0001-01-01 UTC
  static const maxTimestamp = 253402300799999; // 9999-12-31 UTC

  final DateTime createdAt;
  final List<FeedRecord> records;

  String encodeJson() {
    final content = const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': schemaVersion,
      'app': appId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'records': [
        for (final record in records)
          {
            'id': record.id,
            'time': record.time.millisecondsSinceEpoch,
            'milkAmountMl': record.milkAmountMl,
          },
      ],
    });
    if (utf8.encode(content).length > maxBytes) {
      throw const FormatException('文件超过 10 MiB，请选择较小的备份');
    }
    return content;
  }

  /// Both the preview and the serialized write use this same capacity check.
  /// An unchanged import returns the original list, even if ordinary recording
  /// has grown beyond the portable backup limits.
  static List<FeedRecord> mergeForRestore({
    required List<FeedRecord> localRecords,
    required List<FeedRecord> incoming,
  }) {
    validateRecords(incoming);
    final existing = {for (final record in localRecords) record.id};
    final additions = incoming
        .where((record) => !existing.contains(record.id))
        .toList();
    if (additions.isEmpty) return localRecords;
    if (localRecords.length + additions.length > maxRecords) {
      throw const FormatException('恢复后超过备份容量（50,000 条），无法合并。现有记录保持不变。');
    }
    final merged = [...localRecords, ...additions];
    // Reserve the longest supported creation timestamp, so a later export
    // with microseconds cannot cross the size limit due to its metadata alone.
    final document = BackupDocument(
      createdAt: DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999),
      records: merged,
    );
    try {
      document.encodeJson();
    } on FormatException {
      throw const FormatException('恢复后超过备份容量（10 MiB），无法合并。现有记录保持不变。');
    }
    return merged;
  }

  DateTime? get firstRecordTime => _edgeTime(oldest: true);
  DateTime? get lastRecordTime => _edgeTime(oldest: false);

  DateTime? _edgeTime({required bool oldest}) {
    DateTime? result;
    for (final record in records) {
      if (result == null ||
          (oldest
              ? record.time.isBefore(result)
              : record.time.isAfter(result))) {
        result = record.time;
      }
    }
    return result;
  }

  /// Also called by the repository, so mutation never trusts a UI preview.
  static void validateRecords(Iterable<FeedRecord> records) {
    final ids = <String>{};
    var count = 0;
    for (final record in records) {
      count++;
      if (count > maxRecords) {
        throw const FormatException('备份最多支持 50,000 条记录');
      }
      if (record.id.trim().isEmpty || record.id.length > 256) {
        throw FormatException('第 $count 条记录的标识无效');
      }
      if (!ids.add(record.id)) {
        throw FormatException('第 $count 条记录的标识重复');
      }
      final timestamp = record.time.millisecondsSinceEpoch;
      if (timestamp < minTimestamp || timestamp > maxTimestamp) {
        throw FormatException('第 $count 条记录的时间无效');
      }
      if (!FeedRecord.isValidMilkAmount(record.milkAmountMl)) {
        throw FormatException('第 $count 条记录的奶量应为 0–2000 mL');
      }
    }
  }
}

/// A preview only: the repository must merge again inside its write queue.
class BackupImportPlan {
  BackupImportPlan({
    required this.document,
    required Iterable<FeedRecord> localRecords,
    required DateTime now,
  }) {
    final local = {for (final record in localRecords) record.id: record};
    var added = 0;
    var duplicate = 0;
    var conflict = 0;
    var future = 0;
    for (final incoming in document.records) {
      if (incoming.time.isAfter(now)) future++;
      final existing = local[incoming.id];
      if (existing == null) {
        added++;
      } else if (existing.time.millisecondsSinceEpoch ==
              incoming.time.millisecondsSinceEpoch &&
          existing.milkAmountMl == incoming.milkAmountMl) {
        duplicate++;
      } else {
        conflict++;
      }
    }
    addedCount = added;
    duplicateCount = duplicate;
    conflictCount = conflict;
    futureCount = future;
  }

  final BackupDocument document;
  late final int addedCount;
  late final int duplicateCount;
  late final int conflictCount;
  late final int futureCount;
}
