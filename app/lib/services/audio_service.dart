import 'dart:io';

import 'package:audio_session/audio_session.dart';
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

  /// **Temporary diagnostics.** Prints the iOS audio session state around
  /// [start].
  ///
  /// Added 4 September 2026. Every file the device recorded was exactly 28
  /// bytes — an m4a container with a header and no frames, which is what iOS
  /// leaves behind when it hands the encoder silence. The hypothesis is that
  /// `just_audio` has configured `AVAudioSession` for playback and the
  /// category is not `playAndRecord` when `record` starts.
  ///
  /// This confirms or kills that hypothesis before anything is changed. It
  /// is logged before *and* after `_recorder.start()`, because whether
  /// `record` sets the category itself is exactly the thing in question.
  ///
  /// `AVAudioSessionRecordPermission` is asked separately from
  /// `record.hasPermission()`: they are different questions, and a plugin
  /// reporting granted while the OS reports otherwise would be a completely
  /// different bug from the one we think we have.
  ///
  /// Remove once the cause is known.
  Future<void> _logSessionState(String when, {required bool granted}) async {
    debugPrint('=== AUDIO SESSION ($when) ==============================');
    debugPrint('record.hasPermission : $granted');

    if (!Platform.isIOS) {
      debugPrint('platform             : not iOS — AVAudioSession n/a');
      debugPrint('=======================================================');
      return;
    }

    try {
      final session = AVAudioSession();
      final category = await session.category;
      debugPrint('AVAudioSession cat   : $category');
      debugPrint('  is playAndRecord?  : '
          '${category == AVAudioSessionCategory.playAndRecord}');
      debugPrint('AVAudioSession mode  : ${await session.mode}');
      debugPrint('category options     : ${await session.categoryOptions}');
      debugPrint('record permission    : ${await session.recordPermission}');
      debugPrint('other audio playing  : ${await session.isOtherAudioPlaying}');
      debugPrint('current route        : ${await session.currentRoute}');
    } catch (error) {
      debugPrint('AVAudioSession       : could not be read — $error');
    }
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
