import 'package:flutter/material.dart';

import '../bench/words.dart';
import '../bench/checkout.dart';
import 'store.dart';
import 'ui/brand.dart';
import 'ui/lab_theme.dart';

/// OhmBench's one paywall, drawn as a datasheet: the mark, the gate that was
/// hit, then exactly what Pro adds.
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
    showDragHandle: true,
    builder: (ctx) => _ProSheet(reason: reason),
  );
}

class _ProSheet extends StatelessWidget {
  const _ProSheet({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            BenchSpace.xl, 0, BenchSpace.xl, BenchSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const OhmMark(size: 26, animate: true),
                const SizedBox(width: BenchSpace.m),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: 'OhmBench ',
                        style: BenchType.monoStyle(BenchType.display,
                            bold: true)),
                    TextSpan(
                        text: 'Pro',
                        style: BenchType.monoStyle(BenchType.display,
                            bold: true)),
                  ])),
                ),
              ],
            ),
            if (reason != null) ...[
              const SizedBox(height: BenchSpace.m),
              Text(reason!, style: BenchType.bodyStyle(color: Bench.inkDim)),
            ],
            const SizedBox(height: BenchSpace.l),
            _SpecHeader(),
            _Spec(
              label: tr(zh: '每张电路的元件', en: 'Parts per circuit'),
              free: '${ProjectStore.freeParts}',
              pro: tr(zh: '不限', en: 'No limit'),
            ),
            _Spec(
              label: tr(zh: '保存的电路', en: 'Saved circuits'),
              free: '${ProjectStore.freeProjects}',
              pro: tr(zh: '不限', en: 'No limit'),
            ),
            _Spec(
              label: tr(
                  zh: '求解精度、示波器、撤销、自动保存',
                  en: 'Solver accuracy, scope, undo, autosave'),
              free: tr(zh: '完整', en: 'Full'),
              pro: tr(zh: '完整', en: 'Full'),
            ),
            const SizedBox(height: BenchSpace.m),
            Text(
              tr(
                zh: '一次性买断,不是订阅。没有账号、没有广告,电路只存在你的手机里。',
                en: 'One purchase, not a subscription. No account, no ads, and your circuits stay on your phone.',
              ),
              style: BenchType.bodyStyle(color: Bench.inkDim),
            ),
            const SizedBox(height: BenchSpace.l),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: BenchSpace.l),
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
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: BenchSpace.xs),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                BenchCheckout.instance.restore();
              },
              child: Text(tr(zh: '恢复购买', en: 'Restore purchase'),
                  style: const TextStyle(color: Bench.inkDim)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          const Spacer(),
          SizedBox(
            width: 76,
            child: Text(tr(zh: '免费', en: 'Free'),
                textAlign: TextAlign.center,
                style:
                    BenchType.monoStyle(BenchType.label, color: Bench.inkDim)),
          ),
          SizedBox(
            width: 76,
            child: Text('Pro',
                textAlign: TextAlign.center,
                style: BenchType.monoStyle(BenchType.label,
                    bold: true, color: Bench.charge)),
          ),
        ],
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
    return Semantics(
      label: tr(zh: '$label:免费版 $free,Pro $pro', en: '$label: free $free, Pro $pro'),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: BenchSpace.row),
        padding: const EdgeInsets.symmetric(vertical: BenchSpace.s),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Bench.panelBorder)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: BenchType.bodyStyle())),
            SizedBox(
              width: 76,
              child: Text(free,
                  textAlign: TextAlign.center,
                  style: BenchType.monoStyle(BenchType.body,
                      color: Bench.inkDim)),
            ),
            SizedBox(
              width: 76,
              child: Text(pro,
                  textAlign: TextAlign.center,
                  style: BenchType.monoStyle(BenchType.body,
                      bold: true, color: Bench.charge)),
            ),
          ],
        ),
      ),
    );
  }
}
