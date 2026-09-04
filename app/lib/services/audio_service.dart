import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'audio_files.dart';

/// A finished recording: a file that exists on disk, with bytes in it.
///
/// There is no constructor for this class that does not correspond to a real
/// file. [AudioService.stop] is the only thing that makes one, and it checks
/// the file before it does.
class Recording {
  const Recording({
    required this.relativePath,
    required this.duration,
    required this.bytes,
  });

  /// Relative to the app documents directory, and the value that goes into
  /// `segment.audio_path`. Not absolute: see [AudioFiles] for the reinstall
  /// bug that rule exists to prevent.
  final String relativePath;

  final Duration duration;
  final int bytes;

  int get durationMs => duration.inMilliseconds;
}

/// Why a finished recording could not be kept.
///
/// Each carries the sentence the user sees. A recording that did not happen
/// has to be said out loud — silently dropping it would leave someone
/// believing an answer was saved when it was not.
enum RecordingLoss {
  /// The recorder produced no file at all.
  noFile('That recording did not save. Nothing was lost — try again.'),

  /// A file with a container header and no audio inside it.
  ///
  /// On the device this was exactly 28 bytes, every time: iOS handed the
  /// encoder silence and it wrote an m4a describing a track with no frames.
  /// The message says "captured nothing" rather than "did not save", because
  /// those are different problems and lead somewhere different.
  silent('The microphone did not pick anything up. Check that nothing else '
      'is using it, then try again.');

  const RecordingLoss(this.message);

  final String message;
}

/// The outcome of [AudioService.stop].
///
/// A sealed pair rather than a nullable [Recording], so the caller cannot
/// reach the save path without having handled the failure — and so a failure
/// arrives with something to show a person rather than as an absence.
sealed class RecordingResult {
  const RecordingResult();
}

class RecordingSaved extends RecordingResult {
  const RecordingSaved(this.recording);

  final Recording recording;
}

class RecordingDiscarded extends RecordingResult {
  const RecordingDiscarded(this.loss);

  final RecordingLoss loss;
}

/// Why a recording could not be started.
enum RecordingBlocker {
  /// The user said no to the microphone, or the OS did on their behalf.
  permissionDenied,

  /// Permission is fine but the recorder would not start — no microphone,
  /// or another app holding it.
  recorderUnavailable,
}

/// Captures microphone audio to a file on this phone.
///
/// Deliberately the least interesting class in the app. There is no AI here,
/// no network, and no dependency that can fail in a way we do not control.
/// Decision D1 in CLAUDE.md says recording must never be able to fail, and
/// the way to honour that is to give it nothing that can.
class AudioService {
  AudioService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// Wall-clock timing of the current recording.
  ///
  /// Timed here rather than read back off the file afterwards, because
  /// reading the duration means decoding the file, which is work we would be
  /// doing while the grandmother waits for the next question.
  final Stopwatch _clock = Stopwatch();

  /// The absolute path the encoder is writing to, for this recording only.
  /// Never stored anywhere that outlives the app.
  String? _currentPath;

  /// The same file, said the way the database says it.
  String? _relativePath;

  bool get isRecording => _clock.isRunning;

  /// Checks the microphone permission, requesting it if it has not been
  /// asked for yet.
  ///
  /// This is `record`'s own method. We removed `permission_handler` in Slice
  /// 1 because this does the same job — see docs/spec.md section 10.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 16 kHz mono AAC.
  ///
  /// Whisper resamples everything to 16 kHz anyway, so recording higher is
  /// bytes we upload and storage we spend for no accuracy. Mono because one
  /// person is speaking. At this setting a 90-second answer is roughly 350 kB,
  /// which matters on a phone that is nearly full and on a connection in a
  /// majlis with thick walls.
  /// The smallest file we are willing to call a recording.
  ///
  /// The dead files the device produced were exactly **28 bytes** — an m4a
  /// header describing a track with nothing in it. Any real recording is far
  /// larger: at 16 kHz mono AAC even a fraction of a second runs to several
  /// kilobytes once the container is written.
  ///
  /// So this threshold has a wide margin on both sides — thirty-six times the
  /// dead file, and a small fraction of the shortest answer anyone would
  /// give. It is set to catch a container with no audio in it, not to judge
  /// how long someone spoke.
  static const minimumBytes = 1024;

