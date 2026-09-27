import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player extends Fake implements AudioPlayer {
  final completions = StreamController<void>.broadcast(sync: true);
  final operations = <String>[];
  Completer<void>? playGate;

  @override
  Stream<void> get onPlayerComplete => completions.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    operations.add('mode:${mode.name}');
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    operations.add('play');
    await playGate?.future;
  }

  @override
  Future<void> stop() async => operations.add('stop');

  @override
  Future<void> dispose() async {
    operations.add('dispose');
    await completions.close();
  }
}

void main() {
  late _Player player;
  late AudioService audio;

  setUp(() {
    player = _Player();
    audio = AudioService(playerFactory: () => player);
  });
  tearDown(() => audio.dispose());

  test(
    'a loop boundary preserves playback and prevents a second start',
    () async {
      await audio.playReminder();
      player.completions.add(null);

      expect(audio.isPlaying, isTrue);
      await audio.playReminder();
      expect(
        player.operations.where((operation) => operation == 'play'),
        hasLength(1),
      );
    },
  );

  test('a completed one-shot reminder can be played again', () async {
    await audio.playReminder(loop: false);
    player.completions.add(null);

    expect(audio.isPlaying, isFalse);
    await audio.playReminder(loop: false);
    expect(audio.isPlaying, isTrue);
    expect(
      player.operations.where((operation) => operation == 'play'),
      hasLength(2),
    );
  });

  test(
    'native playback errors are handled and allow another attempt',
    () async {
      await audio.playReminder();
      player.completions.addError(PlatformException(code: 'playback_failed'));

      expect(audio.isPlaying, isFalse);
      await audio.playReminder();
      expect(audio.isPlaying, isTrue);
    },
  );

  test('stop waits for a pending start and leaves playback stopped', () async {
    player.playGate = Completer<void>();
    final playing = audio.playReminder();
    final stopped = audio.stopReminder();
    await Future<void>.delayed(Duration.zero);
    expect(player.operations, ['mode:loop', 'play']);

    player.playGate!.complete();
    await Future.wait([playing, stopped]);

    expect(player.operations.last, 'stop');
    expect(audio.isPlaying, isFalse);
  });

  test(
    'disposal releases the player once and prevents later playback',
    () async {
      await audio.playReminder();
      await audio.dispose();
      await audio.playReminder();
      await audio.dispose();

      expect(audio.isPlaying, isFalse);
      expect(
        player.operations.where((operation) => operation == 'play'),
        hasLength(1),
      );
      expect(
        player.operations.where((operation) => operation == 'dispose'),
        hasLength(1),
      );
    },
  );
}
