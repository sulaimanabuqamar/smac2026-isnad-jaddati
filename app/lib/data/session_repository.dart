import 'package:sqflite/sqflite.dart';

import '../models/session.dart';

/// Create and read for `session`. Update and delete arrive with the slice
/// that needs them — ending a session and editing a story card are both
/// later work, and a method written now would be written against a guess.
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
