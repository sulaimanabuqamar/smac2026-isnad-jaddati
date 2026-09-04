import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/segment_repository.dart';
import '../models/segment.dart';
import 'audio_files.dart';
import 'transcription_service.dart';

/// Works through the segments waiting to be transcribed, one at a time.
///
/// This class is the other half of decision D1. Recording writes a row and
/// stops caring; everything that can fail — the network, the key, the model,
/// the free tier — happens in here, later, against a file that is already
/// safe on disk. Nothing in this class can lose audio, because nothing in
/// this class writes or deletes audio.
///
/// It extends [ChangeNotifier], which ships with Flutter and is not a state
/// management library: it is a list of callbacks and a method that calls
/// them. The interview screen adds one listener and reloads its rows.
class TranscriptionQueue extends ChangeNotifier {
  TranscriptionQueue({
    required this.segments,
    required this.service,
    Future<File> Function(String relativePath)? resolveAudio,
  }) : resolveAudio = resolveAudio ?? AudioFiles.resolve;

  final SegmentRepository segments;
  final TranscriptionService service;

  /// Turns a stored relative path into a file on this install.
  ///
  /// Injected for the same reason the HTTP client is: the real one calls
  /// `getApplicationDocumentsDirectory`, which needs a platform channel and
  /// therefore a device. Without this seam every queue test would need a
  /// phone, and the queue's retry decisions are exactly what we want to be
  /// able to test without one.
  final Future<File> Function(String relativePath) resolveAudio;

  /// How long to wait before trying again after the network let us down.
  ///
  /// Rising, so a phone that has been out of signal for an hour is not
  /// retrying every fifteen seconds for that hour, and capped at five
  /// minutes so it never gives up entirely. The wait is reset by any
  /// success — one transcript through means the connection is back.
  static const backoff = [
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  /// The run that is currently going, or null. Doubles as the "am I busy"
  /// flag and as the thing a second caller waits on — see [run].
  Future<void>? _inFlight;

  int _backoffStep = 0;
  Timer? _retry;
  bool _disposed = false;

  /// The segment being uploaded right now, so its row can say so.
  int? _activeSegmentId;

  /// Why the queue stopped, or null if it did not. Drives the offline banner.
  TranscriptionFailure? _pausedBy;

  int? get activeSegmentId => _activeSegmentId;
  TranscriptionFailure? get pausedBy => _pausedBy;
  bool get isWorking => _inFlight != null;

  /// Starts working through the pending rows.
  ///
  /// Deliberately returns a Future that the interview screen ignores. It
  /// calls this the instant a segment is saved and must not wait for it: a
  /// grandmother is sitting there, and the next question does not depend on
  /// the last answer having reached a server.
  ///
  /// Calling this while a run is going joins that run rather than starting a
  /// second one. Two runs over the same table would upload the same segment
  /// twice — and the interview screen calls this on open, on every save, and
  /// on every retry, so overlapping calls are the normal case, not the edge.
  Future<void> run() {
    if (_disposed) return Future<void>.value();
    return _inFlight ??= _drain().whenComplete(() => _inFlight = null);
  }

  Future<void> _drain() async {
    _retry?.cancel();
    _pausedBy = null;
    _notify();

    try {
      // Re-read from the database each pass rather than iterating a list
      // captured up front, so a segment recorded while we were uploading the
      // previous one is picked up in the same run.
      while (!_disposed) {
        final pending = await segments.getPending();
        if (pending.isEmpty) break;

        final failure = await _transcribe(pending.first);
        if (failure != null && failure.transient) {
          // Something outside our control. Stop here rather than marching
          // through every remaining row collecting the identical failure,
          // and leave them pending so a later run finds them.
          _pause(failure);
          return;
        }
      }
      _backoffStep = 0;
    } finally {
      _activeSegmentId = null;
      _notify();
    }
  }

  /// Transcribes one segment and writes the outcome. Returns the failure, or
  /// null if it worked.
  Future<TranscriptionFailure?> _transcribe(Segment segment) async {
    _activeSegmentId = segment.id;
    _notify();

    // Resolved now, against this install's documents directory. The row may
    // have been written by a build whose container UUID is long gone.
    final result = await service.transcribe(
      await resolveAudio(segment.audioPath),
      audioDuration: segment.durationMs == null
          ? null
          : Duration(milliseconds: segment.durationMs!),
    );

    switch (result) {
      case Transcribed(:final textAr):
        await segments.saveTranscript(segment.id!, textAr);
        // A success means the connection is healthy again, so the next
        // network failure starts from the shortest wait rather than the
        // long one we had climbed to.
        _backoffStep = 0;
        _notify();
        return null;

      case TranscriptionRejected(:final reason):
        if (!reason.transient) {
          // Permanent for this file. Marking it failed takes it out of the
          // queue so the rest can proceed; the user can put it back with the
          // retry button, which is a decision only they should make.
          await segments.markFailed(segment.id!);
          _notify();
        }
        return reason;
    }
  }

  void _pause(TranscriptionFailure failure) {
    _pausedBy = failure;
    // No point retrying on a schedule when the problem is a missing key —
    // that changes at build time, not while the app is running.
    if (failure != TranscriptionFailure.noKey) {
      final wait = backoff[_backoffStep.clamp(0, backoff.length - 1)];
      if (_backoffStep < backoff.length - 1) _backoffStep++;
      _retry = Timer(wait, run);
    }
  }

  /// Puts a failed segment back in the queue at the user's request.
  ///
  /// Only the user does this. The queue never re-queues its own permanent
  /// failures, because a file the endpoint refused once will be refused
  /// again and the loop would be invisible and endless.
  Future<void> retry(int segmentId) async {
    await segments.markPending(segmentId);
    _notify();
    unawaited(run());
  }

  /// [notifyListeners] throws if it runs after dispose, and an upload in
  /// flight will finish after the app has torn the queue down. Every
  /// notification in this class goes through here for that reason.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    super.dispose();
  }
}
