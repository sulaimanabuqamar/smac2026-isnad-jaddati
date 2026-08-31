import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../data/bank_question_repository.dart';
import '../data/segment_repository.dart';
import '../data/session_repository.dart';
import '../models/bank_question.dart';
import '../models/person.dart';
import '../models/segment.dart';
import '../models/session.dart';
import '../services/audio_service.dart';
import '../theme.dart';
import '../widgets/bilingual.dart';

/// The interview loop: one question, one answer, one file. Repeat.
///
/// No AI in this screen. The question comes from the offline bank seeded at
/// first run, and the recording never leaves the phone. Transcription is
/// Slice 3 and hangs off the rows this screen writes.
class InterviewScreen extends StatefulWidget {
  const InterviewScreen({
    super.key,
    required this.person,
    required this.sessions,
    required this.segments,
    required this.bank,
    required this.audio,
  });

  final Person person;
  final SessionRepository sessions;
  final SegmentRepository segments;
  final BankQuestionRepository bank;
  final AudioService audio;

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

/// What the screen is doing. One field instead of four booleans, so the
/// impossible combinations — recording while the permission is denied —
/// cannot be represented.
enum _Phase { loading, blocked, ready, recording, saving }

class _InterviewScreenState extends State<InterviewScreen> {
  final AudioPlayer _player = AudioPlayer();

  _Phase _phase = _Phase.loading;
  RecordingBlocker? _blocker;

  Session? _session;
  BankQuestion? _question;
  List<Segment> _segments = const [];

  /// Path of the segment currently playing, so only that row shows a stop
  /// icon. Null when nothing is playing.
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _bootstrap();

