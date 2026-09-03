import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'models.dart';
import 'pro.dart';

/// Result of the editor — the home/detail screen applies it to the store.
class EventDraft {
  EventDraft({
    required this.title,
    required this.date,
    required this.emoji,
    required this.colorValue,
    required this.pinned,
    required this.yearlyRepeat,
    required this.note,
  });

  final String title;
  final DateTime date;
  final String emoji;
  final int colorValue;
  final bool pinned;
  final bool yearlyRepeat;
  final String note;
}

class EventEditPage extends StatefulWidget {
  const EventEditPage({super.key, this.initial, this.pro = false});

  /// When non-null the form is prefilled for editing.
  final CountdownEvent? initial;
  final bool pro;

  @override
  State<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends State<EventEditPage> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late DateTime _date;
  late String _emoji;
  late int _color;
  late bool _pinned;
  late bool _yearly;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _date = e != null ? dateOnly(e.date) : dateOnly(DateTime.now());
    _emoji = e?.emoji ?? kEventEmojis.first;
    _color = e?.colorValue ?? kEventColors.first;
    _pinned = e?.pinned ?? false;
    _yearly = e?.yearlyRepeat ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  void _submit() {
    Navigator.of(context).pop(EventDraft(
      title: _title.text.trim(),
      date: _date,
      emoji: _emoji,
      colorValue: _color,
      pinned: _pinned,
      yearlyRepeat: _yearly,
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? tr(zh: '编辑日子', en: 'Edit day') : tr(zh: '新的日子', en: 'New day')),
        actions: [
          TextButton(
            onPressed: _valid ? _submit : null,
            child: Text(tr(zh: '保存', en: 'Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr(zh: '标题', en: 'Title'),
              hintText: tr(zh: '例如：生日、考试、纪念日', en: 'e.g. birthday, exam, anniversary'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          _Section(
            title: tr(zh: '日期', en: 'Date'),
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                '${_date.year}-${_two(_date.month)}-${_two(_date.day)} ${weekdayLabel(_date)}',
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(zh: '每年重复', en: 'Repeat yearly')),
            subtitle: Text(tr(
              zh: '生日 / 纪念日会自动跳到下一年',
              en: 'Birthdays / anniversaries roll to the next year',
            )),
            value: _yearly,
            onChanged: (v) => setState(() => _yearly = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(zh: '置顶', en: 'Pin')),
            subtitle: Text(tr(
              zh: '置顶的日子排在最前，并显示在小组件',
              en: 'Pinned days sort first and drive the widget',
            )),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          const SizedBox(height: 8),
          _Section(
            title: tr(zh: '图标', en: 'Icon'),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final em in kEventEmojis)
                  _EmojiChip(
                    emoji: em,
                    selected: em == _emoji,
                    onTap: () => setState(() => _emoji = em),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: tr(zh: '颜色', en: 'Color'),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < kEventColors.length; i++)
                  _ColorDot(
                    color: Color(kEventColors[i]),
                    selected: kEventColors[i] == _color,
                    locked: !widget.pro && i >= kFreeColorCount,
                    onTap: () {
                      if (!widget.pro && i >= kFreeColorCount) {
                        _showColorLocked();
                      } else {
                        setState(() => _color = kEventColors[i]);
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: tr(zh: '备注（可选）', en: 'Note (optional)'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  void _showColorLocked() {
    showProSheet(
      context,
      reason: tr(
        zh: '这个颜色是 Pro 主题色,免费版可用前 $kFreeColorCount 种。',
        en: 'This is a Pro theme color; the free tier has the first $kFreeColorCount.',
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: child),
      ],
    );
  }
}

class _EmojiChip extends StatelessWidget {
  const _EmojiChip({required this.emoji, required this.selected, required this.onTap});
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.locked,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
              : null,
        ),
        child: locked
            ? const Icon(Icons.lock, size: 16, color: Colors.white)
            : (selected ? const Icon(Icons.check, size: 20, color: Colors.white) : null),
      ),
    );
  }
}
