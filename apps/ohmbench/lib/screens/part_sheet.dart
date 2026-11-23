import 'package:flutter/material.dart';

import '../i18n/txt.dart';
import '../workshop/format.dart';
import '../circuit/schematic/document.dart';

/// Localised name of a part kind.
String partKindName(PartKind kind) => switch (kind) {
      PartKind.resistor => Txt.resistor,
      PartKind.capacitor => Txt.capacitor,
      PartKind.inductor => Txt.inductor,
      PartKind.diode => Txt.diode,
      PartKind.dcSource => Txt.dcVoltage,
      PartKind.sineSource => Txt.acSineVoltage,
      PartKind.currentSource => Txt.currentSource,
      PartKind.toggleSwitch => Txt.switchPart,
      PartKind.ground => Txt.ground,
    };

/// Short palette caption.
String partKindShort(PartKind kind) => switch (kind) {
      PartKind.resistor => Txt.resistor,
      PartKind.capacitor => Txt.capacitor,
      PartKind.inductor => Txt.inductor,
      PartKind.diode => Txt.diode,
      PartKind.dcSource => Txt.dc,
      PartKind.sineSource => Txt.ac,
      PartKind.currentSource => Txt.current,
      PartKind.toggleSwitch => Txt.switchPart,
      PartKind.ground => Txt.ground,
    };

bool hasEditableValue(PartKind kind) => switch (kind) {
      PartKind.diode || PartKind.ground || PartKind.toggleSwitch => false,
      _ => true,
    };

List<double> _presets(PartKind kind) => switch (kind) {
      PartKind.resistor => const [10, 100, 220, 470, 1e3, 2.2e3, 4.7e3, 10e3, 47e3, 100e3, 1e6],
      PartKind.capacitor => const [1e-9, 10e-9, 100e-9, 1e-6, 10e-6, 47e-6, 100e-6, 1e-3],
      PartKind.inductor => const [1e-6, 10e-6, 100e-6, 1e-3, 10e-3, 100e-3, 1],
      PartKind.dcSource || PartKind.sineSource => const [1.5, 3.3, 5, 9, 12, 24],
      PartKind.currentSource => const [1e-6, 100e-6, 1e-3, 10e-3, 100e-3],
      _ => const [],
    };

const List<double> _frequencyPresets = [1, 10, 50, 60, 100, 1e3, 10e3];

/// Edits a part's value. Returns the updated part, or null when dismissed.
/// Invalid input never leaves the sheet: the field says what is wrong and
/// the Save button stays disabled.
Future<SchematicPart?> showPartValueSheet(
    BuildContext context, SchematicPart part) {
  return showModalBottomSheet<SchematicPart>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _PartValueSheet(part: part),
    ),
  );
}

class _PartValueSheet extends StatefulWidget {
  const _PartValueSheet({required this.part});

  final SchematicPart part;

  @override
  State<_PartValueSheet> createState() => _PartValueSheetState();
}

class _PartValueSheetState extends State<_PartValueSheet> {
  late final TextEditingController _value;
  late final TextEditingController _frequency;

  @override
  void initState() {
    super.initState();
    final p = widget.part;
    _value = TextEditingController(text: _plain(p.value, unitOf(p.kind)));
    _frequency = TextEditingController(text: _plain(p.secondaryValue, 'Hz'));
  }

  /// A value as an editable string: the display form without the space, so
  /// "4.7 kΩ" becomes "4.7k".
  String _plain(double v, String unit) =>
      formatSi(v, unit).replaceAll(' ', '').replaceAll(unit, '').replaceAll('−', '-');

  @override
  void dispose() {
    _value.dispose();
    _frequency.dispose();
    super.dispose();
  }

  double? get _parsedValue => parseSi(_value.text);
  double? get _parsedFrequency => parseSi(_frequency.text);

  String? get _valueError {
    final v = _parsedValue;
    if (v == null) {
      return Txt.notNumberTry4;
    }
    if (!isValidPartValue(widget.part.kind, v)) {
      return Txt.mustGreaterThanZero;
    }
    if (v.abs() > 1e12) return Txt.tooLarge;
    return null;
  }

  String? get _frequencyError {
    if (widget.part.kind != PartKind.sineSource) return null;
    final f = _parsedFrequency;
    if (f == null) return Txt.notNumber;
    if (f <= 0) return Txt.mustGreaterThanZero;
    if (f > 1e7) return Txt.most10Mhz;
    return null;
  }

  void _save() {
    if (_valueError != null || _frequencyError != null) return;
    final p = widget.part;
    Navigator.of(context).pop(p.copyWith(
      value: _parsedValue,
      secondaryValue:
          p.kind == PartKind.sineSource ? _parsedFrequency : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.part;
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final unit = unitOf(p.kind);
    final isSine = p.kind == PartKind.sineSource;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${p.id} · ${partKindName(p.kind)}', style: text.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              textInputAction: isSine ? TextInputAction.next : TextInputAction.done,
              style: text.headlineSmall,
              decoration: InputDecoration(
                labelText: isSine
                    ? Txt.amplitude
                    : Txt.value,
                suffixText: unit,
                errorText: _value.text.isEmpty ? null : _valueError,
                helperText: Txt.prefixesKMM,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => isSine ? null : _save(),
            ),
            const SizedBox(height: 12),
            _Presets(
              values: _presets(p.kind),
              unit: unit,
              onPick: (v) => setState(() => _value.text = _plain(v, unit)),
            ),
            if (isSine) ...[
              const SizedBox(height: 18),
              TextField(
                controller: _frequency,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: text.headlineSmall,
                decoration: InputDecoration(
                  labelText: Txt.frequency,
                  suffixText: 'Hz',
                  errorText: _frequency.text.isEmpty ? null : _frequencyError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              _Presets(
                values: _frequencyPresets,
                unit: 'Hz',
                onPick: (v) =>
                    setState(() => _frequency.text = _plain(v, 'Hz')),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed:
                  _valueError == null && _frequencyError == null ? _save : null,
              child: Text(Txt.done),
            ),
            if (p.valueOverride != null)
              TextButton(
                onPressed: () => Navigator.of(context)
                    .pop(p.copyWith(resetValue: true)),
                child: Text(
                  Txt.resetDefault(formatSi(p.kind.defaultValue, unit)),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Presets extends StatelessWidget {
  const _Presets(
      {required this.values, required this.unit, required this.onPick});

  final List<double> values;
  final String unit;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ActionChip(
            label: Text(formatSi(v, unit),
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()])),
            onPressed: () => onPick(v),
          ),
      ],
    );
  }
}
