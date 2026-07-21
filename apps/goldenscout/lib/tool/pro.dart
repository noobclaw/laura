import 'package:flutter/material.dart';

import 'location_store.dart';

/// Presents the one-time Pro buyout. Real in-app purchase wiring is deferred;
/// v1 unlocks a local flag so the gated screens can be exercised end-to-end.
void showProSheet(BuildContext context, LocationStore store) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: Color(0xFFF5A623), size: 28),
              const SizedBox(width: 10),
              Text('GoldenScout Pro',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          const _Perk('Plan the light for any date, past or future'),
          const _Perk('Save unlimited shooting spots'),
          const _Perk('Full moon details: rise, set & phase'),
          const SizedBox(height: 8),
          Text('One-time purchase — no subscription, no account.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                store.unlockPro();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('GoldenScout Pro unlocked')),
                );
              },
              child: const Text('Unlock — \$3.99'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Perk extends StatelessWidget {
  const _Perk(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 20, color: Color(0xFFF5A623)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
