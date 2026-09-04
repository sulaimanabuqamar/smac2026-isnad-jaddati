/// The two cloud keys, and where they come from.
///
/// They arrive as compile-time constants, not as a file the app reads at
/// startup:
///
/// ```
/// flutter run   --dart-define-from-file=.env
/// flutter build ipa --dart-define-from-file=.env
/// ```
///
/// `.env` is gitignored and `.env.example` is committed blank, exactly as
/// docs/spec.md section 11 says. The Flutter SDK reads that file itself and
/// turns each line into a `String.fromEnvironment` value, which is why this
/// app no longer depends on `flutter_dotenv` — see docs/walkthrough-slice3.md.
///
/// The honest caveat has not changed: a key inside any client app is
/// extractable by anyone who wants it, whether it is bundled as an asset or
/// baked into the binary. The real answer is a proxy server holding the key,
/// and we scoped that out for eight days rather than pretend otherwise.
class ApiKeys {
  const ApiKeys._();

  /// Whisper, for transcription. Empty when nobody passed one, which is a
  /// state the app is required to survive: recording works with no key at
  /// all, and every segment simply stays in the queue.
  static const groq = String.fromEnvironment('GROQ_API_KEY');

  /// Gemini, for follow-up questions and story extraction. Unused until
  /// Slice 4; declared here so both keys are described in one place.
  static const gemini = String.fromEnvironment('GEMINI_API_KEY');
}
