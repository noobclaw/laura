import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../i18n/txt.dart';
import '../platform/unlock_service.dart';

/// The sentence for a store event.
String unlockMessageText(UnlockMessage m) {
  final apple = Platform.isIOS || Platform.isMacOS;
  return switch (m) {
    UnlockMessage.storeMissing => apple
        ? Txt.storeUnavailableMakeSure
        : Txt.storeUnavailableInstallVia,
    UnlockMessage.unlocked => Txt.benchUnlockedNoMore,
    UnlockMessage.restored =>
      Txt.benchRestoredProNo,
    UnlockMessage.failed => UnlockService.shared.storeErrorText ??
        Txt.purchaseDidNotGo,
    UnlockMessage.waitingForPayment => Txt.storeConfirmingPaymentBench,
    UnlockMessage.productMissing => Txt.storeHasNotAnswered,
    UnlockMessage.checkingRestore =>
      Txt.checkingProStore,
    UnlockMessage.restoreUnanswered => Txt.storeDidNotAnswer,
    UnlockMessage.nothingToRestore => Txt.storeAccountHasNo,
  };
}

/// Shows store events as snackbars on whatever screen is open. Placed once
/// in `MaterialApp.builder`.
class UnlockToasts extends StatefulWidget {
  const UnlockToasts({super.key, required this.child});

  final Widget? child;

  @override
  State<UnlockToasts> createState() => _UnlockToastsState();
}

class _UnlockToastsState extends State<UnlockToasts> {
  final ValueNotifier<UnlockMessage?> _source = UnlockService.shared.message;

  @override
  void initState() {
    super.initState();
    _source.addListener(_announce);
    // StoreKit can replay a purchase before the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void dispose() {
    _source.removeListener(_announce);
    super.dispose();
  }

  void _announce() {
    final m = _source.value;
    if (m == null || !mounted) return;
    _source.value = null;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(unlockMessageText(m))));
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox();
}

/// The store's price for Pro, or [fallback] until the store answers.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.fallback, this.style});

  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    UnlockService.shared.wantPrice();
    return ValueListenableBuilder<String?>(
      valueListenable: UnlockService.shared.priceLabel,
      builder: (_, price, _) => Text(price ?? fallback, style: style),
    );
  }
}
