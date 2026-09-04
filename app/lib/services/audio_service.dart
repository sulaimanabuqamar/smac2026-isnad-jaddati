import 'dart:io';

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
    if (!await hasPermission()) return RecordingBlocker.permissionDenied;

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

    _relativePath = relative;
    _currentPath = absolute;
    _clock
      ..reset()
      ..start();
    return null;
  }

  /// Stops recording and returns the file, or null if there is nothing usable.
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
  /// is on disk, because the value does not exist until it is. A null return
  /// means no row should be written at all.
  Future<Recording?> stop() async {
    if (!_clock.isRunning) return null;

    // Completes once the encoder has flushed and closed the file. Awaiting
    // this is what makes the rest of the method meaningful.
    final returned = await _recorder.stop();
    _clock.stop();

    final path = returned ?? _currentPath;
    final relative = _relativePath;
    _currentPath = null;
    _relativePath = null;
    if (path == null || relative == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final bytes = await file.length();

    // A zero-byte file is what a microphone that was never actually opened
    // leaves behind. Writing a row for it would put a segment in the archive
    // that plays silence, which is worse than losing it: it looks like a
    // recording that failed quietly rather than one that never happened.
    if (bytes == 0) {
      await file.delete();
      return null;
    }

    return Recording(
      relativePath: relative,
      duration: _clock.elapsed,
      bytes: bytes,
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
