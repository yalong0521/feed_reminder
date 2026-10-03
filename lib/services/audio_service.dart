import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Serializes playback so a quick stop cannot be overtaken by a pending start.
class AudioService {
  AudioService({AudioPlayer Function()? playerFactory})
    : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;
  StreamSubscription<void>? _completion;
  Future<void> _pending = Future<void>.value();
  bool _isPlaying = false;
  bool _loop = true;
  bool _disposed = false;
  Object? _playbackError;
  bool get isPlaying => _isPlaying;
  bool get hasPlaybackError => _playbackError != null;

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.catchError((Object _) {});
    return result;
  }

  AudioPlayer _getPlayer() {
    final player = _player ??= _playerFactory();
    _completion ??= player.onPlayerComplete.listen(
      (_) {
        if (_disposed || !identical(_player, player)) return;
        // The plugin emits completion at each loop boundary as well.
        if (!_loop) _isPlaying = false;
      },
      onError: (Object error, StackTrace stack) {
        if (_disposed || !identical(_player, player)) return;
        _isPlaying = false;
        _playbackError = error;
        debugPrint('Reminder audio unavailable: $error\n$stack');
      },
    );
    return player;
  }

  Future<void> _discardFailedPlayer(AudioPlayer player) async {
    // Detach before awaiting cleanup so late native events cannot affect the
    // replacement. A failed creation future makes release/dispose fail forever.
    _player = null;
    final completion = _completion;
    _completion = null;
    try {
      await completion?.cancel();
    } finally {
      try {
        await player.dispose();
      } catch (error, stack) {
        debugPrint(
          'Failed reminder player cleanup unavailable: $error\n$stack',
        );
      }
    }
  }

  Future<void> playReminder({bool loop = true}) => _enqueue(() async {
    if (_disposed || _isPlaying) return;
    var player = _player;
    try {
      // Android retains the source after a MediaPlayer error. Reusing that
      // source without release can report "prepared" without starting sound.
      if (_playbackError != null && player != null) {
        try {
          await player.release();
        } catch (_) {
          // Native creation failures are retained by AudioPlayer itself. Use
          // a new instance when releasing the old one cannot recover it.
          await _discardFailedPlayer(player);
          player = null;
        }
      }
      player ??= _getPlayer();
      _loop = loop;
      _playbackError = null;
      await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      // Completion/error events may arrive before the platform play future.
      // Set this first so those events remain authoritative after it returns.
      _isPlaying = true;
      await player.play(AssetSource('sounds/reminder.wav'));
      final error = _playbackError;
      if (error != null) throw error;
    } catch (error) {
      _isPlaying = false;
      _playbackError = error;
      rethrow;
    }
  });

  Future<void> stopReminder() => _enqueue(() async {
    if (_disposed) return;
    await _player?.stop();
    _isPlaying = false;
  });

  Future<void> dispose() => _enqueue(() async {
    if (_disposed) return;
    _disposed = true;
    _isPlaying = false;
    await _completion?.cancel();
    await _player?.dispose();
  });
}
