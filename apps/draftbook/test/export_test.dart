import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:draftbook/tool/export/docx.dart';
import 'package:draftbook/tool/export/manuscript.dart';
import 'package:draftbook/tool/models.dart';
import 'package:flutter_test/flutter_test.dart';

Project sample() => Project(
      id: 'p',
      title: 'Night Bus',
      chapters: [
        Chapter(id: 'c1', title: 'Departure', scenes: [
          Scene(
            id: 's1',
            title: 'The stop',
            synopsis: 'she waits',
            body: '# A heading\n\nShe waited under the **broken** light.',
          ),
          Scene(id: 's2', body: 'A second scene, untitled.'),
        ]),
        Chapter(id: 'c2', scenes: [
          Scene(id: 's3', body: '> Quoted line\n\nAnd *slanted* words.'),
        ]),
      ],
    );

void main() {
  test('markdown keeps the structure and the inline marks', () {
    final md = buildMarkdown(sample());
    expect(md, startsWith('# Night Bus'));
    expect(md, contains('## Departure'));
    expect(md, contains('### The stop'));
    expect(md, contains('**broken**'));
    // The untitled second scene gets a break instead of a heading.
    expect(md, contains('* * *'));
    // A chapter without a title still gets one, numbered.
    expect(md, contains('## '));
  });

  test('synopses stay out unless asked for', () {
    expect(buildMarkdown(sample()), isNot(contains('she waits')));
    expect(
      buildMarkdown(sample(), options: const ExportOptions(includeSynopsis: true)),
      contains('she waits'),
    );
  });

  test('plain text drops every mark', () {
    final txt = buildPlainText(sample());
    expect(txt, contains('She waited under the broken light.'));
    expect(txt, contains('A heading'));
    expect(txt, isNot(contains('**')));
    expect(txt, isNot(contains('# ')));
  });

  test('stripInlineMarks leaves lone asterisks alone', () {
    expect(stripInlineMarks('a * b'), 'a * b');
    expect(stripInlineMarks('* * *'), '* * *');
    expect(stripInlineMarks('**bold** and *thin*'), 'bold and thin');
  });

  test('export file names are safe on every platform', () {
    final p = Project(id: 'p', title: 'A/B: "test"? <x>');
    final name = exportFileName(p, 'md');
    expect(name.endsWith('.md'), isTrue);
    expect(RegExp(r'[\\/:*?"<>|]').hasMatch(name), isFalse);
    expect(exportFileName(Project(id: 'q'), 'txt'), endsWith('.txt'));
  });

  group('docx', () {
    test('is a zip with the parts Word needs', () {
      final bytes = buildDocx(sample());
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).toSet();
      expect(
        names,
        containsAll(<String>[
          '[Content_Types].xml',
          '_rels/.rels',
          'word/_rels/document.xml.rels',
          'word/document.xml',
          'word/styles.xml',
        ]),
      );
    });

    test('carries the manuscript, with formatting as runs not asterisks', () {
      final zip = ZipDecoder().decodeBytes(buildDocx(sample()));
      final doc = utf8.decode(
        zip.files.firstWhere((f) => f.name == 'word/document.xml').content,
      );
      expect(doc, contains('<w:t xml:space="preserve">Night Bus</w:t>'));
      expect(doc, contains('Departure'));
      expect(doc, contains('<w:b/>'));
      expect(doc, contains('<w:t xml:space="preserve">broken</w:t>'));
      expect(doc, isNot(contains('**broken**')));
      // Chapter two starts on a new page.
      expect(doc, contains('<w:pageBreakBefore/>'));
    });

    test('keeps the paragraph-property children in schema order', () {
      // `CT_PPrBase` is a sequence. Word does not ignore a wrong order, it
      // offers to repair the file — and the chapter page break, which every
      // real manuscript hits from chapter two onwards, is where this bites.
      final zip = ZipDecoder().decodeBytes(buildDocx(sample()));
      String part(String name) =>
          utf8.decode(zip.files.firstWhere((f) => f.name == name).content);

      final doc = part('word/document.xml');
      final paragraphProps = RegExp(r'<w:pPr>(.*?)</w:pPr>')
          .allMatches(doc)
          .map((m) => m.group(1)!)
          .toList();
      expect(paragraphProps, isNotEmpty);
      for (final p in paragraphProps) {
        final style = p.indexOf('<w:pStyle');
        final brk = p.indexOf('<w:pageBreakBefore/>');
        if (style >= 0 && brk >= 0) {
          expect(style, lessThan(brk),
              reason: 'pStyle must come before pageBreakBefore');
        }
      }

      // In the styles part: spacing → ind → jc → outlineLvl.
      final styles = part('word/styles.xml');
      for (final m in RegExp(r'<w:pPr>(.*?)</w:pPr>').allMatches(styles)) {
        final p = m.group(1)!;
        final seen = [
          for (final tag in ['<w:spacing', '<w:ind', '<w:jc', '<w:outlineLvl'])
            if (p.contains(tag)) p.indexOf(tag),
        ];
        expect(seen, [...seen]..sort(), reason: 'out of schema order in: $p');
      }
    });

    test('escapes characters that would break the XML', () {
      final p = Project(id: 'p', title: 'Tom & Jerry <draft>', chapters: [
        Chapter(id: 'c', scenes: [Scene(id: 's', body: 'a < b & c > d')]),
      ]);
      final zip = ZipDecoder().decodeBytes(buildDocx(p));
      final doc = utf8.decode(
        zip.files.firstWhere((f) => f.name == 'word/document.xml').content,
      );
      expect(doc, contains('Tom &amp; Jerry &lt;draft&gt;'));
      expect(doc, contains('a &lt; b &amp; c &gt; d'));
    });
  });
}
