import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../data/bank_question_repository.dart';
import '../data/segment_repository.dart';
import '../data/session_repository.dart';
import '../models/bank_question.dart';
import '../models/person.dart';
import '../models/segment.dart';
import '../models/session.dart';
import '../services/audio_files.dart';
import '../services/audio_service.dart';
import '../services/transcription_queue.dart';
import '../services/transcription_service.dart';
import '../theme.dart';
import '../widgets/bilingual.dart';

/// The interview loop: one question, one answer, one file. Repeat.
///
/// From Slice 3 the transcripts appear underneath the answers, but note what
/// did not change: nothing on the recording path awaits the network. Saving a
/// segment hands the queue a row and returns immediately. If transcription is
/// slow, failing or impossible, this screen behaves exactly as it did in
/// Slice 2 — which is the reliability rule in CLAUDE.md, made structural.
///
/// The question still comes from the offline bank. Generating it from what
/// she just said is Slice 4 and reads the transcripts this slice writes.
class InterviewScreen extends StatefulWidget {
  const InterviewScreen({
    super.key,
    required this.person,
    required this.sessions,
    required this.segments,
    required this.bank,
    required this.audio,
    required this.transcription,
  });

  final Person person;
  final SessionRepository sessions;
  final SegmentRepository segments;
  final BankQuestionRepository bank;
  final AudioService audio;
  final TranscriptionQueue transcription;

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

    // The queue writes to the database from outside this screen, so the
    // screen has to be told when to re-read. One listener, one reload — this
    // is the whole reason ChangeNotifier is enough and a state-management
    // package is not.
    widget.transcription.addListener(_onQueueChanged);

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
    widget.transcription.removeListener(_onQueueChanged);
    _player.dispose();
    widget.audio.dispose();
    // The queue itself is not disposed here. It belongs to the app, not to
    // this screen, and it has work to finish after we are gone.
    super.dispose();
  }

  /// Re-reads this session's rows because the queue changed something.
  ///
  /// Reads from the database rather than accepting an updated segment from
  /// the queue, so there is exactly one place transcripts come from and no
  /// chance of the screen and the database disagreeing about a row.
  Future<void> _onQueueChanged() async {
    final session = _session;
    if (session == null) return;
    final segments = await widget.segments.getForSession(session.id!);
    if (!mounted) return;
    setState(() => _segments = segments);
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

    // Opening the screen is a good moment to try again: the phone may have
    // found signal since the last time anything ran, and there may be rows
    // waiting from a session that ended days ago.
    unawaited(widget.transcription.run());
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
        audioPath: recording.relativePath,
        durationMs: recording.durationMs,
        createdAt: DateTime.now(),
      ),
    );

    // Not awaited, and that is the design. The row and its file are already
    // safe; the upload is somebody else's problem now. Awaiting here would
    // put the network between her answer and the next question, which is
    // exactly the coupling decision D1 exists to prevent.
    unawaited(widget.transcription.run());

    final segments = await widget.segments.getForSession(session.id!);
    final next = await widget.bank.questionAt(segments.length);

    if (!mounted) return;
    setState(() {
      _segments = segments;
      _question = next;
      _phase = _Phase.ready;
    });
  }

  /// Puts one failed segment back in the queue, because the user asked.
  Future<void> _retryTranscription(Segment segment) async {
    await widget.transcription.retry(segment.id!);
  }

  Future<void> _play(Segment segment) async {
    if (_playingPath == segment.audioPath) {
      await _player.stop();
      if (mounted) setState(() => _playingPath = null);
      return;
    }
    try {
      // Resolved against this install, not against the one that recorded it.
      final file = await AudioFiles.resolve(segment.audioPath);
      await _player.setFilePath(file.path);
      await _player.play();
      if (mounted) setState(() => _playingPath = segment.audioPath);
    } catch (_) {
      // The row exists but the file does not. Before schema version 2 this
      // was reached after every reinstall, because the stored path pointed
      // into a container UUID that no longer existed — the file was there
      // and we were looking in the wrong place. Now it means what it says.
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
                      transcribing:
                          widget.transcription.activeSegmentId == s.id,
                      onPlay: () => _play(s),
                      onRetry: () => _retryTranscription(s),
                    );
                  },
                ),
        ),

        _QueueBanner(
          paused: widget.transcription.pausedBy,
          waiting: _segments
              .where((s) => s.transcribeStatus == TranscribeStatus.pending)
              .length,
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

/// One saved answer: play it, read it, and see where its transcript got to.
///
/// The question is the quiet line and her words are the loud one. That is the
/// right way round — the question is ours and the answer is hers.
class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.playing,
    required this.transcribing,
    required this.onPlay,
    required this.onRetry,
  });

  final Segment segment;
  final bool playing;

  /// True only for the one segment being uploaded right now. Queue state,
  /// not database state — there is no `transcribing` row in the schema,
  /// because if the app were killed mid-upload that row would be stuck in it
  /// forever with nothing to move it back.
  final bool transcribing;

  final VoidCallback onPlay;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final transcript = segment.transcriptAr;
    final failed = segment.transcribeStatus == TranscribeStatus.failed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              icon: Icon(
                playing
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                size: 34,
                color: JaddatiTheme.clay,
              ),
              onPressed: onPlay,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ArabicText(
                    segment.questionText,
                    maxLines: 2,
                    style: JaddatiTheme.arabic.copyWith(
                      fontSize: 17,
                      height: 1.5,
                      color: JaddatiTheme.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Her answer, if we have it. Full size and full colour,
                  // and never truncated: this is the thing being kept.
                  if (transcript != null && transcript.isNotEmpty)
                    ArabicText(transcript)
                  else
                    _TranscriptPending(
                      transcribing: transcribing,
                      failed: failed,
                    ),

                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${segment.seq}  ·  ${_length(segment.durationMs)}',
                        style: JaddatiTheme.english.copyWith(fontSize: 15),
                      ),
                      const Spacer(),
                      if (failed)
                        TextButton(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Try again'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
}

/// The placeholder where a transcript will go.
///
/// Deliberately worded so that none of these three states reads like
/// something was lost. The audio is saved in all of them, and the only thing
/// at stake is text we can ask for again.
class _TranscriptPending extends StatelessWidget {
  const _TranscriptPending({required this.transcribing, required this.failed});

  final bool transcribing;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch ((transcribing, failed)) {
      (true, _) => (Icons.cloud_upload_outlined, 'Transcribing…'),
      (_, true) => (Icons.error_outline, 'Could not transcribe — audio saved'),
      _ => (Icons.schedule, 'Waiting to transcribe'),
    };

    return Row(
      children: [
        Icon(icon, size: 17, color: JaddatiTheme.inkSoft),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: JaddatiTheme.english.copyWith(
              fontSize: 15,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

/// A line above the record button, shown only when the queue is stuck.
///
/// It exists to make the offline path visible instead of merely survivable.
/// Without it, a session recorded in a basement looks like a session where
/// transcription is broken; with it, the app has told you what it is waiting
/// for and that your recordings are fine.
class _QueueBanner extends StatelessWidget {
  const _QueueBanner({required this.paused, required this.waiting});

  final TranscriptionFailure? paused;
  final int waiting;

  @override
  Widget build(BuildContext context) {
    final reason = paused;
    if (reason == null || waiting == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: JaddatiTheme.linen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 19, color: JaddatiTheme.inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${reason.message}  '
              '$waiting ${waiting == 1 ? 'answer is' : 'answers are'} '
              'saved on this phone and will transcribe later.',
              style: JaddatiTheme.english.copyWith(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
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
