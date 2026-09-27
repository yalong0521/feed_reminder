import '../models/feed_record.dart';
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
      if (legacyTime != null) history.add(FeedRecord(time: legacyTime));
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

  Future<void> add(DateTime time) =>
      _save([..._records, FeedRecord(time: time)]);

  Future<void> remove(FeedRecord record) =>
      _save(_records.where((item) => item.id != record.id).toList());

  Future<void> _save(List<FeedRecord> records) async {
    final normalized = normalize(records);
    await _storage.saveFeedState(normalized);
    _records = normalized;
  }

  static List<FeedRecord> normalize(Iterable<FeedRecord> records) {
    final ordered = records.toList()..sort((a, b) => b.time.compareTo(a.time));
    final retained = ordered.take(100).toList();
    return List.unmodifiable([
      for (var index = 0; index < retained.length; index++)
        FeedRecord(
          id: retained[index].id,
          time: retained[index].time,
          intervalFromPrevious: index + 1 < retained.length
              ? retained[index].time.difference(retained[index + 1].time)
              : null,
        ),
    ]);
  }
}
