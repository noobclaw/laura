import '../models.dart';

/// What an export is allowed to contain. Synopses are the writer's notes to
/// themselves, so they are opt-in and off by default.
class ExportOptions {
  const ExportOptions({
    this.includeSynopsis = false,
    this.includeSceneTitles = true,
    this.sceneBreak = '* * *',
  });

  final bool includeSynopsis;
  final bool includeSceneTitles;

  /// Printed between two untitled scenes of the same chapter, the way a
  /// manuscript marks a scene change.
  final String sceneBreak;
}

/// The manuscript as Markdown: `#` book, `##` chapter, `###` scene, bodies
/// verbatim (they are already written in the same light Markdown the editor
/// renders inline).
String buildMarkdown(Project p, {ExportOptions options = const ExportOptions()}) {
  final b = StringBuffer()
    ..writeln('# ${p.displayTitle}')
    ..writeln();
  if (p.note.trim().isNotEmpty) {
    b
      ..writeln('> ${p.note.trim().replaceAll('\n', '\n> ')}')
      ..writeln();
  }
  for (var ci = 0; ci < p.chapters.length; ci++) {
    // A chapter with nothing written in it still gets its heading: the
    // structure is part of what the writer is exporting.
    final c = p.chapters[ci];
    b
      ..writeln('## ${c.displayTitle(ci)}')
      ..writeln();
    for (var si = 0; si < c.scenes.length; si++) {
      final s = c.scenes[si];
      final titled = s.title.trim().isNotEmpty;
      if (options.includeSceneTitles && titled) {
        b
          ..writeln('### ${s.displayTitle(si)}')
          ..writeln();
      } else if (si > 0) {
        b
          ..writeln(options.sceneBreak)
          ..writeln();
      }
      if (options.includeSynopsis && s.synopsis.trim().isNotEmpty) {
        b
          ..writeln('_${s.synopsis.trim()}_')
          ..writeln();
      }
      if (s.body.trim().isNotEmpty) {
        b
          ..writeln(s.body.trimRight())
          ..writeln();
      }
    }
  }
  return b.toString();
}

/// The manuscript as plain text: same structure, no Markdown punctuation —
/// for pasting into anything that does not speak Markdown.
String buildPlainText(Project p,
    {ExportOptions options = const ExportOptions()}) {
  final b = StringBuffer()
    ..writeln(p.displayTitle)
    ..writeln();
  for (var ci = 0; ci < p.chapters.length; ci++) {
    final c = p.chapters[ci];
    b
      ..writeln(c.displayTitle(ci))
      ..writeln();
    for (var si = 0; si < c.scenes.length; si++) {
      final s = c.scenes[si];
      final titled = s.title.trim().isNotEmpty;
      if (options.includeSceneTitles && titled) {
        b
          ..writeln(s.displayTitle(si))
          ..writeln();
      } else if (si > 0) {
        b
          ..writeln(options.sceneBreak)
          ..writeln();
      }
      if (options.includeSynopsis && s.synopsis.trim().isNotEmpty) {
        b
          ..writeln(s.synopsis.trim())
          ..writeln();
      }
      if (s.body.trim().isNotEmpty) {
        b
          ..writeln(stripInlineMarks(s.body).trimRight())
          ..writeln();
      }
    }
  }
  return b.toString();
}

/// Drops the light Markdown marks the editor understands (`**`, `*`, leading
/// `#`/`>`), leaving the words. Used by the plain-text export and by the
/// outline preview.
String stripInlineMarks(String text) {
  final lines = text.split('\n');
  return lines.map((line) {
    var l = line;
    final heading = RegExp(r'^\s{0,3}(#{1,6})\s+');
    final quote = RegExp(r'^\s{0,3}>\s?');
    l = l.replaceFirst(heading, '');
    l = l.replaceFirst(quote, '');
    l = l.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!);
    l = l.replaceAllMapped(RegExp(r'(?<!\*)\*(?!\s)([^*]+?)\*'), (m) => m[1]!);
    return l;
  }).join('\n');
}

/// A file name that every desktop OS accepts, derived from the book title.
String exportFileName(Project p, String extension) {
  var base = p.displayTitle.trim();
  // Anything a desktop filesystem would refuse, plus the control range.
  base = base.replaceAll(RegExp('[\\\\/:*?"<>|\\x00-\\x1F]'), ' ');
  base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Runes, not code units: cutting a title mid-emoji leaves half a surrogate
  // pair in the name and some systems reject the file outright.
  final runes = base.runes.toList();
  if (runes.length > 60) base = String.fromCharCodes(runes.take(60));
  // A name of only dots is hidden on Unix and meaningless everywhere.
  base = base.replaceAll(RegExp(r'^[.\s]+'), '').trim();
  if (base.isEmpty) base = 'draft';
  return '$base.$extension';
}
