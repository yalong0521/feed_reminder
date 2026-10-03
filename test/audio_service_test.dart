import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:feed_reminder/services/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player extends Fake implements AudioPlayer {
  final completions = StreamController<void>.broadcast(sync: true);
  final operations = <String>[];
  Completer<void>? playGate;
  bool creationFails = false;
  bool releaseFails = false;
  bool disposeFails = false;

  @override
  Stream<void> get onPlayerComplete => completions.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    operations.add('mode:${mode.name}');
    if (creationFails) throw PlatformException(code: 'creation_failed');
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
  Future<void> release() async {
    operations.add('release');
    if (releaseFails) throw PlatformException(code: 'release_failed');
  }

  @override
  Future<void> dispose() async {
    operations.add('dispose');
    if (disposeFails) throw PlatformException(code: 'dispose_failed');
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
      expect(
        player.operations.where((operation) => operation == 'release'),
        hasLength(1),
      );
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
    'an error during playback startup cannot report successful playback',
    () async {
      player.playGate = Completer<void>();
      final playing = audio.playReminder();
      final failed = expectLater(playing, throwsA(isA<PlatformException>()));
      await Future<void>.delayed(Duration.zero);
      player.completions.addError(PlatformException(code: 'playback_failed'));
      player.playGate!.complete();
      await failed;
      expect(audio.isPlaying, isFalse);

      await audio.playReminder();
      expect(audio.isPlaying, isTrue);
    },
  );

  test('one-shot completion during startup stays completed', () async {
    player.playGate = Completer<void>();
    final playing = audio.playReminder(loop: false);
    await Future<void>.delayed(Duration.zero);
    player.completions.add(null);
    player.playGate!.complete();
    await playing;
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

  test(
    'failed native creation replaces an unrecoverable player on retry',
    () async {
      player.creationFails = true;
      player.releaseFails = true;
      player.disposeFails = true;
      final replacement = _Player();
      var creations = 0;
      audio = AudioService(
        playerFactory: () => creations++ == 0 ? player : replacement,
      );
      addTearDown(player.completions.close);

      await expectLater(
        audio.playReminder(loop: false),
        throwsA(isA<PlatformException>()),
      );
      expect(audio.isPlaying, isFalse);
      expect(audio.hasPlaybackError, isTrue);

      await audio.playReminder(loop: false);

      expect(creations, 2);
      expect(player.operations, ['mode:stop', 'release', 'dispose']);
      expect(audio.isPlaying, isTrue);
      expect(audio.hasPlaybackError, isFalse);
      // Neither completion nor an error from the retired native instance may
      // stop or invalidate the current one-shot reminder.
      player.completions.add(null);
      player.completions.addError(PlatformException(code: 'old_player_error'));
      expect(audio.isPlaying, isTrue);
      expect(audio.hasPlaybackError, isFalse);

      replacement.completions.add(null);
      expect(audio.isPlaying, isFalse);
      expect(
        replacement.operations.where((operation) => operation == 'play'),
        hasLength(1),
      );
    },
  );

  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'dispose' : 'stop'} waits for replacement playback and wins',
      () async {
        player.creationFails = true;
        player.releaseFails = true;
        final replacement = _Player()..playGate = Completer<void>();
        var creations = 0;
        audio = AudioService(
          playerFactory: () => creations++ == 0 ? player : replacement,
        );
        await expectLater(
          audio.playReminder(),
          throwsA(isA<PlatformException>()),
        );

        final recovery = audio.playReminder();
        final stopped = dispose ? audio.dispose() : audio.stopReminder();
        await Future<void>.delayed(Duration.zero);
        expect(replacement.operations, ['mode:loop', 'play']);
        replacement.playGate!.complete();
        await Future.wait([recovery, stopped]);

        expect(replacement.operations.last, dispose ? 'dispose' : 'stop');
        expect(audio.isPlaying, isFalse);
        if (dispose) {
          await audio.playReminder();
          expect(creations, 2);
          expect(
            replacement.operations.where((operation) => operation == 'play'),
            hasLength(1),
          );
        }
      },
    );
  }
}
