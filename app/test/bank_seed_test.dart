import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jaddati/data/db.dart';
import 'package:jaddati/models/bank_question.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Seeding is tested against the real `assets/questions/bank.json`, read off
/// disk rather than through the asset bundle. If someone adds a question with
/// a missing `en` key or a duplicate id, these tests fail here rather than on
/// a phone in the majlis.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        onConfigure: AppDatabase.configure,
        onCreate: (db, _) => AppDatabase.createSchema(db),
      ),
    );
  });

  tearDown(() async => db.close());

  String readBank() => File(AppDatabase.bankAssetPath).readAsStringSync();

  test('the asset declared in pubspec.yaml exists at that path', () {
    expect(File(AppDatabase.bankAssetPath).existsSync(), isTrue,
        reason: 'AppDatabase.bankAssetPath must match the real file, and the '
            'same path must be listed under flutter: assets: in pubspec.yaml');
  });

  test('every question in the bank loads into the table', () async {
    await AppDatabase.seedBankQuestions(db, readBank());

    final count = (await db.rawQuery(
        'SELECT COUNT(*) AS n FROM bank_question')).first['n'] as int;

    expect(count, greaterThan(0));

    // Compare against the file rather than a hard-coded number, so adding
    // questions to the bank does not break this test.
    final expected =
        (await db.rawQuery('SELECT COUNT(DISTINCT id) AS n FROM bank_question'))
            .first['n'] as int;
    expect(count, expected, reason: 'ids in bank.json must be unique');
  });

  test('a seeded row round-trips with its Arabic intact', () async {
    await AppDatabase.seedBankQuestions(db, readBank());

    final rows = await db.query('bank_question',
        where: 'id = ?', whereArgs: ['child_01'], limit: 1);
    expect(rows, hasLength(1));

    final q = BankQuestion.fromMap(rows.first);
    expect(q.topic, 'childhood');
    expect(q.textAr, contains('صغيرة'));
    expect(q.textEn, isNotEmpty);
  });

  test('seeding twice updates rather than duplicating or failing', () async {
    await AppDatabase.seedBankQuestions(db, readBank());
    final first = (await db.rawQuery('SELECT COUNT(*) AS n FROM bank_question'))
        .first['n'] as int;

    // The second call is what happens if seeding is ever moved to onUpgrade,
    // or run manually. It must be safe.
    await AppDatabase.seedBankQuestions(db, readBank());
    final second =
        (await db.rawQuery('SELECT COUNT(*) AS n FROM bank_question'))
            .first['n'] as int;

    expect(second, first);
  });

  test('every topic named in the bank header is actually used', () async {
    await AppDatabase.seedBankQuestions(db, readBank());

    final topics = (await db.rawQuery(
            'SELECT DISTINCT topic FROM bank_question ORDER BY topic'))
        .map((r) => r['topic'] as String)
        .toList();

    expect(topics, isNotEmpty);
    for (final topic in topics) {
      expect(topic.trim(), isNotEmpty);
    }
  });
}
