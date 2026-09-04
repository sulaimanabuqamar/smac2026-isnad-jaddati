import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/bank_question_repository.dart';
import '../data/person_repository.dart';
import '../data/segment_repository.dart';
import '../data/session_repository.dart';
import '../services/audio_service.dart';
import '../services/transcription_queue.dart';
import '../models/person.dart';
import '../theme.dart';
import '../widgets/bilingual.dart';
import 'add_person_screen.dart';
import 'archive_screen.dart';
import 'interview_screen.dart';
import 'settings_screen.dart';

/// Home. The list of people whose stories we are keeping.
///
/// State is held with setState and a repository, not a state-management
/// package. There is one piece of state on this screen — the list — and one
/// event that changes it: coming back from somewhere that added a person.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    super.key,
    required this.people,
    required this.sessions,
    required this.segments,
    required this.bank,
    required this.transcription,
  });

  final PersonRepository people;
  final SessionRepository sessions;
  final SegmentRepository segments;
  final BankQuestionRepository bank;
  final TranscriptionQueue transcription;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  /// Null while the first load is in flight, so the screen can tell
  /// "still loading" apart from "loaded, and there is nobody yet". Showing
  /// the empty state during the load would flash the wrong screen.
  List<PersonSummary>? _people;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.people.getAllWithCounts();
    if (!mounted) return;
    setState(() => _people = rows);
  }

  Future<void> _addPerson() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddPersonScreen(people: widget.people),
      ),
    );
    if (added ?? false) await _load();
  }

  /// A fresh AudioService per interview. It owns a platform recorder, and
  /// keeping one alive for the life of the app would hold the microphone
  /// open between sessions.
  Future<void> _openInterview(Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InterviewScreen(
          person: person,
          sessions: widget.sessions,
          segments: widget.segments,
          bank: widget.bank,
          audio: AudioService(),
          transcription: widget.transcription,
        ),
      ),
    );
    // Counts change when a session is started or finished, so the list is
    // stale the moment we come back from an interview.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jaddati'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Archive',
            onPressed: () => Navigator.of(context).pushNamed(ArchiveScreen.route),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.of(context).pushNamed(SettingsScreen.route),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPerson,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add someone'),
      ),
      body: switch (people) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const _EmptyState(),
        _ => RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              itemCount: people.length,
              itemBuilder: (context, i) => _PersonCard(
                summary: people[i],
                onTap: () => _openInterview(people[i].person),
              ),
            ),
          ),
      },
    );
  }
}

/// What a judge sees on a fresh install, and what Maryam sees the first time
/// she opens the app. It has to answer "what is this for" without a tutorial.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.record_voice_over_outlined,
                size: 56, color: JaddatiTheme.clay),
            const SizedBox(height: 24),
            const BilingualText(
              arabic: 'ابدأي بسؤال واحد.',
              english: 'Start with one question.',
              arabicStyle: JaddatiTheme.arabicLarge,
              crossAxisAlignment: CrossAxisAlignment.center,
            ),
            const SizedBox(height: 20),
            Text(
              'Every family has someone who holds the stories, and no one '
              'asks them — because "tell me about your life" is an impossible '
              'question to answer.\n\n'
              'Jaddati asks the questions for you. Add the person you want '
              'to record, and it will take it from there.',
              textAlign: TextAlign.center,
              style: JaddatiTheme.english.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.summary, required this.onTap});

  final PersonSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final person = summary.person;
    final nameAr = person.nameAr;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _Initial(name: person.name),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nameAr != null && nameAr.isNotEmpty)
                      ArabicText(nameAr, style: JaddatiTheme.arabicLarge),
                    Text(
                      person.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (person.relation != null &&
                        person.relation!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(person.relation!, style: JaddatiTheme.english),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _counts(summary),
                      style: JaddatiTheme.english.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: JaddatiTheme.inkSoft),
            ],
          ),
        ),
      ),
    );
  }

  /// Reads as a sentence rather than as two numbers with labels. A person
  /// with nothing recorded gets an invitation, not "0 sessions, 0 stories".
  static String _counts(PersonSummary s) {
    if (s.sessionCount == 0) {
      return 'Nothing recorded yet · added ${DateFormat.MMMd().format(s.person.createdAt)}';
    }
    final sessions =
        '${s.sessionCount} ${s.sessionCount == 1 ? "session" : "sessions"}';
    final stories =
        '${s.storyCount} ${s.storyCount == 1 ? "story" : "stories"}';
    return '$sessions · $stories';
  }
}

/// Stands in for a photo until the photo picker exists. The first letter of
/// the name on a coloured ground reads better than a generic avatar icon,
/// and it is one widget rather than a dependency.
class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: JaddatiTheme.olive,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
