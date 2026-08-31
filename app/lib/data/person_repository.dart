import 'package:sqflite/sqflite.dart';

import '../models/person.dart';

/// Every SQL statement that touches the `person` table lives here.
///
/// Screens call methods on this class and get models back. They never see a
/// query string. That boundary is why the database can change shape without
/// a screen changing, and why these methods can be tested without a widget.
class PersonRepository {
  PersonRepository(this._db);

  final Database _db;

  /// Inserts and returns the new row's id.
  ///
  /// `createdAt` is taken from the model rather than defaulted in SQL, so a
  /// test can insert a person with a known timestamp.
  Future<int> create(Person person) =>
      _db.insert('person', person.toMap());

  Future<Person?> getById(int id) async {
    final rows = await _db.query(
      'person',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Person.fromMap(rows.first);
  }

  Future<List<Person>> getAll() async {
    final rows = await _db.query('person', orderBy: 'name COLLATE NOCASE');
    return rows.map(Person.fromMap).toList();
  }

  /// Returns the number of rows changed, which is 0 if the id does not exist.
  /// The caller can tell "updated" from "there was nothing to update".
  Future<int> update(Person person) {
    final id = person.id;
    if (id == null) {
      throw ArgumentError('Cannot update a person that has no id');
    }
    return _db.update(
      'person',
      person.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes the person. Their sessions, segments and mentions go with them
  /// through ON DELETE CASCADE — provided foreign keys are on, which
  /// AppDatabase.configure guarantees for every connection.
  Future<int> delete(int id) =>
      _db.delete('person', where: 'id = ?', whereArgs: [id]);

  /// The home screen list: each person with how many sessions they have and
  /// how many of those are finished.
  ///
  /// Done as two correlated subqueries in a single statement rather than a
  /// query per row. With five people the difference does not matter; the
  /// reason to write it this way is that the list stays one round trip to
  /// the database however long it grows.
  ///
  /// A LEFT JOIN with GROUP BY would also work, but counting two different
  /// things — all sessions, and only finished ones — needs two conditional
  /// aggregates and reads worse than this does.
  Future<List<PersonSummary>> getAllWithCounts() async {
    final rows = await _db.rawQuery('''
      SELECT
        p.*,
        (SELECT COUNT(*) FROM session s
          WHERE s.person_id = p.id)                      AS session_count,
        (SELECT COUNT(*) FROM session s
          WHERE s.person_id = p.id
            AND s.ended_at IS NOT NULL)                  AS story_count
      FROM person p
      ORDER BY p.name COLLATE NOCASE
    ''');

    return rows
        .map((row) => PersonSummary(
              person: Person.fromMap(row),
              sessionCount: row['session_count'] as int,
              storyCount: row['story_count'] as int,
            ))
        .toList();
  }
}
