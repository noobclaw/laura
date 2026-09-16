import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models.dart';
import 'manuscript.dart';

/// Writes a Word document by hand: a .docx is a zip of XML parts, so no
/// service and no native library is involved — the manuscript is assembled on
/// the phone and handed straight to the share sheet.
///
/// The parts we emit are the minimum Word, Pages and Google Docs all accept:
/// `[Content_Types].xml`, the package relationships, `word/document.xml` and a
/// small `word/styles.xml` defining Title / Heading 1–3 / Quote.
Uint8List buildDocx(Project p, {ExportOptions options = const ExportOptions()}) {
  final archive = Archive()
    ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..add(ArchiveFile.string('_rels/.rels', _packageRels))
    ..add(ArchiveFile.string('word/_rels/document.xml.rels', _documentRels))
    ..add(ArchiveFile.string('word/styles.xml', _styles))
    ..add(ArchiveFile.string('word/document.xml', _document(p, options)));
  return ZipEncoder().encodeBytes(archive);
}

String _document(Project p, ExportOptions options) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<w:document xmlns:w="$_wNs"><w:body>')
    ..write(_para(p.displayTitle, style: 'Title'));

  if (p.note.trim().isNotEmpty) {
    for (final line in p.note.trim().split('\n')) {
      b.write(_para(line, style: 'Quote'));
    }
  }

  for (var ci = 0; ci < p.chapters.length; ci++) {
    final c = p.chapters[ci];
    // Every chapter starts on a fresh page, the way a manuscript is submitted.
    b.write(_para(c.displayTitle(ci), style: 'Heading1', pageBreakBefore: ci > 0));
    for (var si = 0; si < c.scenes.length; si++) {
      final s = c.scenes[si];
      final titled = s.title.trim().isNotEmpty;
      if (options.includeSceneTitles && titled) {
        b.write(_para(s.displayTitle(si), style: 'Heading2'));
      } else if (si > 0) {
        b.write(_para(options.sceneBreak, style: 'SceneBreak'));
      }
      if (options.includeSynopsis && s.synopsis.trim().isNotEmpty) {
        // One paragraph per line: a newline inside a single `w:t` renders as a
        // space in Word, so a three-line synopsis would arrive as one blob.
        for (final line in s.synopsis.trim().split('\n')) {
          b.write(_para(line, style: 'Quote'));
        }
      }
      for (final line in s.body.split('\n')) {
        if (line.trim().isEmpty) continue;
        b.write(_bodyPara(line));
      }
    }
  }

  b
    ..write('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1418" w:right="1418" w:bottom="1418" w:left="1418" '
        'w:header="709" w:footer="709" w:gutter="0"/></w:sectPr>')
    ..write('</w:body></w:document>');
  return b.toString();
}

/// One body line, with the editor's light Markdown mapped onto Word styles:
/// `#`/`##`/`###` become headings inside the scene, `>` becomes a quote, and
/// `**bold**` / `*italic*` become character formatting instead of literal
/// asterisks in the exported manuscript.
String _bodyPara(String line) {
  final heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*)$').firstMatch(line);
  if (heading != null) {
    final level = heading.group(1)!.length.clamp(1, 3);
    return _runsPara(heading.group(2)!, style: 'Heading${level + 2 > 6 ? 6 : level + 2}');
  }
  final quote = RegExp(r'^\s{0,3}>\s?(.*)$').firstMatch(line);
  if (quote != null) return _runsPara(quote.group(1)!, style: 'Quote');
  return _runsPara(line);
}

String _para(String text, {String? style, bool pageBreakBefore = false}) =>
    '<w:p>${_pPr(style, pageBreakBefore)}${_run(text)}</w:p>';

String _runsPara(String text, {String? style}) =>
    '<w:p>${_pPr(style, false)}${_inlineRuns(text)}</w:p>';

