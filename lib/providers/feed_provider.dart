import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/feed_record.dart';
import '../repositories/feed_repository.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/time_utils.dart';

enum FeedState { normal, warning, alerting }

/// Presentation state for the current feeding cycle and immutable history.
class FeedProvider extends ChangeNotifier {
  static const _acknowledgementError = '提醒已停止，但状态保存失败，请重试';
  static const _audioPlayError = '提醒声音播放失败，请重试';
  static const _audioStopError = '声音停止失败，请重试';
  FeedProvider({
    required StorageService storage,
    required AudioService audioService,
    required NotificationService notificationService,
    DateTime Function()? clock,
    bool startTimer = true,
  }) : _storage = storage,
       _repository = FeedRepository(storage),
       _audioService = audioService,
       _notificationService = notificationService,
       _clock = clock ?? DateTime.now,
       _startTimerEnabled = startTimer {
    ready = _initialize();
  }

  final StorageService _storage;
  final FeedRepository _repository;
  final AudioService _audioService;
  final NotificationService _notificationService;
  final DateTime Function() _clock;
  final bool _startTimerEnabled;
  late final Future<void> ready;
  Future<void> _writeQueue = Future.value();
  Future<void> _effectQueue = Future.value();
  Future<void>? _stoppingAlert;
  FeedRecord? _stoppingRecord;
  Timer? _timer;
  bool _disposed = false;
  bool _isInitialized = false;
  bool _loadFailed = false;
  bool _foreground = true;
  bool _hasTriggeredAlert = false;
  bool _alertAcknowledged = false;
  bool _playbackRecoverySuppressed = false;
  bool _audioStopPending = false;
  bool _wasQuiet = false;
  int _pendingWrites = 0;
  int _pendingReminderEffects = 0;
  int _settingsRevision = 0;
  String? _error;
  String? _notificationError;
  String? _audioError;
  DateTime? _lastFeedTime;
  DateTime? _acknowledgedFeedTime;
  Duration _timeRemaining = const Duration(
    minutes: AppDefaults.feedIntervalMinutes,
  );
  Duration _timeElapsed = Duration.zero;
  Duration _overdue = Duration.zero;
  FeedState _state = FeedState.normal;
  int _feedIntervalMinutes = AppDefaults.feedIntervalMinutes;
  bool _nightModeEnabled = AppDefaults.nightModeEnabled;
  String _nightStartTime = AppDefaults.nightStartTime;
  String _nightEndTime = AppDefaults.nightEndTime;
  bool _soundEnabled = AppDefaults.soundEnabled;
  bool _soundLoopEnabled = AppDefaults.soundLoopEnabled;

  bool get isInitialized => _isInitialized;
  bool get isSaving => _pendingWrites > 0;
  bool get isAlertAcknowledged => _alertAcknowledged;
  String? get error =>
      _error ??
      (_audioError == _audioStopError
          ? _audioError
          : _notificationError ?? _audioError);
  DateTime? get lastFeedTime => _lastFeedTime;
  DateTime? get nextFeedTime =>
      _lastFeedTime?.add(Duration(minutes: _feedIntervalMinutes));
  Duration get timeRemaining => _timeRemaining;
  Duration get timeElapsed => _timeElapsed;
  Duration get overdue => _overdue;
  FeedState get state => _state;
  int get feedIntervalMinutes => _feedIntervalMinutes;
  DateTime get referenceTime => _clock().toLocal();
  List<FeedRecord> get feedHistory => _repository.records;
  List<FeedRecord> get todayRecords {
    final today = referenceTime;
    return List.unmodifiable(
      feedHistory.where((record) {
        final time = record.time.toLocal();
        return time.year == today.year &&
            time.month == today.month &&
            time.day == today.day;
      }),
    );
  }

  bool _isQuietAt(DateTime time) =>
      _nightModeEnabled &&
      TimeUtils.isInNightMode(_nightStartTime, _nightEndTime, now: time);

  bool get _mustStopAudio =>
      _state != FeedState.alerting ||
      _lastFeedTime == null ||
      _isQuietAt(_clock()) ||
      !_foreground ||
      _alertAcknowledged ||
      !_soundEnabled;

  bool get _shouldRecoverPlayback =>
      !_playbackRecoverySuppressed &&
      _soundLoopEnabled &&
      !_mustStopAudio &&
      _audioService.hasPlaybackError;

  bool _wasAcknowledged(DateTime? time) =>
      time != null &&
      _acknowledgedFeedTime?.millisecondsSinceEpoch ==
          time.millisecondsSinceEpoch;

