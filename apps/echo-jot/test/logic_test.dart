import 'dart:convert';
import 'dart:io';

import 'package:echo_jot/tool/note.dart';
import 'package:echo_jot/tool/transcript_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isCjkText', () {
    test('detects Chinese, Japanese, Korean', () {
      expect(isCjkText('买牛奶'), isTrue);
      expect(isCjkText('メモを取る'), isTrue);
      expect(isCjkText('메모'), isTrue);
    });

    test('plain latin is not CJK', () {
      expect(isCjkText('buy milk'), isFalse);
      expect(isCjkText(''), isFalse);
      expect(isCjkText('123 !?'), isFalse);
    });
  });

  group('appendSegment', () {
    test('first CJK segment is kept as-is', () {
      expect(appendSegment('', '买牛奶'), '买牛奶');
    });

    test('first latin segment gets capitalised', () {
      expect(appendSegment('', 'buy milk'), 'Buy milk');
    });

    test('CJK segments are joined with a full stop, no space', () {
      expect(appendSegment('买牛奶', '还有鸡蛋'), '买牛奶。还有鸡蛋');
    });

    test('latin segments are joined with a period and a space', () {
      expect(appendSegment('Buy milk', 'call the dentist'),
          'Buy milk. Call the dentist');
    });

    test('existing punctuation is respected', () {
      expect(appendSegment('买牛奶?', '还有鸡蛋'), '买牛奶?还有鸡蛋');
      expect(appendSegment('Buy milk!', 'call back'), 'Buy milk! Call back');
      expect(appendSegment('买牛奶,', '还有鸡蛋'), '买牛奶,还有鸡蛋');
    });

    test('blank segments change nothing', () {
      expect(appendSegment('买牛奶', '   '), '买牛奶');
      expect(appendSegment('', ''), '');
    });

    test('a CJK note stays CJK even when a latin word arrives', () {
      expect(appendSegment('买牛奶', 'ok'), '买牛奶。ok');
    });
  });

  group('finalizeTranscript', () {
    test('terminates an unpunctuated tail', () {
      expect(finalizeTranscript('买牛奶'), '买牛奶。');
      expect(finalizeTranscript('buy milk'), 'buy milk.');
    });

    test('leaves an already terminated tail alone', () {
      expect(finalizeTranscript('买牛奶。'), '买牛奶。');
      expect(finalizeTranscript('Buy milk?'), 'Buy milk?');
    });

    test('empty stays empty', () {
      expect(finalizeTranscript('   '), '');
    });
  });

  group('previewTranscript', () {
    test('shows the live partial appended to committed text', () {
      expect(previewTranscript('买牛奶', '还有鸡蛋'), '买牛奶。还有鸡蛋');
    });

    test('no partial means no change', () {
      expect(previewTranscript('买牛奶', ''), '买牛奶');
    });
  });

  group('firstSentenceTitle', () {
    test('takes the first sentence', () {
      expect(firstSentenceTitle('买牛奶。然后去银行。'), '买牛奶');
      expect(firstSentenceTitle('Buy milk. Then bank.'), 'Buy milk');
    });

    test('stops at a line break', () {
      expect(firstSentenceTitle('第一行\n第二行'), '第一行');
    });

    test('truncates long text', () {
      final title =
          firstSentenceTitle('这是一段非常非常长的没有任何标点的开头文字用来测试截断行为是否正确');
      expect(title.length, 25); // 24 chars + ellipsis
      expect(title.endsWith('…'), isTrue);
    });

    test('empty input uses the given label', () {
      expect(firstSentenceTitle('  ', emptyLabel: '(none)'), '(none)');
      expect(firstSentenceTitle('。。', emptyLabel: '(none)'), '(none)');
    });
  });

  group('countUnits', () {
    test('counts CJK characters ignoring whitespace', () {
      expect(countUnits('买 牛奶 和鸡蛋', cjk: true), 6);
    });

    test('counts latin words', () {
      expect(countUnits('buy milk and  eggs', cjk: false), 4);
      expect(countUnits('   ', cjk: false), 0);
    });
  });

  group('Note serialization', () {
    test('round-trips', () {
      final note = Note(
        id: '1',
        createdAt: DateTime.parse('2026-07-30T09:14:00.000'),
        durationMs: 12345,
        text: '买牛奶。',
        language: 'zh-CN',
      );
      final copy = Note.fromJson(jsonDecode(jsonEncode(note.toJson())));
      expect(copy.id, '1');
      expect(copy.createdAt, note.createdAt);
      expect(copy.durationMs, 12345);
      expect(copy.text, '买牛奶。');
      expect(copy.language, 'zh-CN');
    });

    test('tolerates pre-release records with audioPath/status and no language',
        () {
      final copy = Note.fromJson({
        'id': 'old',
        'createdAt': '2026-07-01T10:00:00.000',
        'audioPath': '/data/user/0/app/audio/1.wav',
        'status': 'done',
        'text': 'legacy',
      });
      expect(copy.id, 'old');
      expect(copy.text, 'legacy');
      expect(copy.language, '');
      expect(copy.durationMs, 0);
    });

    test('missing fields never throw', () {
      final copy = Note.fromJson(<String, dynamic>{});
      expect(copy.text, '');
      expect(copy.id, isNotEmpty);
    });
  });

  group('NoteStore', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('echojot_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Note note(String id, String text) => Note(
          id: id,
          createdAt: DateTime.parse('2026-07-30T09:00:00.000'),
          text: text,
        );

    test('search matches text case-insensitively', () async {
      final store = NoteStore.forTest(
        File('${tmp.path}/notes.json'),
        [note('1', 'Buy MILK'), note('2', '去银行')],
      );
      expect(store.search('milk').length, 1);
      expect(store.search('银行').length, 1);
      expect(store.search('').length, 2);
      expect(store.search('nothing'), isEmpty);
    });

    test('add / remove / unlockPro persist to the index file', () async {
      final file = File('${tmp.path}/notes.json');
      final store = NoteStore.forTest(file, []);
      await store.add(note('1', 'first'));
      await store.unlockPro();
      expect(store.pro, isTrue);

      final saved = jsonDecode(await file.readAsString()) as Map;
      expect(saved['pro'], isTrue);
      expect((saved['notes'] as List).length, 1);

      await store.remove(store.notes.first);
      final after = jsonDecode(await file.readAsString()) as Map;
      expect((after['notes'] as List), isEmpty);
      // Pro survives note deletion.
      expect(after['pro'], isTrue);
    });

    test('newest note is first', () async {
      final store = NoteStore.forTest(File('${tmp.path}/notes.json'), []);
      await store.add(note('1', 'older'));
      await store.add(note('2', 'newer'));
      expect(store.notes.first.id, '2');
    });

    test('overlapping writes leave valid JSON (queued + atomic)', () async {
      final file = File('${tmp.path}/notes.json');
      final store = NoteStore.forTest(file, []);
      // Fire a burst without awaiting: two interleaved truncating writes used to
      // be able to corrupt the index and wipe every note plus the Pro flag.
      final futures = <Future<void>>[
        store.add(note('1', 'one')),
        store.add(note('2', 'two')),
        store.unlockPro(),
        store.add(note('3', 'three')),
      ];
      await Future.wait(futures);
      final saved = jsonDecode(await file.readAsString()) as Map;
      expect(saved['pro'], isTrue);
      expect((saved['notes'] as List).length, 3);
      // No temp file left behind.
      expect(await File('${file.path}.tmp').exists(), isFalse);
    });

    test('insertAt restores a deleted note at its old position', () async {
      final store = NoteStore.forTest(File('${tmp.path}/notes.json'), []);
      await store.add(note('1', 'first'));
      await store.add(note('2', 'second'));
      final victim = store.notes[1]; // the older one
      final index = store.indexOf(victim);
      await store.remove(victim);
      expect(store.notes.length, 1);
      await store.insertAt(index, victim);
      expect(store.notes.length, 2);
      expect(store.notes[1].id, victim.id);
    });

    test('volatileFallback keeps the app usable and reports the failure', () {
      final store = NoteStore.volatileFallback('no documents dir');
      expect(store.notes, isEmpty);
      expect(store.pro, isFalse);
      expect(store.loadError, contains('no documents dir'));
    });
  });
}
