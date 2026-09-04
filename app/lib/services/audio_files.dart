import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where a recording lives, and the one rule about how we say so.
///
/// **A stored `audio_path` is always relative to the app documents
/// directory** — `recordings/session_3/seg_1_1757000000.m4a` — and is
/// resolved against that directory every time it is read.
///
/// This is not tidiness. On iOS the app container is a UUID that changes on
/// every install, so an absolute path written by one build is dead in the
/// next one. We shipped that bug: after a reinstall, every recording on the
/// phone was still on disk and every row in the database pointed at a
/// directory that no longer existed. Playback said "that audio file is
/// missing from this phone", and it was not.
///
/// So no caller anywhere touches a raw absolute path. [AudioService] writes
/// through here, the transcription queue and playback read through here, and
/// the invariant is pinned by a test: a stored path never begins with `/`.
class AudioFiles {
  const AudioFiles._();

  /// The directory names of the two roots this app has ever written into.
  ///
  /// iOS gives `.../Application/<uuid>/Documents`, Android gives
  /// `/data/user/0/<package>/app_flutter`. Both are what
  /// `getApplicationDocumentsDirectory` returns on their platform, and both
  /// appear in rows written before schema version 2 — so the migration has
  /// to know both names even though iOS is the platform we demo.
  static const documentsMarkers = ['/Documents/', '/app_flutter/'];

  /// The relative path a new segment's audio should be stored at.
  ///
  /// Pure, so the shape of the path is testable without a device. The
  /// timestamp is in the name as well as the sequence number: if a segment
  /// is ever re-recorded, the old file is not overwritten. We would rather
  /// leak a file we can delete later than destroy audio we cannot get back.
  static String segmentPath({
    required int sessionId,
    required int seq,
    required int stamp,
  }) =>
      'recordings/session_$sessionId/seg_${seq}_$stamp.m4a';

  /// Turns a stored relative path into a file on this install.
  ///
  /// Every read goes through here. Two lines, and they are the whole fix:
  /// the container UUID is looked up now rather than remembered from
  /// whenever the recording was made.
  /// Not cached. It is a platform channel call a handful of times a session
  /// — once per playback, once per transcription — and a cached container
  /// path is the exact thing that caused the bug this class exists to fix.
  static Future<File> resolve(String relativePath) async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/$relativePath');
  }

  /// Creates the directory a relative path lives in, and returns the
  /// absolute path to hand the platform recorder.
  ///
  /// The recorder needs somewhere real to write, so this is the one place
  /// that produces an absolute path — and it produces it for the encoder,
  /// never for the database.
  static Future<String> prepare(String relativePath) async {
    final file = await resolve(relativePath);
    await file.parent.create(recursive: true);
    return file.path;
  }

  /// Strips an absolute path back to the relative one we should have stored.
  ///
  /// Used by the schema version 2 migration and by nothing else. Kept in
  /// Dart as well as SQL so the rule can be tested directly and so the SQL
  /// has something to be read against.
  ///
  /// Returns the input unchanged when no marker is found, because a path we
  /// do not recognise is not one we should be guessing about.
  static String toRelative(String absolutePath) {
    for (final marker in documentsMarkers) {
      final at = absolutePath.indexOf(marker);
      if (at >= 0) return absolutePath.substring(at + marker.length);
    }
    return absolutePath;
  }
}