  String _notificationFailure(Object error) => switch (error) {
    PlatformException(code: 'notification_permission_denied') =>
      '系统通知未开启，请前往设置开启',
    PlatformException(code: 'reminder_permission_denied') =>
      '后台提醒尚未启用，请更新支持该能力的应用版本',
    PlatformException(code: 'reminder_limit_exceeded') => '后台提醒额度受限，暂时无法添加提醒',
    _ => '系统通知暂时失败，请稍后重试',
  };

  void _logFailure(String operation, Object error, StackTrace stack) {
    debugPrint('FeedProvider.$operation failed: $error\n$stack');
  }

  Future<void> _initialize() async {
    final settingsRevision = _settingsRevision;
    try {
      final interval = await _storage.getFeedInterval();
      final nightEnabled = await _storage.getNightModeEnabled();
      final nightStart = await _storage.getNightStartTime();
      final nightEnd = await _storage.getNightEndTime();
      final sound = await _storage.getSoundEnabled();
      final loop = await _storage.getSoundLoopEnabled();
      final acknowledgedFeed = await _storage.getAcknowledgedFeedTime();
      await _repository.load();
      if (_disposed) return;
      if (settingsRevision == _settingsRevision) {
        _feedIntervalMinutes = interval;
        _nightModeEnabled = nightEnabled;
        _nightStartTime = nightStart;
        _nightEndTime = nightEnd;
        _soundEnabled = sound;
        _soundLoopEnabled = loop;
      }
      _lastFeedTime = _repository.lastFeedTime;
      _acknowledgedFeedTime = acknowledgedFeed;
      _alertAcknowledged = _wasAcknowledged(_lastFeedTime);
      _calculateCountdown();
      _isInitialized = true;
      // Native notification callbacks can be slow. Local readiness and the
      // countdown must not wait for reminder delivery services to respond.
      unawaited(_syncReminder(reschedule: true).then<void>((_) {}));
      if (_startTimerEnabled) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
    } catch (error, stack) {
      _logFailure('loadRecords', error, stack);
      _loadFailed = true;
      _error = '记录读取失败，原有数据已保留：$error';
    } finally {
      _isInitialized = true;
      _notify();
    }
  }

  void _calculateCountdown() {
    final last = _lastFeedTime;
    final interval = Duration(minutes: _feedIntervalMinutes);
    if (last == null) {
      _timeElapsed = Duration.zero;
      _overdue = Duration.zero;
      _timeRemaining = interval;
      _state = FeedState.normal;
      return;
    }
    final now = _clock();
    final elapsed = now.difference(last);
    _timeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
    // A clock correction can put the last record in the future. Elapsed stays
    // non-negative for display, but remaining must still match the deadline.
    final remaining = last.add(interval).difference(now);
    _timeRemaining = remaining.isNegative ? Duration.zero : remaining;
    _overdue = remaining.isNegative ? -remaining : Duration.zero;
    if (_timeRemaining == Duration.zero) {
      _state = FeedState.alerting;
    } else if (_timeRemaining.inMicroseconds < interval.inMicroseconds * 0.2) {
      _state = FeedState.warning;
    } else {
      _state = FeedState.normal;
    }
    if (_state != FeedState.alerting) {
      _hasTriggeredAlert = false;
    }
  }

  void _tick() {
    if (_disposed || !_isInitialized) return;
    final wasAlerting = _state == FeedState.alerting;
    _calculateCountdown();
    final leftAlert = wasAlerting && _state != FeedState.alerting;
    final quiet = _isQuietAt(_clock());
    // A one-shot stream failure must be visible without replaying the sound.
    if (!_mustStopAudio &&
        _audioService.hasPlaybackError &&
        _audioError == null) {
      _audioError = _audioPlayError;
    }
    if (leftAlert ||
        quiet != _wasQuiet ||
        (_audioStopPending && _pendingReminderEffects == 0 && _mustStopAudio) ||
        (_pendingReminderEffects == 0 &&
            _state == FeedState.alerting &&
            (!_hasTriggeredAlert || _shouldRecoverPlayback) &&
            !_playbackRecoverySuppressed &&
            !_alertAcknowledged &&
            _foreground &&
            !quiet)) {
      unawaited(_syncReminder(reschedule: leftAlert).then<void>((_) {}));
    }
    _notify();
  }