/// `CT_PPrBase` is an XML **sequence**, not a bag: Word validates the order of
/// these children and shows the "unreadable content" repair dialog when it is
/// wrong. The order that matters here is
/// `pStyle → pageBreakBefore → spacing → ind → jc → outlineLvl`.
String _pPr(String? style, bool pageBreakBefore) {
  if (style == null && !pageBreakBefore) return '';
  final b = StringBuffer('<w:pPr>');
  if (style != null) b.write('<w:pStyle w:val="$style"/>');
  if (pageBreakBefore) b.write('<w:pageBreakBefore/>');
  b.write('</w:pPr>');
  return b.toString();
}

String _run(String text, {bool bold = false, bool italic = false}) {
  final props = (bold || italic)
      ? '<w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}</w:rPr>'
      : '';
  return '<w:r>$props<w:t xml:space="preserve">${_esc(text)}</w:t></w:r>';
}

/// Splits a line into bold / italic / plain runs. Unmatched asterisks are left
/// as typed — a writer using `*` as a scene break should see it, not lose it.
String _inlineRuns(String line) {
  final pattern = RegExp(r'\*\*(.+?)\*\*|(?<!\*)\*(?!\s)([^*]+?)\*(?!\*)');
  final b = StringBuffer();
  var index = 0;
  for (final m in pattern.allMatches(line)) {
    if (m.start > index) b.write(_run(line.substring(index, m.start)));
    if (m.group(1) != null) {
      b.write(_run(m.group(1)!, bold: true));
    } else {
      b.write(_run(m.group(2)!, italic: true));
    }
    index = m.end;
  }
  if (index < line.length) b.write(_run(line.substring(index)));
  if (b.isEmpty) return _run(line);
  return b.toString();
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Control characters are illegal in XML 1.0 and make Word refuse the file.
    .replaceAll(_xmlControl, '');

/// XML 1.0 forbids these code points outright; a single stray one makes Word
/// refuse the whole document. Written as escapes on purpose — the literal
/// characters do not belong in source.
final RegExp _xmlControl = RegExp('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]');

const String _wNs =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

const String _contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

const String _packageRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

const String _documentRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

/// Manuscript defaults: 12pt body, 1.5 line spacing, first-line indent, and
/// headings that are plainly headings in every reader's outline pane.
///
/// Every `w:pPr` below keeps the schema's child order (`spacing → ind → jc →
/// outlineLvl`); see the note on [_pPr]. Getting this wrong does not produce a
/// slightly-off document, it produces one Word offers to repair.
const String _styles = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="$_wNs">
<w:docDefaults><w:rPrDefault><w:rPr>
<w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:eastAsia="SimSun" w:cs="Georgia"/>
<w:sz w:val="24"/><w:szCs w:val="24"/>
</w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:line="360" w:lineRule="auto" w:after="0"/></w:pPr></w:pPrDefault>
</w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>
<w:pPr><w:ind w:firstLine="480"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/>
<w:pPr><w:spacing w:after="360"/><w:jc w:val="center"/></w:pPr>
<w:rPr><w:b/><w:sz w:val="52"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>
<w:pPr><w:spacing w:before="480" w:after="240"/><w:jc w:val="center"/><w:outlineLvl w:val="0"/></w:pPr>
<w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>
<w:pPr><w:spacing w:before="320" w:after="160"/><w:outlineLvl w:val="1"/></w:pPr>
<w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/>
<w:pPr><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="2"/></w:pPr>
<w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/>
<w:pPr><w:spacing w:before="200" w:after="120"/><w:outlineLvl w:val="3"/></w:pPr>
<w:rPr><w:b/><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/>
<w:pPr><w:spacing w:before="200" w:after="120"/><w:outlineLvl w:val="4"/></w:pPr>
<w:rPr><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/>
<w:pPr><w:spacing w:before="200" w:after="120"/><w:outlineLvl w:val="5"/></w:pPr>
<w:rPr><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/>
<w:pPr><w:spacing w:before="120" w:after="120"/><w:ind w:left="480" w:right="480"/></w:pPr>
<w:rPr><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="SceneBreak"><w:name w:val="Scene Break"/>
<w:pPr><w:spacing w:before="240" w:after="240"/><w:ind w:firstLine="0"/><w:jc w:val="center"/></w:pPr>
</w:style>
</w:styles>''';
