import 'package:flutter/material.dart';

import '../i18n/txt.dart';
import '../platform/unlock_service.dart';
import 'store.dart';
import '../screens/brand.dart';
import '../screens/lab_theme.dart';

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
/// starts a purchase directly. `reason` names the
/// gate that was hit.
Future<void> showProSheet(BuildContext context, {String? reason}) {
  UnlockService.shared.wantPrice();
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
              label: Txt.partsPerCircuit,
              free: '${ProjectStore.freeParts}',
              pro: Txt.noLimit,
            ),
            _Spec(
              label: Txt.savedCircuits,
              free: '${ProjectStore.freeProjects}',
              pro: Txt.noLimit,
            ),
            _Spec(
              label: Txt.solverAccuracyScopeUndo,
              free: Txt.full,
              pro: Txt.full,
            ),
            const SizedBox(height: BenchSpace.m),
            Text(
              Txt.onePurchaseNotSubscription,
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
                UnlockService.shared.purchase();
              },
              child: ValueListenableBuilder<String?>(
                valueListenable: UnlockService.shared.priceLabel,
                builder: (context, price, _) => Text(
                  Txt.unlockPro(price ?? '\$4.99'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: BenchSpace.xs),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                UnlockService.shared.restorePurchases();
              },
              child: Text(Txt.restorePurchase,
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
            child: Text(Txt.free,
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
      label: Txt.freePro(label, free, pro),
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
