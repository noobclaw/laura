import 'package:flutter/material.dart';
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _partCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Part', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _wholeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Whole', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(_result, style: Theme.of(context).textTheme.displaySmall),
          ),
        ],
      ),
    );
  }
}
