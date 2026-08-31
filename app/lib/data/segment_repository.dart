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
}
