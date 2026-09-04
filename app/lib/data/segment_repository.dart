import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/segment.dart';

/// Create and read for `segment`.
///
/// Note what is missing: there is no method here that writes a segment row
/// without an `audio_path`. The model makes that field non-nullable and this
/// class offers no way around it. The ordering guarantee in docs/spec.md
/// section 8 — audio on disk before any transcription state exists — is
/// enforced by the shape of the code, not by remembering to do it right.
class SegmentRepository {
  SegmentRepository(this._db);

  final Database _db;

  /// Inserts a segment whose audio file is already written and closed.
  ///
  /// The status it is born in is `pending`, which is the model's default.
  /// Transcription is a separate job that runs later against a row that
  /// already exists, and can fail without costing us the recording.
  Future<int> create(Segment segment) =>
      _db.insert('segment', segment.toMap());

  Future<List<Segment>> getForSession(int sessionId) async {
    final rows = await _db.query(
      'segment',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'seq',
    );
    return rows.map(Segment.fromMap).toList();
  }

  /// The position the next segment in this session should take.
  ///
  /// Asked of the database rather than counted in Dart, because the answer
  /// has to be right after the app has been closed and reopened mid-session.
  /// COALESCE covers the first segment, where MAX(seq) over no rows is null.
  Future<int> nextSeq(int sessionId) async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(seq), 0) + 1 AS next FROM segment WHERE session_id = ?',
      [sessionId],
    );
    return rows.first['next'] as int;
  }

  /// Segments still waiting to be transcribed, oldest first, across every
  /// session. This is the queue the archive screen will show a count for.
  Future<List<Segment>> getPending() async {
    final rows = await _db.query(
      'segment',
      where: 'transcribe_status = ?',
      whereArgs: [TranscribeStatus.pending.db],
      orderBy: 'created_at',
    );
    return rows.map(Segment.fromMap).toList();
  }

  /// Writes a finished transcript and moves the row out of the queue.
  ///
  /// Two rules in one statement. The CASE is the human-correction guard: if
  /// someone has fixed this transcript by hand, a later transcription must
  /// not silently undo their work. The status is set outside the CASE and so
  /// always advances — an edited row still leaves `pending`, because if it
  /// did not, [getPending] would hand it back on every run forever.
  ///
  /// Written as raw SQL rather than two updates so it is one atomic
  /// statement. There is no instant at which the text is new and the status
  /// is old.
  Future<int> saveTranscript(int id, String transcriptAr) => _db.rawUpdate(
        '''
        UPDATE segment
           SET transcript_ar = CASE WHEN edited_by_user = 0
                                    THEN ? ELSE transcript_ar END,
               transcribe_status = ?
         WHERE id = ?
        ''',
        [transcriptAr, TranscribeStatus.done.db, id],
      );

  /// Marks a segment as one transcription will not fix.
  ///
  /// Note what this does not touch: `audio_path` and the file it names. A
  /// failed transcription costs a transcript, never a recording.
  Future<int> markFailed(int id) => _db.update(
        'segment',
        {'transcribe_status': TranscribeStatus.failed.db},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Puts a failed segment back in the queue. Only ever called because a
  /// person pressed retry — see TranscriptionQueue.retry for why.
  Future<int> markPending(int id) => _db.update(
        'segment',
        {'transcribe_status': TranscribeStatus.pending.db},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// How many segments are in a given state, across every session. Counted
  /// in SQL rather than by fetching rows and calling `.length`, because the
  /// archive shows this number and has no use for the rows behind it.
  Future<int> countByStatus(TranscribeStatus status) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM segment WHERE transcribe_status = ?',
      [status.db],
    );
    return rows.first['n'] as int;
  }

  /// Removes segments whose audio file is present but too small to be audio,
  /// and deletes the file with them. Returns how many went.
  ///
  /// This exists because four rows were written before the 28-byte guard did:
  /// an m4a header with no frames behind it, which will never play and never
  /// transcribe. A row like that is worse than no row, because it looks to
  /// the user like a recording that saved.
  ///
  /// **It only deletes what it can prove is dead.** A row whose file is
  /// *missing* is deliberately left alone. Missing is exactly what the
  /// reinstall bug looked like — every file on the phone appeared absent
  /// because we were resolving against the wrong container — and a sweep
  /// that deleted on absence would have destroyed the whole archive that
  /// morning instead of fixing it. A file we can open and measure is a
  /// different class of evidence from a file we cannot find.
  ///
  /// The resolver is injected for the same reason the queue's is: resolving
  /// a path needs a platform channel, and this needs to be testable without
  /// a phone.
  Future<int> deleteEmptyRecordings({
    required Future<File> Function(String relativePath) resolveAudio,
    required int minimumBytes,
  }) async {
    final rows = await _db.query('segment', columns: ['id', 'audio_path']);
    var deleted = 0;

    for (final row in rows) {
      final id = row['id'] as int;
      final file = await resolveAudio(row['audio_path'] as String);

      // Absence proves nothing. Leave it.
      if (!await file.exists()) continue;
      if (await file.length() >= minimumBytes) continue;

      await _db.delete('segment', where: 'id = ?', whereArgs: [id]);
      await file.delete();
      deleted++;
      debugPrint('removed empty segment $id — ${row['audio_path']}');
    }
    return deleted;
  }
}
