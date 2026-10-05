import 'dart:convert';
import 'dart:typed_data';

import '../models/backup_document.dart';
import '../models/feed_record.dart';
import '../repositories/feed_repository.dart';

/// Encoding and validation are independent of platform file dialogs.
class BackupService {
  const BackupService();

  String encodeJson(Iterable<FeedRecord> records, {required DateTime now}) {
    return BackupDocument(
      createdAt: now.toUtc(),
      records: records,
    ).encodeJson();
  }

  BackupDocument decodeBytes(Uint8List bytes) {
    _checkSize(bytes.length);
    try {
      return decodeJson(utf8.decode(bytes, allowMalformed: false));
    } on FormatException catch (error) {
      if (error.message.startsWith('Invalid UTF-8')) {
        throw const FormatException('文件不是有效的 UTF-8 备份');
      }
      rethrow;
    }
  }

  BackupDocument decodeJson(String content) {
    _checkSize(utf8.encode(content).length);
    if (content.startsWith('\uFEFF')) content = content.substring(1);
    dynamic data;
    try {
      data = jsonDecode(content);
    } on FormatException {
      throw const FormatException('文件内容损坏，请选择完整的 JSON 备份');
    }
    if (data is! Map<String, dynamic> || data['app'] != BackupDocument.appId) {
      throw const FormatException('这不是奶点记的备份文件');
    }
    if (data['schemaVersion'] is! int ||
        data['schemaVersion'] != BackupDocument.schemaVersion) {
      throw const FormatException('备份版本不兼容，请使用支持此备份的应用版本');
    }
    final createdAtValue = data['createdAt'];
    final createdAt = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)
        : null;
    if (createdAt == null ||
        !createdAt.isUtc ||
        createdAt.toIso8601String() != createdAtValue ||
        createdAt.year < 1 ||
        createdAt.year > 9999) {
      throw const FormatException('备份创建时间无效');
    }
    final rawRecords = data['records'];
    if (rawRecords is! List) {
      throw const FormatException('备份缺少完整的记录列表');
    }
    if (rawRecords.length > BackupDocument.maxRecords) {
      throw const FormatException('备份最多支持 50,000 条记录');
    }
    final records = <FeedRecord>[];
    for (var index = 0; index < rawRecords.length; index++) {
      final raw = rawRecords[index];
      if (raw is! Map<String, dynamic> ||
          raw['id'] is! String ||
          raw['time'] is! int ||
          raw['milkAmountMl'] is! int) {
        throw FormatException('第 ${index + 1} 条记录缺少有效的标识、时间或奶量');
      }
      final time = raw['time'] as int;
      final milk = raw['milkAmountMl'] as int;
      if (time < BackupDocument.minTimestamp ||
          time > BackupDocument.maxTimestamp) {
        throw FormatException('第 ${index + 1} 条记录的时间无效');
      }
      if (!FeedRecord.isValidMilkAmount(milk)) {
        throw FormatException('第 ${index + 1} 条记录的奶量应为 0–2000 mL');
      }
      records.add(
        FeedRecord(
          id: raw['id'] as String,
          time: DateTime.fromMillisecondsSinceEpoch(time),
          milkAmountMl: milk,
        ),
      );
    }
    return BackupDocument(createdAt: createdAt, records: records);
  }

  String encodeCsv(Iterable<FeedRecord> records) {
    BackupDocument.validateRecords(records);
    final normalized = FeedRepository.normalize(records);
    final rows = <List<String>>[
      ['记录ID', '喂奶时间（本地时间含时区）', '奶量（mL，未记录表示未填写）', '距上次（分钟）'],
      for (final record in normalized)
        [
          record.id,
          _localTimeWithOffset(record.time),
          record.milkAmountMl == 0 ? '未记录' : '${record.milkAmountMl}',
          record.intervalFromPrevious == null
              ? ''
              : '${record.intervalFromPrevious!.inMinutes}',
        ],
    ];
    final content =
        '\uFEFF${rows.map((row) => row.map(_cell).join(',')).join('\r\n')}\r\n';
    _checkSize(utf8.encode(content).length);
    return content;
  }

  static String _cell(String value) {
    // Quoting does not prevent spreadsheet formula execution. Prefix text
    // whose first non-whitespace character could start a formula as well.
    if (RegExp(r'^[\s\uFEFF]*[=+@\-]').hasMatch(value) ||
        value.startsWith('\t') ||
        value.startsWith('\r') ||
        value.startsWith('\n')) {
      value = "'$value";
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _localTimeWithOffset(DateTime value) {
    final local = value.toLocal();
    final minutes = local.timeZoneOffset.inMinutes;
    final absolute = minutes.abs();
    final hours = (absolute ~/ 60).toString().padLeft(2, '0');
    final remainder = (absolute % 60).toString().padLeft(2, '0');
    return '${local.toIso8601String()}${minutes < 0 ? '-' : '+'}$hours:$remainder';
  }

  static void _checkSize(int bytes) {
    if (bytes > BackupDocument.maxBytes) {
      throw const FormatException('文件超过 10 MiB，请选择较小的备份');
    }
  }
}
