import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart';

import 'data/bank_question_repository.dart';
import 'data/db.dart';
import 'data/person_repository.dart';
import 'data/segment_repository.dart';
import 'data/session_repository.dart';
import 'screens/archive_screen.dart';
import 'screens/people_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_keys.dart';
import 'services/transcription_queue.dart';
import 'services/transcription_service.dart';
import 'theme.dart';

Future<void> main() async {
  // Required before any plugin is touched, and sqflite is a plugin. Opening
  // the database here rather than inside a widget means the app is either
  // running with a working database or has not started — no screen ever has
  // to render a "database not ready yet" state.
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.instance.database;
  runApp(JaddatiApp(db: db));
}

class JaddatiApp extends StatelessWidget {
  /// A factory rather than an initialiser list because the queue needs the
  /// same [SegmentRepository] the screens get, and an initialiser list cannot
  /// refer to a field it is still building. Two repositories over one
  /// database would work, but "which one is the real one" is a question
  /// nobody should have to answer.
  factory JaddatiApp({Key? key, required Database db}) {
    final segments = SegmentRepository(db);
    return JaddatiApp._(
      key: key,
      people: PersonRepository(db),
      sessions: SessionRepository(db),
      segments: segments,
      bank: BankQuestionRepository(db),
      transcription: TranscriptionQueue(
        segments: segments,
        service: TranscriptionService(apiKey: ApiKeys.groq),
      ),
    );
  }

  const JaddatiApp._({
    super.key,
    required this.people,
    required this.sessions,
    required this.segments,
    required this.bank,
    required this.transcription,
  });

  /// Built once and handed to the screens that need it.
  ///
  /// This is the whole of our dependency injection: construct the thing at
  /// the top and pass it down. No service locator, no provider, no global.
  /// A screen's constructor states exactly what that screen can reach.
  final PersonRepository people;
  final SessionRepository sessions;
  final SegmentRepository segments;
  final BankQuestionRepository bank;

  /// One queue for the whole app, not one per interview.
  ///
  /// The queue holds work that outlives the screen that created it: a
  /// segment recorded in the kitchen and uploaded twenty minutes later in
  /// the car. Building it per-screen would abandon that work — and would let
  /// two screens upload the same row twice.
  final TranscriptionQueue transcription;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jaddati',
      debugShowCheckedModeBanner: false,
      theme: JaddatiTheme.light,

      // The interface chrome is English and stays English, so the app is
      // pinned to `en` rather than following the phone's language. Arabic is
      // content, not interface: it appears because a grandmother said it, and
      // it is laid out right-to-left by the Directionality inside
      // ArabicText. Letting the whole app flip to RTL on an Arabic phone
      // would mirror the layout around content that is already bilingual,
      // which helps nobody.
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('ar')],

      // Arabic is still declared as supported so Flutter loads its text
      // handling — line breaking, selection handles and the cursor behave
      // correctly in the Arabic fields on the add-person screen.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Named routes for the screens that need nothing to be built. Screens
      // that take a Person are pushed with a typed constructor instead — see
      // the note in interview_screen.dart for why.
      routes: {
        ArchiveScreen.route: (_) => const ArchiveScreen(),
        SettingsScreen.route: (_) => const SettingsScreen(),
      },

      home: PeopleScreen(
        people: people,
        sessions: sessions,
        segments: segments,
        bank: bank,
        transcription: transcription,
      ),
    );
  }
}