  /// The size of the empty container iOS produced, kept as documentation.
  /// It is what [minimumBytes] was chosen against.
  static const observedEmptyContainerBytes = 28;

  static const _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    sampleRate: 16000,
    numChannels: 1,
  );

  /// Begins recording. Returns null on success, or why it could not start.
  Future<RecordingBlocker?> start({
    required int sessionId,
    required int seq,
  }) async {
    final granted = await hasPermission();
    await _logSessionState('before start', granted: granted);
    if (!granted) return RecordingBlocker.permissionDenied;

    // Audio lives under the app documents directory, which on both platforms
    // is backed up and is not cleared by the OS when storage runs low —
    // unlike the cache directory, which is. The recording is the
    // irreplaceable thing; it does not go anywhere the system may delete.
    final relative = AudioFiles.segmentPath(
      sessionId: sessionId,
      seq: seq,
      stamp: DateTime.now().millisecondsSinceEpoch,
    );

    // The encoder is the only thing in this app that gets an absolute path,
    // and it gets one because it has to open a file. Nothing keeps it.
    final absolute = await AudioFiles.prepare(relative);

    try {
      await _recorder.start(_config, path: absolute);
    } catch (_) {
      return RecordingBlocker.recorderUnavailable;
    }

    await _logSessionState('after start', granted: granted);

    _relativePath = relative;
    _currentPath = absolute;
    _clock
      ..reset()
      ..start();
    return null;
  }

  /// **Temporary diagnostics.** Prints the permission state around [start].
  ///
  /// This used to read the `AVAudioSession` category too, to test whether
  /// `just_audio` had left the session in `playback` when recording started.
  /// **That hypothesis is dead.** The device log showed `record` setting the
  /// category itself — `soloAmbient` before the first start, `playAndRecord`
  /// after it and on every attempt since — with the permission granted, and
  /// the files still 28 bytes. The session is not the problem, so the
  /// package that read it has been removed and only the permission line is
  /// kept.
  Future<void> _logSessionState(String when, {required bool granted}) async {
    debugPrint('=== AUDIO SESSION ($when) ==============================');
    debugPrint('record.hasPermission : $granted');
    debugPrint('platform             : ${Platform.operatingSystemVersion}');
    debugPrint('=======================================================');
  }

  /// **Temporary diagnostics.** Records a short clip with each candidate
  /// encoder config and reports how many bytes each one produced.
  ///
  /// Added 5 September 2026. Every recording is 28 bytes — an m4a container
  /// with no frames. The audio session was cleared as the cause: `record`
  /// sets `playAndRecord` itself, confirmed on the device. The current
  /// suspicion is that iOS's AAC encoder refuses 16 kHz and writes a header
  /// with nothing behind it rather than raising.
  ///
  /// This exists so that hypothesis costs **one** device run instead of one
  /// per config. The list below is a 2×2 over sample rate and channel count,
  /// plus two discriminators:
  ///
  /// - If everything except 16 kHz works, the sample rate is the problem.
  /// - If `wav` at 16 kHz works while `aacLc` at 16 kHz does not, the problem
  ///   is specifically the AAC encoder and not the input rate.
  /// - If **every** row is 28 bytes then the encoder is not the cause at all,
  ///   and the next place to look is `record` 7.1.1 on this iOS version.
  ///   That is a real outcome and it should be reported as one, not answered
  ///   with a third guess.
  ///
  /// Remove once the config is settled.
  Future<void> probeEncoderConfigs() async {
    if (isRecording) {
      debugPrint('probe skipped: a real recording is in progress');
      return;
    }

    // Ordered so each row differs from the one above it in one variable.
    const candidates = <(String, RecordConfig)>[
      ('platform defaults  44100 / 2ch aac', RecordConfig()),
      ('44100 / 1ch aac', RecordConfig(sampleRate: 44100, numChannels: 1)),
      ('22050 / 1ch aac', RecordConfig(sampleRate: 22050, numChannels: 1)),
      ('16000 / 2ch aac', RecordConfig(sampleRate: 16000, numChannels: 2)),
      ('16000 / 1ch aac  <-- what we ship',
          RecordConfig(sampleRate: 16000, numChannels: 1)),
      ('16000 / 1ch wav', RecordConfig(
          encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1)),
    ];

    debugPrint('=== ENCODER PROBE =====================================');
    debugPrint('iOS                  : ${Platform.operatingSystemVersion}');
    for (final encoder in [AudioEncoder.aacLc, AudioEncoder.wav]) {
      debugPrint('supported ${encoder.name.padRight(6)}     : '
          '${await _recorder.isEncoderSupported(encoder)}');
    }
    debugPrint('a dead container is  : $observedEmptyContainerBytes bytes');
    debugPrint('-------------------------------------------------------');

    final dir = Directory(await AudioFiles.prepare('recordings/_probe/x'))
        .parent;

    for (final (label, config) in candidates) {
      final path = '${dir.path}/probe_${label.hashCode}.'
          '${config.encoder == AudioEncoder.wav ? 'wav' : 'm4a'}';
      var result = '?';
      try {
        await _recorder.start(config, path: path);
        // Long enough that a working encoder writes several frames, short
        // enough that six of these is ten seconds of someone's time.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final returned = await _recorder.stop();

        final file = File(returned ?? path);
        if (!file.existsSync()) {
          result = 'NO FILE';
        } else {
          final bytes = file.lengthSync();
          result = '$bytes bytes'
              '${bytes <= observedEmptyContainerBytes * 2 ? '   <-- DEAD' : ''}';
          file.deleteSync();
        }
      } catch (error) {
        result = 'threw ${error.runtimeType}: $error';
      }
      debugPrint('${label.padRight(36)} $result');
    }

    if (dir.existsSync()) dir.deleteSync(recursive: true);
    debugPrint('=======================================================');
  }

  /// Stops recording and returns either the file or why there isn't one.
  ///
  /// **This method is the reliability guarantee in CLAUDE.md D1.**
  ///
  /// It does not return until three things are true: the recorder has
  /// finished and closed the file, the file exists on disk, and it has bytes
  /// in it. Only then does the caller have a [Recording] to write a database
  /// row from.
  ///
  /// So there is no ordering for the caller to remember and no way to get it
  /// wrong. `audio_path` cannot be written to the database before the audio
  /// is on disk, because the value does not exist until it is. A
  /// [RecordingDiscarded] means no row should be written at all.
  Future<RecordingResult> stop() async {
    if (!_clock.isRunning) {
      return const RecordingDiscarded(RecordingLoss.noFile);
    }

    // Completes once the encoder has flushed and closed the file. Awaiting
    // this is what makes the rest of the method meaningful.
    final returned = await _recorder.stop();
    _clock.stop();

    final path = returned ?? _currentPath;
    final relative = _relativePath;
    _currentPath = null;
    _relativePath = null;
    if (path == null || relative == null) {
      return const RecordingDiscarded(RecordingLoss.noFile);
    }

    final file = File(path);
    if (!await file.exists()) {
      return const RecordingDiscarded(RecordingLoss.noFile);
    }

    final bytes = await file.length();
    debugPrint('recording finished: $bytes bytes, ${_clock.elapsed} — $relative');

    // The guard used to be `bytes == 0`, and 28 bytes went straight through
    // it. An m4a header with no frames behind it is not a short recording,
    // it is a failed one, and storing it is worse than losing it: it puts a
    // segment in the archive that will never play and never transcribe, and
    // it looks to the user like something that saved.
    if (bytes < minimumBytes) {
      // Deleting this is not deleting audio. There is no audio in it — that
      // is what the check just established.
      await file.delete();
      return const RecordingDiscarded(RecordingLoss.silent);
    }

    return RecordingSaved(
      Recording(
        relativePath: relative,
        duration: _clock.elapsed,
        bytes: bytes,
      ),
    );
  }

  /// Abandons the current recording and removes the partial file.
  Future<void> cancel() async {
    if (!_clock.isRunning) return;
    await _recorder.stop();
    _clock.stop();
    final path = _currentPath;
    _currentPath = null;
    _relativePath = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> dispose() => _recorder.dispose();
}
