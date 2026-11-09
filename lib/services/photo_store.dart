import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// One frame on the app's film roll.
class RollEntry {
  final File file;
  final DateTime time;
  final String filmId; // sanitized film id
  const RollEntry(this.file, this.time, this.filmId);
}

/// Keeps a private copy of every shot taken with the app so the in-app
/// film roll can list them without needing any gallery permission.
/// File name format: <millis>__<filmId>.<ext>
class PhotoStore {
  static String sanitize(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '-');

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/film_roll');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<RollEntry> save(Uint8List bytes, String ext, String filmId, DateTime time) async {
    final d = await _dir();
    final id = sanitize(filmId);
    final f = File('${d.path}/${time.millisecondsSinceEpoch}__$id.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return RollEntry(f, time, id);
  }

  /// Oldest first, like frames on a real roll.
  static Future<List<RollEntry>> load() async {
    final d = await _dir();
    final out = <RollEntry>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final m = RegExp(r'^(\d+)__(.+)\.(jpg|png)$').firstMatch(name);
      if (m == null) continue;
      out.add(RollEntry(
        e,
        DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(1)!)),
        m.group(2)!,
      ));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static Future<void> delete(RollEntry e) async {
    if (await e.file.exists()) await e.file.delete();
  }
}