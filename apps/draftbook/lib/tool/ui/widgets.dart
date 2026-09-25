import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../models.dart';

/// The platform's error, said in the reader's language (kb F6/F16): the
/// common errno values get a plain sentence; anything else keeps the device's
/// own words so there is still something to search for.
String plainStorageReason(String detail) {
  final errno = int.tryParse(RegExp(r'errno\s*=\s*(\d+)').firstMatch(detail)?.group(1) ?? '');
  final lower = detail.toLowerCase();
  if (errno == 28 || errno == 69 || errno == 122 || lower.contains('no space left')) {
    return tr(zh: '手机存储空间不足', en: 'this phone is out of storage');
  }
  if (errno == 13 || errno == 1 || lower.contains('permission denied')) {
    return tr(zh: '没有写入这个文件的权限', en: 'the app was not allowed to write the file');
  }
  if (errno == 30 || lower.contains('read-only file system')) {
    return tr(zh: '存储处于只读状态', en: 'storage is read-only right now');
  }
  if (errno == 5) {
    return tr(zh: '存储读写出错', en: 'the storage reported a read/write error');
  }
  return tr(zh: '设备报告「$detail」', en: 'the device reported "$detail"');
}

/// Disposes a dialog's controllers on the next frame instead of the moment
/// `showDialog` returns: the dialog is still on screen, animating out, when
/// its future completes, and its fields must not be left holding disposed
/// controllers for that frame.
void disposeNextFrame(List<ChangeNotifier> notifiers) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final n in notifiers) {
      n.dispose();
    }
  });
}

/// Press feedback for anything tappable (kb 四 按压手感): scales to
/// [DbMotion.pressScale] the instant the finger lands, springs back on release
/// along the same curve. No ripple anywhere in the app.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = DbMotion.pressScale,
    this.enabled = true,
  });

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: DbMotion.of(context, DbMotion.press),
        curve: DbMotion.enter,
        child: widget.child,
      ),
    );
  }
}

/// A count that rolls to its value instead of snapping — once, when it first
/// appears or changes; never on every keystroke.
class RollingCount extends StatelessWidget {
  const RollingCount({
    super.key,
    required this.value,
    this.style,
    this.rollIn = true,
  });

  final int value;
  final TextStyle? style;
  final bool rollIn;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: rollIn ? 0 : value.toDouble(), end: value.toDouble()),
      duration: DbMotion.of(context, DbMotion.hero),
      curve: DbMotion.enter,
      builder: (context, v, _) => Text(groupedCount(v.round()), style: style),
    );
  }
}

/// A book or goal target as a printer's rule: a hairline track and a heavier
/// inked run. Square ends — this app draws rules, not pills.
class RuleProgress extends StatelessWidget {
  const RuleProgress({super.key, required this.value, this.semanticLabel});

  final double value;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: SizedBox(
        height: 7,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          // Not a hero: the screen's one hero is its figure (kb 四).
          duration: DbMotion.of(context, DbMotion.medium),
          curve: DbMotion.enter,
          builder: (context, t, _) => CustomPaint(
            painter: _RulePainter(t, c.rule, c.ink),
          ),
        ),
      ),
    );
  }
}

class _RulePainter extends CustomPainter {
  _RulePainter(this.t, this.track, this.ink);
  final double t;
  final Color track;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y),
        Paint()..color = track..strokeWidth = DbRadius.hairline);
    if (t > 0) {
      canvas.drawRect(Rect.fromLTWH(0, y - 1.5, size.width * t, 3), Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.t != t || old.ink != ink || old.track != track;
}

/// A full-width hairline.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(start: indent),
        child: SizedBox(
          height: DbRadius.hairline,
          width: double.infinity,
          child: ColoredBox(color: DbColors.of(context).rule),
        ),
      );
}

/// The heading of a bottom sheet: a serif title and, optionally, one line of
/// context under it.
class SheetHeading extends StatelessWidget {
  const SheetHeading({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DbType.heading.copyWith(color: c.ink)),
        if (subtitle != null) ...[
          const SizedBox(height: DbSpace.x0_5),
          Text(subtitle!, style: DbType.byline.copyWith(color: c.inkMuted)),
        ],
      ],
    );
  }
}

/// Delete now, offer Undo (kb F4). The action is already done when this
/// shows; Undo puts it back. Stays ≥5 s, and much longer under a screen
/// reader so it can actually be reached.
void showUndo(
  ScaffoldMessengerState messenger, {
  required String message,
  required VoidCallback onUndo,
  bool accessible = false,
}) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: accessible ? DbMotion.undoWindowAccessible : DbMotion.undoWindow,
      action: SnackBarAction(label: tr(zh: '撤销', en: 'Undo'), onPressed: onUndo),
    ));
}

/// "3 分钟前 / 2 天前" — relative times, in both languages, without pulling in
/// an i18n date package.
String relativeTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return tr(zh: '刚刚', en: 'just now');
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return tr(zh: '$m 分钟前', en: m == 1 ? '1 minute ago' : '$m minutes ago');
  }
  if (d.inHours < 24) {
    final h = d.inHours;
    return tr(zh: '$h 小时前', en: h == 1 ? '1 hour ago' : '$h hours ago');
  }
  if (d.inDays < 30) {
    final days = d.inDays;
    return tr(zh: '$days 天前', en: days == 1 ? 'yesterday' : '$days days ago');
  }
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Words, phrased for the current language ("12,480 字" / "12,480 words").
String wordsLabel(int n) =>
    tr(zh: '${groupedCount(n)} 字', en: n == 1 ? '1 word' : '${groupedCount(n)} words');
