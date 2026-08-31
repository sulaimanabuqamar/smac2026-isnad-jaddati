import 'package:flutter_test/flutter_test.dart';
import 'package:jaddati/data/db.dart';
import 'package:jaddati/data/person_repository.dart';
import 'package:jaddati/data/session_repository.dart';
import 'package:jaddati/models/person.dart';
import 'package:jaddati/models/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tests run on the desktop VM, where the sqflite plugin does not exist —
/// it is Android and iOS platform code. sqflite_common_ffi swaps in a real
/// SQLite compiled for the host, so these tests exercise the actual SQL,
/// including the CHECK constraints and the cascades, rather than a fake.
///
/// `inMemoryDatabasePath` gives each test a database that never touches the
/// disk and vanishes when the connection closes, so tests cannot leak state
/// into one another.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late PersonRepository people;
  late SessionRepository sessions;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        onConfigure: AppDatabase.configure,
        onCreate: (db, _) => AppDatabase.createSchema(db),
      ),
    );
    people = PersonRepository(db);
    sessions = SessionRepository(db);
  });

  tearDown(() async => db.close());

  Person fatima({String name = 'Fatima'}) => Person(
        name: name,
        nameAr: 'فاطمة',
        relation: 'Grandmother',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1756600000000),
      );

  group('create and read', () {
    test('create returns a usable id and the row reads back identically',
        () async {
      final id = await people.create(fatima());

      expect(id, greaterThan(0));

      final read = await people.getById(id);
      expect(read, isNotNull);
      expect(read!.id, id);
      expect(read.name, 'Fatima');
      expect(read.nameAr, 'فاطمة');
      expect(read.relation, 'Grandmother');
      expect(read.photoPath, isNull);
      // Timestamps survive the trip through the integer column intact.
      expect(read.createdAt.millisecondsSinceEpoch, 1756600000000);
    });

    test('getById returns null for an id that does not exist', () async {
      expect(await people.getById(999), isNull);
    });

    test('getAll is empty on a fresh database', () async {
      expect(await people.getAll(), isEmpty);
    });

    test('getAll sorts by name, case-insensitively', () async {
      await people.create(fatima(name: 'zainab'));
      await people.create(fatima(name: 'Ahmed'));
      await people.create(fatima(name: 'khalid'));

      final names = (await people.getAll()).map((p) => p.name).toList();
      expect(names, ['Ahmed', 'khalid', 'zainab']);
    });
  });

  group('update', () {
    test('changes the stored row and leaves other fields alone', () async {
      final id = await people.create(fatima());
      final original = (await people.getById(id))!;

      final changed = await people.update(
        original.copyWith(relation: 'Great-grandmother'),
      );

      expect(changed, 1, reason: 'exactly one row should have been updated');

      final read = await people.getById(id);
      expect(read!.relation, 'Great-grandmother');
      expect(read.name, 'Fatima', reason: 'untouched fields must survive');
      expect(read.nameAr, 'فاطمة');
    });

    test('reports 0 rows changed when the id is not in the table', () async {
      final ghost = fatima().copyWith(id: 999);
      expect(await people.update(ghost), 0);
    });

    test('refuses to update a person that was never saved', () async {
      expect(() => people.update(fatima()), throwsArgumentError);
    });
  });

  group('delete', () {
    test('removes the row and reports one deletion', () async {
      final id = await people.create(fatima());

      expect(await people.delete(id), 1);
      expect(await people.getById(id), isNull);
      expect(await people.getAll(), isEmpty);
    });

    test('reports 0 for an id that is not there', () async {
      expect(await people.delete(999), 0);
    });

    test('cascades to the sessions belonging to that person', () async {
      final id = await people.create(fatima());
      await sessions.create(
        Session(personId: id, startedAt: DateTime(2026, 8, 31)),
      );
      expect(await sessions.getForPerson(id), hasLength(1));

      await people.delete(id);

      // This assertion is really testing PRAGMA foreign_keys = ON. Without
      // it SQLite accepts the delete and silently strands the session rows.
      expect(await sessions.getForPerson(id), isEmpty);
    });
  });

  group('getAllWithCounts', () {
    test('a person with nothing recorded counts zero and zero', () async {
      await people.create(fatima());

      final rows = await people.getAllWithCounts();
      expect(rows, hasLength(1));
      expect(rows.single.person.name, 'Fatima');
      expect(rows.single.sessionCount, 0);
      expect(rows.single.storyCount, 0);
    });

    test('counts every session, but only finished ones as stories', () async {
      final id = await people.create(fatima());

      // Two finished, one still open.
      await sessions.create(Session(
        personId: id,
        startedAt: DateTime(2026, 8, 1),
        endedAt: DateTime(2026, 8, 1, 1),
      ));
      await sessions.create(Session(
        personId: id,
        startedAt: DateTime(2026, 8, 2),
        endedAt: DateTime(2026, 8, 2, 1),
      ));
      await sessions.create(
        Session(personId: id, startedAt: DateTime(2026, 8, 3)),
      );

      final row = (await people.getAllWithCounts()).single;
      expect(row.sessionCount, 3);
      expect(row.storyCount, 2,
          reason: 'an unfinished session is not yet a story');
    });

    test('counts stay with the right person', () async {
      final fatimaId = await people.create(fatima());
      final ahmedId = await people.create(fatima(name: 'Ahmed'));

      await sessions.create(Session(
        personId: fatimaId,
        startedAt: DateTime(2026, 8, 1),
        endedAt: DateTime(2026, 8, 1, 1),
      ));

      final rows = await people.getAllWithCounts();
      final byName = {for (final r in rows) r.person.name: r};

      expect(byName['Fatima']!.sessionCount, 1);
      expect(byName['Fatima']!.storyCount, 1);
      expect(byName['Ahmed']!.sessionCount, 0,
          reason: 'the subquery must be correlated to each person row');
      expect(byName['Ahmed']!.storyCount, 0);
      expect(ahmedId, isNot(fatimaId));
    });
  });
}
