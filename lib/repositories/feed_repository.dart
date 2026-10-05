import '../models/feed_record.dart';
import '../models/backup_document.dart';
import '../services/storage_service.dart';

/// Owns the ordered history. The history is authoritative; lastFeedTime remains
/// persisted for compatibility with older versions of the application.
class FeedRepository {
  FeedRepository(this._storage);

  final StorageService _storage;
  List<FeedRecord> _records = const [];

  List<FeedRecord> get records => _records;
  DateTime? get lastFeedTime => _records.firstOrNull?.time;

  Future<void> load() async {
    final hasHistory = await _storage.hasFeedHistory();
    final history = await _storage.getFeedHistory();
    if (!hasHistory) {
      final legacyTime = await _storage.getLastFeedTime();
      if (legacyTime != null) {
        history.add(
          FeedRecord(
            id: 'legacy-last-${legacyTime.millisecondsSinceEpoch}',
            time: legacyTime,
          ),
        );
      }
    }
    final identities = <String>{};
    if (history.any(
      (record) => record.id.isEmpty || !identities.add(record.id),
    )) {
      // Deletion uses identity. Accepting duplicates could erase several meals
      // when the user confirms deleting one damaged record.
      throw const FormatException('喂奶记录标识重复或为空');
    }
    _records = normalize(history);
  }

  Future<void> add(DateTime time, {int milkAmountMl = 0}) async =>
      _save([..._records, FeedRecord(time: time, milkAmountMl: milkAmountMl)]);

  Future<void> update(
    String id, {
    required DateTime time,
    required int milkAmountMl,
  }) async {
    if (!_records.any((record) => record.id == id)) {
      throw StateError('这条记录已不存在，请刷新后重试');
    }
    final replacement = FeedRecord(
      id: id,
      time: time,
      milkAmountMl: milkAmountMl,
    );
    await _save([
      for (final record in _records) record.id == id ? replacement : record,
    ]);
  }

  Future<void> remove(FeedRecord record) =>
      _save(_records.where((item) => item.id != record.id).toList());

  /// Merge only missing identities; local edits always win over old backups.
  Future<int> merge(List<FeedRecord> incoming) async {
    final merged = BackupDocument.mergeForRestore(
      localRecords: _records,
      incoming: incoming,
    );
    final added = merged.length - _records.length;
    if (added > 0) await _save(merged);
    return added;
  }

  Future<void> _save(List<FeedRecord> records) async {
    final normalized = normalize(records);
    await _storage.saveFeedState(normalized);
    _records = normalized;
  }

  static List<FeedRecord> normalize(Iterable<FeedRecord> records) {
    // Preserve the input order for equal instants. List.sort is not stable;
    // shuffling equal-time records could change the active cycle's identity.
    final indexed = records.indexed.toList()
      ..sort((a, b) {
        final byTime = b.$2.time.compareTo(a.$2.time);
        return byTime == 0 ? a.$1.compareTo(b.$1) : byTime;
      });
    final ordered = indexed.map((entry) => entry.$2).toList();
    return List.unmodifiable([
      for (var index = 0; index < ordered.length; index++)
        FeedRecord(
          id: ordered[index].id,
          time: ordered[index].time,
          milkAmountMl: ordered[index].milkAmountMl,
          intervalFromPrevious: index + 1 < ordered.length
              ? ordered[index].time.difference(ordered[index + 1].time)
              : null,
        ),
    ]);
  }
}
