import 'package:sqflite/sqflite.dart';

import '../models/bank_question.dart';

/// Reads the offline question bank seeded from `assets/questions/bank.json`.
///
/// Read-only. The bank ships with the app and nothing in the app writes to it.
class BankQuestionRepository {
  BankQuestionRepository(this._db);

  final Database _db;

  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM bank_question');
    return rows.first['n'] as int;
  }

  /// The question to ask at position [index] in a session, counting from 0.
  ///
  /// Ordered by `rowid`, which is the order the questions appear in
  /// `bank.json`, which is the order they were deliberately written in:
  /// childhood, then home, then work, then family, traditions, change. A
  /// session opens on "where were you living when you were small?" and works
  /// outward. That progression is the reason not to pick at random — random
  /// could open a session by asking about someone's death.
  ///
  /// Note it is NOT ordered by `id`. The ids sort alphabetically, which puts
  /// `chg_01` — the "change" topic, the heaviest questions in the bank —
  /// ahead of `child_01`. That was the first version of this method and a
  /// test caught it.
  ///
  /// The index wraps once the bank runs out, so a long session never reaches
  /// a dead end with nothing to ask. In practice this should not be hit:
  /// from Slice 3 the question comes from the model and the bank is the
  /// offline fallback, not the main path.
  Future<BankQuestion?> questionAt(int index) async {
    final total = await count();
    if (total == 0) return null;

    final rows = await _db.query(
      'bank_question',
      orderBy: 'rowid',
      limit: 1,
      offset: index % total,
    );
    return rows.isEmpty ? null : BankQuestion.fromMap(rows.first);
  }
}
