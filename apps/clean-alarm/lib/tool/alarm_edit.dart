import 'package:flutter/material.dart';

import 'alarm_tool.dart';
import 'models.dart';

/// Add or edit a single alarm. `existing == null` means create.
class AlarmEditPage extends StatefulWidget {
  const AlarmEditPage({super.key, this.existing});

  final AlarmItem? existing;

  @override
  State<AlarmEditPage> createState() => _AlarmEditPageState();
}

class _AlarmEditPageState extends State<AlarmEditPage> {
  late TimeOfDay _time;
  late TextEditingController _label;
  late Set<int> _weekdays;
  late bool _soundOn;
  late bool _vibrate;
  late int _snooze;

  static const List<int> _snoozeOptions = [0, 5, 10, 15];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _time = e != null
        ? TimeOfDay(hour: e.hour, minute: e.minute)
        : TimeOfDay.now();
    _label = TextEditingController(text: e?.label ?? '');
    _weekdays = {...?e?.weekdays};
    _soundOn = e?.soundOn ?? true;
    _vibrate = e?.vibrate ?? true;
    _snooze = e?.snoozeMinutes ?? 5;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final store = AlarmScope.of(context);
    final e = widget.existing;
    if (e == null) {
      store.add(
        hour: _time.hour,
        minute: _time.minute,
        label: _label.text,
        weekdays: _weekdays,
        soundOn: _soundOn,
        vibrate: _vibrate,
        snoozeMinutes: _snooze,
      );
    } else {
      e.hour = _time.hour;
      e.minute = _time.minute;
      e.label = _label.text;
      e.weekdays = _weekdays;
      e.soundOn = _soundOn;
      e.vibrate = _vibrate;
      e.snoozeMinutes = _snooze;
      e.enabled = true; // editing re-arms the alarm
      store.update(e);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑闹钟' : '新建闹钟'),
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: () {
                AlarmScope.of(context).delete(widget.existing!);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                child: Text(
                  '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 72, fontWeight: FontWeight.w200),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: '标签（可选）',
              hintText: '例如：起床、吃药、开会',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('重复', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _WeekdayPicker(
            selected: _weekdays,
            onChanged: (s) => setState(() => _weekdays = s),
          ),
          const SizedBox(height: 8),
          Text(
            repeatLabel(_weekdays),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('响铃声'),
            value: _soundOn,
            onChanged: (v) => setState(() => _soundOn = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.vibration),
            title: const Text('震动'),
            value: _vibrate,
            onChanged: (v) => setState(() => _vibrate = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.snooze),
            title: const Text('贪睡'),
            trailing: DropdownButton<int>(
              value: _snooze,
              items: [
                for (final m in _snoozeOptions)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m == 0 ? '关闭' : '$m 分钟'),
                  ),
              ],
              onChanged: (v) => setState(() => _snooze = v ?? 0),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(editing ? '保存' : '添加闹钟'),
          ),
        ],
      ),
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var w = 1; w <= 7; w++)
          FilterChip(
            label: Text(weekdayShort(w)),
            selected: selected.contains(w),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(w);
              } else {
                next.remove(w);
              }
              onChanged(next);
            },
          ),
        ActionChip(
          label: const Text('工作日'),
          onPressed: () => onChanged({...kWorkdays}),
        ),
        ActionChip(
          label: const Text('周末'),
          onPressed: () => onChanged({...kWeekend}),
        ),
        ActionChip(
          label: const Text('每天'),
          onPressed: () => onChanged({...kWeekdaysAll}),
        ),
        ActionChip(
          label: const Text('仅一次'),
          onPressed: () => onChanged(<int>{}),
        ),
      ],
    );
  }
}
