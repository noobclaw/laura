import 'package:flutter/material.dart';

import '../bench/words.dart';
import '../bench/checkout.dart';
import 'ui/brand.dart';
import 'ui/lab_theme.dart';

/// OhmBench's one paywall, drawn as a bench panel: live charge drifting
/// behind the mark, then exactly what Pro adds.
///
/// It sells only what 1.0 ships: more circuits and bigger circuits. The
/// simulator, the scope, undo and saving are free and stay free — the free
/// tier is a real tool with a size limit, not a demo. M2 features (AC sweep,
/// transistors, iPad layout) are deliberately NOT listed: billing for
/// something the build does not do is an App Store 3.1.1 rejection.
///
/// Rule (2026-09-03): every free-tier gate opens this sheet first; nothing
/// calls `BenchCheckout.instance.buyPro()` directly. `reason` names the
/// gate that was hit.
Future<void> showProSheet(BuildContext context, {String? reason}) {
  BenchCheckout.instance.ensurePrice();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ProSheet(reason: reason),
  );
}

class _ProSheet extends StatelessWidget {
  const _ProSheet({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B141B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Bench.panelBorder)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 132,
                child: Stack(
                  children: [
                    const Positioned.fill(child: ChargeField(count: 9)),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF0B141B).withValues(alpha: 0.95),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Center(child: OhmMark(size: 44)),
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A5363),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      const TextSpan(
                          text: 'OhmBench ',
                          style: TextStyle(
                              color: Bench.ink,
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      TextSpan(
                          text: 'Pro',
                          style: TextStyle(
                              color: Bench.charge,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(
                                    color: Bench.charge.withValues(alpha: 0.6),
                                    blurRadius: 12),
                              ])),
                    ])),
                    if (reason != null) ...[
                      const SizedBox(height: 8),
                      Text(reason!,
                          style: const TextStyle(
                              color: Bench.inkDim, fontSize: 14, height: 1.45)),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Spacer(),
                        SizedBox(
                          width: 64,
                          child: Text(tr(zh: '免费', en: 'Free'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Bench.inkDim,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)),
                        ),
                        const SizedBox(
                          width: 64,
                          child: Text('PRO',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Bench.charge,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2)),
                        ),
                      ],
                    ),
                    _Spec(
                      label: tr(zh: '元件', en: 'Parts'),
                      free: '12',
                      pro: '∞',
                    ),
                    _Spec(
                      label: tr(zh: '保存的电路', en: 'Saved circuits'),
                      free: '1',
                      pro: '∞',
                    ),
                    _Spec(
                      label: tr(zh: '引擎精度 · 示波器 · 撤销', en: 'Engine accuracy · scope · undo'),
                      free: tr(zh: '完整', en: 'Full'),
                      pro: tr(zh: '完整', en: 'Full'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tr(
                        zh: '一次性买断,不是订阅。没有账号、没有广告,电路只存在你的手机里。',
                        en: 'One purchase, not a subscription. No account, no ads, and your circuits stay on your phone.',
                      ),
                      style: const TextStyle(
                          color: Bench.inkDim, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          // The result arrives on the purchase stream.
                          BenchCheckout.instance.buyPro();
                        },
                        child: ValueListenableBuilder<String?>(
                          valueListenable: BenchCheckout.instance.price,
                          builder: (context, price, _) => Text(
                            tr(
                              zh: '解锁 Pro · ${price ?? '\$4.99'}',
                              en: 'Unlock Pro · ${price ?? '\$4.99'}',
                            ),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          BenchCheckout.instance.restore();
                        },
                        child: Text(tr(zh: '恢复购买', en: 'Restore purchase'),
                            style: const TextStyle(color: Bench.inkDim)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the free-vs-Pro spec sheet, like a datasheet table.
class _Spec extends StatelessWidget {
  const _Spec({required this.label, required this.free, required this.pro});

  final String label;
  final String free;
  final String pro;

  @override
  Widget build(BuildContext context) {
    const mono = [FontFeature.tabularFigures()];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Bench.panelBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Bench.ink, fontSize: 14.5)),
          ),
          SizedBox(
            width: 64,
            child: Text(free,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Bench.inkDim,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: mono)),
          ),
          SizedBox(
            width: 64,
            child: Text(pro,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Bench.charge,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: mono)),
          ),
        ],
      ),
    );
  }
}
