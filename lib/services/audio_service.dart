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

  Future<void> playReminder({bool loop = true}) => _enqueue(() async {
    if (_disposed || _isPlaying) return;
    final player = _player ??= _playerFactory();
    _completion ??= player.onPlayerComplete.listen(
      (_) {
        // The plugin emits completion at each loop boundary as well.
        if (!_loop) _isPlaying = false;
      },
      onError: (Object error, StackTrace stack) {
        _isPlaying = false;
        _playbackError = error;
        debugPrint('Reminder audio unavailable: $error\n$stack');
      },
    );
    _loop = loop;
    final resetPlayer = _playbackError != null;
    _playbackError = null;
    try {
      // Android retains the source after a MediaPlayer error. Reusing that
      // source without release can report "prepared" without starting sound.
      if (resetPlayer) await player.release();
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
