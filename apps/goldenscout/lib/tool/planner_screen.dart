import 'package:flutter/material.dart';

import 'light_view.dart';
import 'location_store.dart';
import 'sensors.dart';
import 'pro.dart';

/// Wraps [LightView] with a date stepper so the photographer can scrub the
/// light forward/back. Any date other than today is a Pro feature.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({
    super.key,
    required this.store,
    required this.sensors,
    this.onNeedLocation,
  });

  final LocationStore store;
  final SensorHub sensors;
  final VoidCallback? onNeedLocation;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _date = DateTime(n.year, n.month, n.day);
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _isToday => _date == _today;

  void _shift(int days) {
    if (!widget.store.pro) {
      showProSheet(context, widget.store);
      return;
    }
    setState(() => _date = _date.add(Duration(days: days)));
  }

  Future<void> _pickDate() async {
    if (!widget.store.pro) {
      showProSheet(context, widget.store);
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous day',
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(_fmtDate(_date),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(_isToday ? 'Today · tap to pick a date' : 'Tap to pick a date',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next day',
                ),
              ],
            ),
          ),
        ),
        if (!widget.store.pro)
          _ProHint(onTap: () => showProSheet(context, widget.store)),
        Expanded(
          child: LightView(
            store: widget.store,
            sensors: widget.sensors,
            date: _date,
            isToday: _isToday,
            onNeedLocation: widget.onNeedLocation,
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _ProHint extends StatelessWidget {
  const _ProHint({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: const Color(0xFFF5A623).withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.lock_open, size: 18, color: Color(0xFFF5A623)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Unlock Pro to plan any date',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text('\$3.99',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: const Color(0xFFF5A623))),
          ],
        ),
      ),
    );
  }
}