  /// Recalculate from the wall clock after resume or an explicit clock change.
  Future<void> refresh() async {
    await ready;
    if (_disposed) return;
    _calculateCountdown();
    _notify();
    await _syncReminder(reschedule: true, preserveDueReminder: true);
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (!_isInitialized) return;
    _calculateCountdown();
    if (foreground &&
        _state == FeedState.alerting &&
        _soundEnabled &&
        _soundLoopEnabled &&
        !_playbackRecoverySuppressed &&
        !_alertAcknowledged) {
      _hasTriggeredAlert = false;
    }
    unawaited(
      _syncReminder(
        reschedule: true,
        preserveDueReminder: true,
      ).then<void>((_) {}),
    );
    _notify();
  }

  /// Acknowledges this feeding cycle without creating a feeding record.
  Future<void> stopAlert() => _stoppingAlert ??= _stopAlert().whenComplete(() {
    _stoppingAlert = null;
    _stoppingRecord = null;
  });

  Future<void> _stopAlert() async {
    await ready;
    if (_disposed) return;
    final acknowledgedFeed = _lastFeedTime;
    final acknowledgedRecord = _stoppingRecord = feedHistory.firstOrNull;
    _alertAcknowledged = true;
    _playbackRecoverySuppressed = true;
    _hasTriggeredAlert = true;
    _notify();
    final stopped = await _syncReminder(reschedule: true);
    if (_disposed) return;
    if (!stopped) {
      // The temporary acknowledgement prevents an in-flight play from winning.
      // Only roll it back for the same cycle; a new record may have arrived.
      if (_lastFeedTime == acknowledgedFeed &&
          feedHistory.firstOrNull?.id == acknowledgedRecord?.id) {
        _alertAcknowledged = false;
        _hasTriggeredAlert = true;
        _audioError = _audioStopError;
        _notify();
      }
      throw StateError(_audioStopError);
    }
    try {
      await _storage.setAcknowledgedFeedTime(acknowledgedFeed);
      _acknowledgedFeedTime = acknowledgedFeed;
      if (_error == _acknowledgementError) {
        _error = null;
        _notify();
      }
    } catch (error, stack) {
      _logFailure('saveAcknowledgement', error, stack);
      _error = _acknowledgementError;
      _notify();
      rethrow;
    }
  }

  Future<void> recordFeed() => addFeedRecordWithTime(_clock());

  Future<void> addFeedRecordWithTime(DateTime time) {
    if (time.isAfter(_clock())) {
      return Future.error(ArgumentError('不能选择未来的时间'));
    }
    return _mutate(() => _repository.add(time));
  }

  Future<void> deleteFeedRecord(int index) {
    if (index < 0 || index >= feedHistory.length) return Future.value();
    final record = feedHistory[index];
    return _mutate(() => _repository.remove(record));
  }

