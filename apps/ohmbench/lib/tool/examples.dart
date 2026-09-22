import '../core/l10n.dart';
import 'schematic/document.dart';

/// Built-in starter circuits. Each one is chosen to show something moving
/// the moment the user taps Run: a steady flow, a capacitor charging, a
/// rectifier clipping, a tank ringing.
class ExampleCircuit {
  const ExampleCircuit({
    required this.id,
    required this.titleZh,
    required this.titleEn,
    required this.blurbZh,
    required this.blurbEn,
    required this.build,
  });

  final String id;
  final String titleZh;
  final String titleEn;
  final String blurbZh;
  final String blurbEn;
  final SchematicDocument Function() build;

  String get title => tr(zh: titleZh, en: titleEn);
  String get blurb => tr(zh: blurbZh, en: blurbEn);
}

/// Small builder so the layouts below read as a drawing, not as JSON.
class _Sketch {
  SchematicDocument doc = const SchematicDocument();

  void part(PartKind kind, int x, int y,
      {int rot = 0, double? value, double? freq, bool? closed}) {
    final (added, p) = doc.addPart(kind, GridPoint(x, y));
    doc = added;
    if (rot != 0 || value != null || freq != null || closed != null) {
      doc = doc.replacePart(p.copyWith(
        rotation: rot,
        value: value,
        secondaryValue: freq,
        closed: closed,
      ));
    }
  }

  void wire(int x1, int y1, int x2, int y2) {
    doc = doc.addWire(GridPoint(x1, y1), GridPoint(x2, y2)).$1;
  }
}

SchematicDocument _divider() {
  final s = _Sketch()
    ..part(PartKind.dcSource, 0, 1, rot: 1, value: 9)
    ..wire(0, 1, 0, 0)
    ..wire(0, 0, 2, 0)
    ..part(PartKind.resistor, 2, 0, value: 1000)
    ..wire(4, 0, 7, 0)
    ..part(PartKind.resistor, 7, 1, rot: 1, value: 2000)
    ..wire(7, 0, 7, 1)
    ..wire(0, 3, 0, 4)
    ..wire(7, 3, 7, 4)
    ..wire(0, 4, 7, 4)
    ..part(PartKind.ground, 3, 4);
  return s.doc;
}

SchematicDocument _rcCharge() {
  final s = _Sketch()
    ..part(PartKind.dcSource, 0, 1, rot: 1, value: 5)
    ..wire(0, 1, 0, 0)
    ..wire(0, 0, 1, 0)
    ..part(PartKind.toggleSwitch, 1, 0, closed: false)
    ..wire(3, 0, 4, 0)
    ..part(PartKind.resistor, 4, 0, value: 1000)
    ..wire(6, 0, 8, 0)
    ..part(PartKind.capacitor, 8, 1, rot: 1, value: 100e-6)
    ..wire(8, 0, 8, 1)
    ..wire(0, 3, 0, 4)
    ..wire(8, 3, 8, 4)
    ..wire(0, 4, 8, 4)
    ..part(PartKind.ground, 4, 4);
  return s.doc;
}

SchematicDocument _rectifier() {
  final s = _Sketch()
    ..part(PartKind.sineSource, 0, 1, rot: 1, value: 5, freq: 50)
    ..wire(0, 1, 0, 0)
    ..wire(0, 0, 2, 0)
    ..part(PartKind.diode, 2, 0)
    ..wire(4, 0, 9, 0)
    ..part(PartKind.capacitor, 6, 1, rot: 1, value: 47e-6)
    ..wire(6, 0, 6, 1)
    ..part(PartKind.resistor, 9, 1, rot: 1, value: 1000)
    ..wire(9, 0, 9, 1)
    ..wire(0, 3, 0, 4)
    ..wire(6, 3, 6, 4)
    ..wire(9, 3, 9, 4)
    ..wire(0, 4, 9, 4)
    ..part(PartKind.ground, 4, 4);
  return s.doc;
}

SchematicDocument _lcTank() {
  final s = _Sketch()
    ..part(PartKind.dcSource, 0, 1, rot: 1, value: 5)
    ..wire(0, 1, 0, 0)
    ..wire(0, 0, 1, 0)
    ..part(PartKind.toggleSwitch, 1, 0, closed: false)
    ..part(PartKind.resistor, 3, 0, value: 10)
    ..part(PartKind.inductor, 5, 0, value: 10e-3)
    ..wire(7, 0, 9, 0)
    ..part(PartKind.capacitor, 9, 1, rot: 1, value: 10e-6)
    ..wire(9, 0, 9, 1)
    ..wire(0, 3, 0, 4)
    ..wire(9, 3, 9, 4)
    ..wire(0, 4, 9, 4)
    ..part(PartKind.ground, 4, 4);
  return s.doc;
}

final List<ExampleCircuit> kExamples = [
  ExampleCircuit(
    id: 'divider',
    titleZh: '分压器',
    titleEn: 'Voltage divider',
    blurbZh: '9 V 被 1k 与 2k 分成 3 V + 6 V',
    blurbEn: '9 V split by 1k and 2k into 3 V + 6 V',
    build: _divider,
  ),
  ExampleCircuit(
    id: 'rc',
    titleZh: 'RC 充电',
    titleEn: 'RC charging',
    blurbZh: '运行后点开关,看电容以 τ = 0.1 s 充电',
    blurbEn: 'Run, then flip the switch: τ = 0.1 s',
    build: _rcCharge,
  ),
  ExampleCircuit(
    id: 'rectifier',
    titleZh: '半波整流',
    titleEn: 'Half-wave rectifier',
    blurbZh: '50 Hz 正弦,二极管削掉负半周,电容抹平',
    blurbEn: '50 Hz in, negative half clipped, smoothed',
    build: _rectifier,
  ),
  ExampleCircuit(
    id: 'lc',
    titleZh: 'LC 振荡',
    titleEn: 'LC ringing',
    blurbZh: '合上开关,约 500 Hz 的衰减振荡',
    blurbEn: 'Close the switch: a ~500 Hz decaying ring',
    build: _lcTank,
  ),
];