    // The player does not tell us when it stops unless we ask. Without this
    // the play icon on a finished segment stays a stop icon forever.
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() => _playingPath = null);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    widget.audio.dispose();
    super.dispose();
  }

  /// Finds the session to work in, or starts one.
  ///
  /// Resuming an unfinished session rather than always creating a new one is
  /// what makes an interrupted Friday afternoon recoverable — the spec calls
  /// for it on the person-picker screen and this is the other half of it.
  Future<void> _bootstrap() async {
    final personId = widget.person.id!;
    var session = await widget.sessions.getUnfinishedForPerson(personId);

    if (session == null) {
      final id = await widget.sessions.create(
        Session(personId: personId, startedAt: DateTime.now()),
      );
      session = await widget.sessions.getById(id);
    }

    final segments = await widget.segments.getForSession(session!.id!);
    final question = await widget.bank.questionAt(segments.length);

    if (!mounted) return;
    setState(() {
      _session = session;
      _segments = segments;
      _question = question;
      _phase = _Phase.ready;
    });
  }

  Future<void> _startRecording() async {
    final session = _session;
    if (session == null) return;

    final seq = await widget.segments.nextSeq(session.id!);
    final blocker =
        await widget.audio.start(sessionId: session.id!, seq: seq);

    if (!mounted) return;
    if (blocker != null) {
      setState(() {
        _blocker = blocker;
        _phase = _Phase.blocked;
      });
      return;
    }
    setState(() => _phase = _Phase.recording);
  }

  /// Stop, then save. The order here is the whole point of the slice.
  ///
  /// `audio.stop()` does not return until the file is closed on disk and has
  /// been confirmed to have bytes in it. Only then is a row inserted, and the
  /// row carries `audio_path` from the start. There is no window in which the
  /// database believes in a recording that does not exist, and no later step
  /// that "fills in" the path.
  ///
  /// A null return means the file never materialised, so nothing is written
  /// at all — we would rather have no row than a row that plays silence.
  Future<void> _stopAndSave() async {
    setState(() => _phase = _Phase.saving);

    final session = _session!;
    final question = _question;
    final recording = await widget.audio.stop();

    if (!mounted) return;

    if (recording == null) {
      setState(() => _phase = _Phase.ready);
      _tell('That recording did not save. Nothing was lost — try again.');
      return;
    }

    final seq = await widget.segments.nextSeq(session.id!);
    await widget.segments.create(
      Segment(
        sessionId: session.id!,
        seq: seq,
        questionText: question?.textAr ?? '',
        questionSource: QuestionSource.bank,
        audioPath: recording.path,
        durationMs: recording.durationMs,
        createdAt: DateTime.now(),
      ),
    );

    final segments = await widget.segments.getForSession(session.id!);
    final next = await widget.bank.questionAt(segments.length);

    if (!mounted) return;
    setState(() {
      _segments = segments;
      _question = next;
      _phase = _Phase.ready;
    });
  }

  Future<void> _play(Segment segment) async {
    if (_playingPath == segment.audioPath) {
      await _player.stop();
      if (mounted) setState(() => _playingPath = null);
      return;
    }
    try {
      await _player.setFilePath(segment.audioPath);
      await _player.play();
      if (mounted) setState(() => _playingPath = segment.audioPath);
    } catch (_) {
      // The row exists but the file does not — the only way this happens is
      // if something outside the app removed it. Say so rather than crash.
      if (mounted) _tell('That audio file is missing from this phone.');
    }
  }

  Future<void> _endSession() async {
    final session = _session;
    if (session == null) return;

    if (widget.audio.isRecording) await widget.audio.cancel();
    await widget.sessions.end(session.id!, DateTime.now());
    if (mounted) Navigator.of(context).pop();
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retryPermission() async {
    setState(() => _phase = _Phase.loading);
    final granted = await widget.audio.hasPermission();
    if (!mounted) return;
    setState(() => _phase = granted ? _Phase.ready : _Phase.blocked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.person.name),
        actions: [
          if (_session != null && _phase != _Phase.loading)
            TextButton(
              onPressed: _phase == _Phase.saving ? null : _endSession,
              child: const Text('Finish'),
            ),
        ],
      ),
      body: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.blocked => _MicrophoneBlocked(
            blocker: _blocker ?? RecordingBlocker.permissionDenied,
            onRetry: _retryPermission,
          ),
        _ => _interview(),
      },
    );
  }

  Widget _interview() {
    final question = _question;
    final recording = _phase == _Phase.recording;
    final saving = _phase == _Phase.saving;

    return Column(
      children: [
        // The question. Given the top of the screen and plenty of room,
        // because it is the only thing on this screen that anyone reads.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: question == null
              ? Text('No questions in the bank.', style: JaddatiTheme.english)
              : BilingualText(
                  arabic: question.textAr,
                  english: question.textEn,
                  arabicStyle: JaddatiTheme.arabicLarge,
                ),
        ),
        const Divider(height: 32),

        Expanded(
          child: _segments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Read the question out loud, then press record while '
                      'she answers.',
                      textAlign: TextAlign.center,
                      style: JaddatiTheme.english,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _segments.length,
                  itemBuilder: (context, i) {
                    final s = _segments[_segments.length - 1 - i];
                    return _SegmentRow(
                      segment: s,
                      playing: _playingPath == s.audioPath,
                      onPlay: () => _play(s),
                    );
                  },
                ),
        ),

        // The record button lives in the bottom third, per docs/spec.md
        // section 7: it is the one control that gets pressed with a thumb
        // while the other hand is holding tea.
        _RecordButton(
          recording: recording,
          busy: saving,
          onPressed: saving
              ? null
              : recording
                  ? _stopAndSave
                  : _startRecording,
        ),
      ],
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.recording,
    required this.busy,
    required this.onPressed,
  });

  final bool recording;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: recording ? 'Stop recording' : 'Start recording',
            child: GestureDetector(
              onTap: onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: recording ? 96 : 88,
                height: recording ? 96 : 88,
                decoration: BoxDecoration(
                  color: busy
                      ? JaddatiTheme.inkSoft
                      : recording
                          ? JaddatiTheme.clay
                          : JaddatiTheme.clay.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: recording
                      ? [
                          BoxShadow(
                            color: JaddatiTheme.clay.withValues(alpha: 0.35),
                            blurRadius: 24,
                            spreadRadius: 6,
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            busy
                ? 'Saving…'
                : recording
                    ? 'Recording — press to stop'
                    : 'Press to record',
            style: JaddatiTheme.english,
          ),
        ],
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.playing,
    required this.onPlay,
  });

  final Segment segment;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: IconButton(
          icon: Icon(
            playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            size: 34,
            color: JaddatiTheme.clay,
          ),
          onPressed: onPlay,
        ),
        title: ArabicText(segment.questionText, maxLines: 2),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${segment.seq}  ·  ${_length(segment.durationMs)}'
            '  ·  ${_status(segment.transcribeStatus)}',
            style: JaddatiTheme.english.copyWith(fontSize: 15),
          ),
        ),
      ),
    );
  }

  static String _length(int? ms) {
    if (ms == null) return '—';
    final total = Duration(milliseconds: ms).inSeconds;
    final m = total ~/ 60, s = total % 60;
    return m > 0 ? '$m:${s.toString().padLeft(2, '0')}' : '${s}s';
  }

  /// Shown from Slice 2 even though nothing sets it to anything but pending
  /// yet. The queue is visible from the day the rows exist, so "waiting to
  /// be transcribed" is a state the user has seen before it ever matters.
  static String _status(TranscribeStatus status) => switch (status) {
        TranscribeStatus.pending => 'not transcribed yet',
        TranscribeStatus.done => 'transcribed',
        TranscribeStatus.failed => 'transcription failed',
      };
}

/// Shown instead of the interview when the microphone is unavailable.
///
/// A real screen, not a crash and not a snackbar. Denying the microphone is
/// a reasonable thing for someone to do, and the app has to still be usable
/// enough to explain what it needs and let them change their mind.
class _MicrophoneBlocked extends StatelessWidget {
  const _MicrophoneBlocked({required this.blocker, required this.onRetry});

  final RecordingBlocker blocker;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = blocker == RecordingBlocker.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_off_outlined,
                size: 52, color: JaddatiTheme.inkSoft),
            const SizedBox(height: 20),
            Text(
              denied
                  ? 'Jaddati needs the microphone'
                  : 'The microphone is not available',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Recording her voice is the whole point of the app, and '
                      'it cannot ask a question without being able to hear '
                      'the answer.\n\nTurn the microphone on for Jaddati in '
                      'your phone settings, then come back.'
                  : 'Something else may be using it. Close other recording '
                      'apps and try again.',
              textAlign: TextAlign.center,
              style: JaddatiTheme.english.copyWith(height: 1.6),
            ),
            const SizedBox(height: 28),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
