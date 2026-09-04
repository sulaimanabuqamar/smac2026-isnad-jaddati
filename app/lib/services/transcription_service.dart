import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The outcome of asking the cloud to transcribe one audio file.
///
/// A sealed class rather than a nullable string, because the caller has to
/// behave differently for "no signal" and "this file will never work", and a
/// null cannot tell them apart. The compiler makes the queue handle both.
sealed class TranscriptionResult {
  const TranscriptionResult();
}

/// Arabic text we are willing to show as her words.
class Transcribed extends TranscriptionResult {
  const Transcribed(this.textAr);

  final String textAr;
}

/// Why a transcription did not produce usable text.
///
/// The only distinction the queue acts on is [transient]. Everything else
/// here exists so a failure can be explained to the user in their own terms
/// instead of as a status code.
enum TranscriptionFailure {
  /// No API key was compiled into this build. Nothing to retry until there
  /// is one, but the audio is untouched and the row stays pending.
  noKey(transient: true, message: 'This build has no transcription key.'),

  /// The request never reached Groq: aeroplane mode, thick walls, a dead
  /// hotspot. The overwhelmingly common failure and the one the whole
  /// decoupled design exists for.
  offline(transient: true, message: 'No connection — this will finish later.'),

  /// HTTP 429. The free tier has a rate limit and we are inside it. Waiting
  /// is the correct and only response.
  rateLimited(transient: true, message: 'Too many requests — waiting a moment.'),

  /// HTTP 5xx. Their problem, not ours, and it usually passes.
  serverError(transient: true, message: 'Transcription service is down.'),

  /// HTTP 4xx that is not 429: a bad key, a file too large, a format the
  /// endpoint refuses. Retrying the identical request gets the identical
  /// answer, so the row is marked failed rather than looped on.
  rejected(transient: false, message: 'That recording was refused.'),

  /// The row points at a file that is no longer on the phone.
  audioMissing(transient: false, message: 'That audio file is missing.'),

  /// The guard from docs/asr-failure-modes.md: text came back, but far too
  /// little of it for the length of the audio. Almost certainly Whisper's
  /// "subscribe to the channel" artefact rather than anything she said.
  implausible(
      transient: false, message: 'That did not transcribe cleanly.');

  const TranscriptionFailure({required this.transient, required this.message});

  /// True when trying the same request again later could succeed.
  ///
  /// The queue reads only this. Transient means stop and leave the row
  /// pending; permanent means mark it failed and move on to the next.
  final bool transient;

  /// What a person is told. No status codes, no jargon.
  final String message;
}

class TranscriptionRejected extends TranscriptionResult {
  const TranscriptionRejected(this.reason, {this.detail});

  final TranscriptionFailure reason;

  /// Server text, kept for the log and never shown on screen.
  final String? detail;
}

/// Sends one audio file to Groq's Whisper endpoint and returns Arabic text.
///
/// Stateless and knows nothing about the database. It takes a file and gives
/// back a result; deciding what that means for a row is the queue's job.
/// Keeping those apart is what lets the guard below be unit-tested without a
/// network, a device, or a key.
class TranscriptionService {
  TranscriptionService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  /// Compiled in with `--dart-define-from-file=.env`. Empty in a build where
  /// nobody supplied one, which is a state the app is required to survive.
  final String apiKey;

  final http.Client _client;

  static final _endpoint =
      Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');

  /// `whisper-large-v3-turbo`, not `whisper-large-v3`.
  ///
  /// Chosen on evidence, not on it being newer: plain v3 returned the
  /// hallucinated phrase "اشتركوا في القناة" on two unrelated clips in our
  /// spike, and turbo returned real text for both. The full working is in
  /// docs/asr-failure-modes.md.
  static const model = 'whisper-large-v3-turbo';

  /// Telling it the language is Arabic made no measurable difference on v3
  /// and a small positive one on turbo, and it removes a whole class of
  /// failure where the model guesses Farsi or Urdu from a few words.
  static const language = 'ar';

  /// Long enough for a 90-second segment to upload over a bad connection,
  /// short enough that a dead network is reported rather than hung on. The
  /// user is never waiting on this — the interview has already moved on.
  static const timeout = Duration(seconds: 60);

  /// Below this many characters of transcript per second of audio, we do not
  /// believe the transcript.
  ///
  /// Conversational Arabic runs about 10–12 characters a second. Both
  /// hallucinations we caught came in at 1.2 and 1.6. Two is a fifth of
  /// normal speech and still comfortably above both failures — deliberately
  /// far from either edge, because this is a threshold picked from two data
  /// points and not a calibrated one.
  static const minCharsPerSecond = 2.0;

  /// The guard is not applied to very short audio. A three-second answer that
  /// is genuinely "نعم" is two characters and would trip any ratio rule.
  static const guardAppliesOver = Duration(seconds: 5);

  /// The cheapest possible hallucination detector: too few characters for
  /// too much audio. No second model call, no heuristics about content.
  ///
  /// A false positive costs one bank question instead of one AI question,
  /// which is the fallback the app already has for having no signal. A false
  /// negative puts words in her mouth. The asymmetry is why this leans
  /// towards rejecting.
  static bool isImplausible(String text, Duration? audio) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (audio == null || audio <= guardAppliesOver) return false;
    final perSecond = trimmed.length / audio.inMilliseconds * 1000;
    return perSecond < minCharsPerSecond;
  }

  /// Transcribes [file]. [audioDuration] is used only by the guard.
  Future<TranscriptionResult> transcribe(
    File file, {
    Duration? audioDuration,
  }) async {
    if (apiKey.isEmpty) {
      return const TranscriptionRejected(TranscriptionFailure.noKey);
    }
    if (!await file.exists()) {
      return const TranscriptionRejected(TranscriptionFailure.audioMissing);
    }

    final request = http.MultipartRequest('POST', _endpoint)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = model
      ..fields['language'] = language
      // Zero temperature so the same audio gives the same text. A creative
      // transcriber is not a thing anyone wants.
      ..fields['temperature'] = '0'
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on Object catch (e) {
      // SocketException, HandshakeException, TimeoutException, and whatever
      // else a dying connection produces. They all mean the same thing to us
      // and they all mean try again later, so they are caught as one.
      return TranscriptionRejected(
        TranscriptionFailure.offline,
        detail: e.toString(),
      );
    }

    if (response.statusCode == 429) {
      return TranscriptionRejected(
        TranscriptionFailure.rateLimited,
        detail: response.body,
      );
    }
    if (response.statusCode >= 500) {
      return TranscriptionRejected(
        TranscriptionFailure.serverError,
        detail: response.body,
      );
    }
    if (response.statusCode != 200) {
      return TranscriptionRejected(
        TranscriptionFailure.rejected,
        detail: response.body,
      );
    }

    // The body is UTF-8 Arabic. `response.body` decodes as Latin-1 unless the
    // server sends a charset, and Groq does not always. Decoding the bytes
    // ourselves is the difference between text and mojibake.
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    final text = (decoded['text'] as String? ?? '').trim();

    if (isImplausible(text, audioDuration)) {
      return TranscriptionRejected(
        TranscriptionFailure.implausible,
        detail: text,
      );
    }
    return Transcribed(text);
  }

  void dispose() => _client.close();
}
