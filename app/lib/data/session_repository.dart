import 'package:sqflite/sqflite.dart';

import '../models/session.dart';

/// Create and read for `session`, plus ending one.
///
/// `end` arrived in Slice 2, which is the slice that needed it. Editing a
/// story card — title, place, decade, summary — is still not here, because
/// the extraction call that produces those fields does not exist yet and a
/// method written now would be written against a guess.
class SessionRepository {
  SessionRepository(this._db);

  final Database _db;

  Future<int> create(Session session) =>
      _db.insert('session', session.toMap());

  Future<Session?> getById(int id) async {
    final rows = await _db.query(
      'session',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Session.fromMap(rows.first);
  }

  /// Most recent first: the archive reads newest-at-top.
  Future<List<Session>> getForPerson(int personId) async {
    final rows = await _db.query(
      'session',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'started_at DESC',
    );
    return rows.map(Session.fromMap).toList();
  }

  /// Marks a session finished. Returns rows changed, so 0 means there was
  /// no such session — which is a real possibility if it was deleted with
  /// the person while the interview screen was open.
  ///
  /// Only `ended_at` is written. Nothing else about a session changes when
  /// it ends, and touching more columns would risk clobbering a title the
  /// extraction call had already set.
  Future<int> end(int sessionId, DateTime endedAt) => _db.update(
        'session',
        {'ended_at': endedAt.millisecondsSinceEpoch},
        where: 'id = ? AND ended_at IS NULL',
        whereArgs: [sessionId],
      );

  /// The one unfinished session, if there is one, so "resume" on the person
  /// screen has something to resume. Ordered so that if a bug ever leaves
  /// two open, we get the newest rather than an arbitrary one.
  Future<Session?> getUnfinishedForPerson(int personId) async {
    final rows = await _db.query(
      'session',
      where: 'person_id = ? AND ended_at IS NULL',
      whereArgs: [personId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Session.fromMap(rows.first);
  }
}
