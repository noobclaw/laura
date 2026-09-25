import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../core/shell_nav.dart';
import 'tool_module.dart';

/// Placeholder tool proving the module contract: a percentage calculator.
/// Generated apps replace this file (and register their module in main.dart).
class SampleTool extends ToolModule {
  @override
  Widget buildHome(BuildContext context) => const _PercentCalculator();
}

class _PercentCalculator extends StatefulWidget {
  const _PercentCalculator();

  @override
  State<_PercentCalculator> createState() => _PercentCalculatorState();
}

class _PercentCalculatorState extends State<_PercentCalculator> {
  final _partCtrl = TextEditingController();
  final _wholeCtrl = TextEditingController();

  String get _result {
    final part = double.tryParse(_partCtrl.text);
    final whole = double.tryParse(_wholeCtrl.text);
    if (part == null || whole == null || whole == 0) return '—';
    return '${(part / whole * 100).toStringAsFixed(2)} %';
  }

  @override
  void dispose() {
    _partCtrl.dispose();
    _wholeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The tool owns its top edge: safe area and the settings entry are
    // placed here, not by the shell. Replace this layout wholesale.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: tr(zh: '设置', en: 'Settings', ja: '設定'),
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => openSettings(context),
              ),
            ),
            TextField(
              controller: _partCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Part',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _wholeCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Whole',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                _result,
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