  Future<void> _mutate(Future<void> Function() change) {
    if (_disposed) return Future.value();
    _pendingWrites++;
    _notify();
    final operation = _writeQueue
        .then((_) async {
          await ready;
          if (_disposed) return;
          if (_loadFailed) throw StateError('记录尚未成功读取，无法覆盖原有数据');
          try {
            final previousRecord = feedHistory.firstOrNull;
            await change();
            if (_disposed) return;
            final latestRecord = feedHistory.firstOrNull;
            final latest = latestRecord?.time;
            if (latest != _lastFeedTime ||
                latestRecord?.id != previousRecord?.id) {
              final stoppingThisCycle =
                  latestRecord != null &&
                  latestRecord.id == _stoppingRecord?.id &&
                  latestRecord.time == _stoppingRecord?.time;
              _hasTriggeredAlert = false;
              _playbackRecoverySuppressed = stoppingThisCycle;
              // Undo may restore a silenced cycle or the exact record whose
              // stop is still pending. Keep that intent until it succeeds or
              // the stop's existing failure path rolls it back.
              _alertAcknowledged =
                  stoppingThisCycle || _wasAcknowledged(latest);
            }
            _lastFeedTime = latest;
            _error = null;
            _calculateCountdown();
            _notify();
            // Persistence completes the save; reminder failures are reported
            // separately by the existing serialized effect queue.
            unawaited(_syncReminder(reschedule: true).then<void>((_) {}));
          } catch (error, stack) {
            _logFailure('saveRecords', error, stack);
            _error = '记录保存失败，请重试';
            rethrow;
          }
        })
        .whenComplete(() {
          _pendingWrites--;
          _notify();
        });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void updateSettings({
    int? feedIntervalMinutes,
    bool? nightModeEnabled,
    String? nightStartTime,
    String? nightEndTime,
    bool? soundEnabled,
    bool? soundLoopEnabled,
  }) {
    if (_disposed) return;
    if (feedIntervalMinutes != null && feedIntervalMinutes <= 0) {
      throw ArgumentError.value(feedIntervalMinutes, 'feedIntervalMinutes');
    }
    if ((nightStartTime != null && !TimeUtils.isValidTime(nightStartTime)) ||
        (nightEndTime != null && !TimeUtils.isValidTime(nightEndTime))) {
      throw ArgumentError('时间格式应为 HH:mm');
    }
    final interval = feedIntervalMinutes ?? _feedIntervalMinutes;
    final night = nightModeEnabled ?? _nightModeEnabled;
    final start = nightStartTime ?? _nightStartTime;
    final end = nightEndTime ?? _nightEndTime;
    final sound = soundEnabled ?? _soundEnabled;
    final loop = soundLoopEnabled ?? _soundLoopEnabled;
    if (interval == _feedIntervalMinutes &&
        night == _nightModeEnabled &&
        start == _nightStartTime &&
        end == _nightEndTime &&
        sound == _soundEnabled &&
        loop == _soundLoopEnabled) {
      return;
    }
    final restartAudio = sound != _soundEnabled || loop != _soundLoopEnabled;
    _settingsRevision++;
    _feedIntervalMinutes = interval;
    _nightModeEnabled = night;
    _nightStartTime = start;
    _nightEndTime = end;
    _soundEnabled = sound;
    _soundLoopEnabled = loop;
    if (restartAudio) {
      _hasTriggeredAlert = false;
      _playbackRecoverySuppressed = false;
    }
    _calculateCountdown();
    if (_state != FeedState.alerting) _hasTriggeredAlert = false;
    _notify();
    if (_isInitialized) {
      unawaited(
        _syncReminder(
          reschedule: true,
          restartAudio: restartAudio,
        ).then<void>((_) {}),
      );
    }
  }

  /// All native effects are serialized so a stale play/schedule cannot win over
  /// a newer feeding, acknowledgement, quiet-hours setting, or lifecycle event.
  /// Returns false when a required audio stop failed. Callers acknowledging a
  /// cycle must not persist success in that case; other effects remain isolated.
  Future<bool> _syncReminder({
    bool reschedule = false,
    bool restartAudio = false,
    bool preserveDueReminder = false,
  }) {
    _pendingReminderEffects++;
    final operation = _effectQueue
        .then<bool>((_) async {
          if (_disposed) return false;
          final notificationState = (
            feedHistory.firstOrNull?.id,
            _lastFeedTime,
            _settingsRevision,
            _foreground,
            _alertAcknowledged,
          );
          var notificationFailed = false;
          var audioFailed = false;
          var cancelled = false;
          var published = false;
          var audioStopped = true;
          Future<bool> attempt(
            String operation,
            Future<void> Function() effect, {
            bool notification = false,
            bool stopAudio = false,
          }) async {
            try {
              await effect();
              if (!_disposed &&
                  !notification &&
                  !audioFailed &&
                  (stopAudio || !_audioStopPending) &&
                  _audioError != null) {
                _audioError = null;
                _notify();
              }
              return true;
            } catch (error, stack) {
              _logFailure(operation, error, stack);
              if (notification) {
                notificationFailed = true;
                _notificationError = _notificationFailure(error);
              } else {
                audioFailed = true;
                _audioError = stopAudio ? _audioStopError : _audioPlayError;
              }
              if (!_disposed) {
                _notify();
              }
              return false;
            }
          }

          final quiet = _isQuietAt(_clock());
          if (quiet && !_wasQuiet) _hasTriggeredAlert = false;
          _wasQuiet = quiet;
          final due = _state == FeedState.alerting && _lastFeedTime != null;
          // Lifecycle refresh must not erase an already delivered reminder or
          // an overdue inexact alarm that Android has not delivered yet.
          final replaceNative =
              reschedule &&
              !(preserveDueReminder && due && !_alertAcknowledged && !quiet);
          if (replaceNative) {
            cancelled = await attempt(
              'cancelNotifications',
              _notificationService.cancelAll,
              notification: true,
            );
          }
          if (_disposed) return false;
          if (restartAudio || _mustStopAudio) {
            audioStopped = await attempt(
              'stopReminderAudio',
              _audioService.stopReminder,
              stopAudio: true,
            );
            if (restartAudio && audioStopped) _hasTriggeredAlert = false;
            // A committed record must stay successful even if stopping fails.
            // Retry on a later tick only while silence is still required and
            // the effect queue is idle, so slow native calls cannot pile up.
            _audioStopPending = !audioStopped;
          } else {
            // A newer cycle may need sound before an old stop can be retried.
            _audioStopPending = false;
          }
          if (_disposed) return false;
          final next = nextFeedTime;
          if (reschedule &&
              !_alertAcknowledged &&
              next != null &&
              next.isAfter(_clock()) &&
              !_isQuietAt(next)) {
            published = await attempt(
              'scheduleNotification',
              () => _notificationService.scheduleFeedReminder(
                next,
                playSound: _soundEnabled && !_foreground,
              ),
              notification: true,
            );
          }
          if (_disposed) return false;
          if (_shouldRecoverPlayback) {
            _hasTriggeredAlert = false;
            _audioError = _audioPlayError;
            _notify();
          }
          if (_state == FeedState.alerting &&
              !_isQuietAt(_clock()) &&
              _foreground &&
              !_playbackRecoverySuppressed &&
              !_alertAcknowledged &&
              (!_hasTriggeredAlert ||
                  cancelled ||
                  (reschedule && _notificationError != null))) {
            // Queued record/undo effects can cancel a notification restored by
            // the preceding effect. Rebuild it without replaying one-shot audio.
            final startedSound = !_hasTriggeredAlert && _soundEnabled;
            _hasTriggeredAlert = true;
            if (startedSound) {
              final played = await attempt(
                'playReminderAudio',
                () => _audioService.playReminder(loop: _soundLoopEnabled),
              );
              // A transient audio failure must not consume this cycle's only
              // opportunity to start its reminder. The next refresh can retry.
              if (!played) _hasTriggeredAlert = false;
            }
            if (_disposed ||
                _alertAcknowledged ||
                !_foreground ||
                _isQuietAt(_clock()) ||
                (startedSound && !_soundEnabled) ||
                _state != FeedState.alerting) {
              final stopped = await attempt(
                'stopReminderAudio',
                _audioService.stopReminder,
                stopAudio: true,
              );
              _audioStopPending = !stopped;
              audioStopped = stopped && audioStopped;
            } else {
              published = await attempt(
                'showNotification',
                () => _notificationService.showFeedReminder(playSound: false),
                notification: true,
              );
            }
          }
          if (_disposed) return false;
          if (!_foreground &&
              _state == FeedState.alerting &&
              !_isQuietAt(_clock()) &&
              !_playbackRecoverySuppressed &&
              !_alertAcknowledged &&
              (cancelled || (reschedule && _notificationError != null))) {
            final backgroundCycle = feedHistory.firstOrNull;
            final settingsRevision = _settingsRevision;
            published = await attempt(
              'showNotification',
              () => _notificationService.showFeedReminder(
                playSound: !_hasTriggeredAlert && _soundEnabled,
              ),
              notification: true,
            );
            // A cancelled due reminder needs a native replacement even after
            // backgrounding. Only the first successful alert may make sound;
            // a late success must not consume a newer cycle's first alert.
            // After resume, that sound also completes a one-shot cycle, while
            // loop mode still needs the foreground playback armed by resume.
            if (published &&
                !_disposed &&
                (!_foreground || !_soundLoopEnabled) &&
                !_alertAcknowledged &&
                !_playbackRecoverySuppressed &&
                settingsRevision == _settingsRevision &&
                backgroundCycle?.id == feedHistory.firstOrNull?.id &&
                backgroundCycle?.time == _lastFeedTime) {
              _hasTriggeredAlert = true;
            }
          }
          // Saving a record or recovering audio does not prove notification
          // recovery. A successful replacement does; cancellation alone does
          // only when this cycle no longer needs a native reminder.
          final currentNext = nextFeedTime;
          final noNotificationNeeded =
              currentNext == null ||
              _alertAcknowledged ||
              _isQuietAt(
                currentNext.isAfter(_clock()) ? currentNext : _clock(),
              );
          // A late success must not clear the error while a newer reminder
          // configuration is still waiting behind it in the native queue.
          final currentNotificationState = (
            feedHistory.firstOrNull?.id,
            _lastFeedTime,
            _settingsRevision,
            _foreground,
            _alertAcknowledged,
          );
          if (!notificationFailed &&
              notificationState == currentNotificationState &&
              (published || (cancelled && noNotificationNeeded)) &&
              _notificationError != null) {
            _notificationError = null;
            _notify();
          }
          return audioStopped;
        })
        .catchError((Object error, StackTrace stack) {
          _logFailure('synchronizeReminders', error, stack);
          if (_disposed) return false;
          _notificationError = '提醒服务暂时失败，请稍后重试';
          _notify();
          return false;
        })
        .whenComplete(() {
          _pendingReminderEffects--;
        });
    _effectQueue = operation.then<void>((_) {});
    return operation;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(
      _audioService.stopReminder().catchError((Object error, StackTrace stack) {
        _logFailure('stopReminderAudioOnDispose', error, stack);
      }),
    );
    super.dispose();
  }
}
