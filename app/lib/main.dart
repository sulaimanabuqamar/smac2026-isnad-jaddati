import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart';

import 'data/db.dart';
import 'data/person_repository.dart';
import 'screens/archive_screen.dart';
import 'screens/people_screen.dart';
import 'screens/settings_screen.dart';
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
  JaddatiApp({super.key, required Database db})
      : people = PersonRepository(db);

  /// Built once and handed to the screens that need it.
  ///
  /// This is the whole of our dependency injection: construct the thing at
  /// the top and pass it down. No service locator, no provider, no global.
  /// A screen's constructor states exactly what that screen can reach.
  final PersonRepository people;

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

      home: PeopleScreen(people: people),
    );
  }
}
