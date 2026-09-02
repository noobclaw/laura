import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remcard/tool/import_deck.dart';

void main() {
  group('decodeTextBytes', () {
    test('decodes UTF-8; a UTF-8 BOM never reaches the parser', () {
      expect(
        decodeTextBytes(Uint8List.fromList([104, 195, 169, 108, 108, 111])),
        'héllo',
      );
      // Dart's decoder drops a leading BOM itself; stripBom is belt-and-braces.
      expect(
        stripBom(decodeTextBytes(
            Uint8List.fromList([0xEF, 0xBB, 0xBF, 104, 105]))),
        'hi',
      );
    });

    test('detects UTF-16LE and UTF-16BE by BOM (Excel "Unicode Text")', () {
      // "hi" as UTF-16LE with BOM.
      expect(
        decodeTextBytes(Uint8List.fromList([0xFF, 0xFE, 0x68, 0, 0x69, 0])),
        'hi',
      );
      expect(
        decodeTextBytes(Uint8List.fromList([0xFE, 0xFF, 0, 0x68, 0, 0x69])),
        'hi',
      );
      // A CJK code point round-trips too.
      expect(
        decodeTextBytes(Uint8List.fromList([0xFF, 0xFE, 0x2D, 0x4E])),
        '中',
      );
    });

    test('does not throw on malformed UTF-8', () {
      expect(
        () => decodeTextBytes(Uint8List.fromList([0x68, 0xFF, 0x69])),
        returnsNormally,
      );
    });
  });

  group('detectDelimiter', () {
    test('picks tab for Anki-style TSV', () {
      expect(detectDelimiter('front\tback\nhello\tworld\n'), '\t');
    });

    test('picks comma for plain CSV', () {
      expect(detectDelimiter('hello,world\nfoo,bar\n'), ',');
    });

    test('picks semicolon for European CSV', () {
      expect(detectDelimiter('hallo;welt\nfoo;bar\n'), ';');
    });

    test('ignores delimiters inside quotes', () {
      // Tabs win: the commas are all inside quoted fields.
      expect(detectDelimiter('"a,b,c"\t"d,e"\n'), '\t');
    });
  });

  group('parseDelimited', () {
    test('handles quoted commas, escaped quotes and embedded newlines', () {
      final rows = parseDelimited(
        'q,a\r\n"Say ""hi""","one,\ntwo"\r\nplain,row',
        ',',
      );
      expect(rows, [
        ['q', 'a'],
        ['Say "hi"', 'one,\ntwo'],
        ['plain', 'row'],
      ]);
    });

    test('accepts LF, CRLF and lone CR line endings', () {
      for (final nl in ['\n', '\r\n', '\r']) {
        expect(parseDelimited('a,b${nl}c,d', ','), [
          ['a', 'b'],
          ['c', 'd'],
        ]);
      }
    });

    test('does not emit a phantom row for a trailing newline', () {
      expect(parseDelimited('a,b\n', ',').length, 1);
    });
  });

  group('htmlToPlainText', () {
    test('turns <br> and <div> boundaries into single newlines', () {
      expect(
        htmlToPlainText('<b>Hello</b><br>world<div>again</div><div>more</div>'),
        'Hello\nworld\nagain\nmore',
      );
    });

    test('decodes entities, ampersand last', () {
      expect(htmlToPlainText('a &amp;lt; b &nbsp; c'), 'a &lt; b c');
      expect(htmlToPlainText('&quot;x&quot; &#39;y&#39;'), '"x" \'y\'');
    });

    test('collapses runs of spaces and trims each line', () {
      expect(htmlToPlainText('  a   b  <br>  c '), 'a b\nc');
    });
  });

  group('parseDelimitedCards', () {
    test('imports an Anki TSV export, skipping the # header lines', () {
      const anki = '#separator:tab\n'
          '#html:true\n'
          '#tags column:3\n'
          'apple\t<b>苹果</b>\tfruit\n'
          'dog\t狗<br>(名词)\tanimal\n';
      final r = parseDelimitedCards(anki);
      expect(r.cards.length, 2);
      expect(r.cards[0].front, 'apple');
      expect(r.cards[0].back, '苹果');
      expect(r.cards[1].back, '狗\n(名词)');
      expect(r.skippedRows, 0);
      expect(r.formatLabel, 'TSV');
    });

    test('strips a UTF-8 BOM so the first front is clean', () {
      final r = parseDelimitedCards('\uFEFFhello,world\n');
      expect(r.cards.single.front, 'hello');
    });

    test('counts single-column rows as skipped, ignores blank lines', () {
      final r = parseDelimitedCards('a,b\n\nonlyfront\n,onlyback\nc,d\n');
      expect(r.cards.map((c) => c.front), ['a', 'c']);
      expect(r.skippedRows, 2);
    });

    test('takes only the first two columns', () {
      final r = parseDelimitedCards('front,back,tag,deck\n');
      expect(r.cards.single.back, 'back');
    });

    test('reports an empty file distinctly from a file with no usable rows',
        () {
      expect(
        () => parseDelimitedCards('   \n\n'),
        throwsA(isA<ImportException>()
            .having((e) => e.problem, 'problem', ImportProblem.emptyFile)),
      );
      expect(
        () => parseDelimitedCards('onlyone\nstillone\n'),
        throwsA(isA<ImportException>()
            .having((e) => e.problem, 'problem', ImportProblem.noCards)),
      );
    });
  });

  group('cardFromAnkiFields', () {
    test('basic note: field 0 → front, field 1 → back, HTML flattened', () {
      final c = cardFromAnkiFields(splitAnkiFields('<i>cat</i>\u001f猫\u001ftag'));
      expect(c!.front, 'cat');
      expect(c.back, '猫');
    });

    test('cloze note: blanks on the front, answer + Extra on the back', () {
      final c = cardFromAnkiFields([
        'The capital of France is {{c1::Paris}}.',
        'Extra: on the Seine',
      ]);
      expect(c!.front, 'The capital of France is […].');
      expect(c.back, 'The capital of France is Paris.\nExtra: on the Seine');
    });

    test('cloze hint is shown on the front instead of […]', () {
      final c = cardFromAnkiFields(['{{c1::Paris::city}} is lovely']);
      expect(c!.front, '[city] is lovely');
      expect(c.back, 'Paris is lovely');
    });

    test('returns null when a side is empty', () {
      expect(cardFromAnkiFields(['only front']), isNull);
      expect(cardFromAnkiFields(['<br>', 'back']), isNull);
      expect(cardFromAnkiFields([]), isNull);
    });
  });

  group('ankiDeckLeafName', () {
    test('takes the leaf of :: and U+001F nesting', () {
      expect(ankiDeckLeafName('Japanese::N5::Verbs'), 'Verbs');
      expect(ankiDeckLeafName('Japanese\u001fN5'), 'N5');
      expect(ankiDeckLeafName('  Flat  '), 'Flat');
    });
  });

  group('deckNameFromFileName', () {
    test('drops directories and extension, humanises underscores', () {
      expect(deckNameFromFileName('C:\\x\\HSK1_vocab.csv', 'x'), 'HSK1 vocab');
      expect(deckNameFromFileName('/a/b/日语 N5.tsv', 'x'), '日语 N5');
    });

    test('falls back when nothing usable is left', () {
      expect(deckNameFromFileName('.csv', 'Imported'), 'Imported');
      expect(deckNameFromFileName('', 'Imported'), 'Imported');
    });
  });
}
