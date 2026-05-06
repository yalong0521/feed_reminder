import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  Future<void> playReminder({bool loop = true}) async {
    if (_isPlaying) return;

    await _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    await _player.play(AssetSource('sounds/reminder.wav'));
    _isPlaying = true;
  }

  Future<void> stopReminder() async {
    if (!_isPlaying) return;

    await _player.stop();
    _isPlaying = false;
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
