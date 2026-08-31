import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'l10n.dart';

/// Every factory app sells exactly one non-consumable: the Pro unlock.
/// The product must exist in Play Console (and later App Store Connect)
/// under this id for every app.
const String kProProductId = 'com.noobclaw.orbit.pro_unlock';

/// Thin wrapper around the official in_app_purchase plugin (Play Billing /
/// StoreKit). Billing runs through the store app's own process, so the app
/// keeps working without the INTERNET permission.
///
/// Every failure degrades gracefully: on devices without a store (emulator,
/// sideload) nothing crashes — [notice] carries a user-facing message and the
/// buy/restore calls simply refuse. The app's ONLY unlock path in release
/// builds is a store purchase; local placeholder unlocks must not survive
/// past SOP gate G8.
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  /// Last user-facing purchase message (error, pending, restored…). UI shows
  /// it via a listener and may clear it after display.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  /// The store's own localized price for [kProProductId] ("¥28.00", "€4,99"),
  /// once known. Null until the store answers; the paywall then falls back to
  /// its written price. Never show a currency the store will not charge.
  final ValueNotifier<String?> price = ValueNotifier<String?>(null);

  VoidCallback? _onUnlocked;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _available = false;
  bool _inited = false;

  String get _unavailableMsg => tr(
        zh: '应用商店不可用(需要从 Google Play 安装并登录)',
        en: 'Store unavailable (install via Google Play and sign in)',
      );

  /// Call once at startup. [onUnlocked] flips the app's persisted Pro flag;
  /// it fires for both fresh purchases and restores.
  Future<void> init({required VoidCallback onUnlocked}) async {
    _onUnlocked = onUnlocked;
    if (_inited) return;
    _inited = true;
    try {
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _handlePurchases,
        onError: (Object e) => debugPrint('purchase stream error: $e'),
      );
      _available = await InAppPurchase.instance.isAvailable();
      if (_available) await _loadPrice();
    } catch (e) {
      // No billing backend (emulator, tests, sideload) — stay silent.
      debugPrint('PurchaseService.init skipped: $e');
      _available = false;
    }
  }

  /// Ask the store what it will actually charge, so the paywall can show that
  /// instead of a hardcoded figure. Failure just leaves [price] null.
  Future<void> _loadPrice() async {
    try {
      final resp =
          await InAppPurchase.instance.queryProductDetails({kProProductId});
      if (resp.productDetails.isNotEmpty) {
        price.value = resp.productDetails.first.price;
      }
    } catch (e) {
      debugPrint('price lookup failed: $e');
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        if (p.productID == kProProductId) {
          _onUnlocked?.call();
          notice.value = tr(zh: 'Pro 已解锁,感谢支持!', en: 'Pro unlocked — thank you!');
        }
      } else if (p.status == PurchaseStatus.error) {
        notice.value = p.error?.message ??
            tr(zh: '购买失败,请稍后重试', en: 'Purchase failed, please try again');
      } else if (p.status == PurchaseStatus.pending) {
        notice.value =
            tr(zh: '等待支付确认…', en: 'Waiting for payment confirmation…');
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (e) {
          debugPrint('completePurchase failed: $e');
        }
      }
    }
  }

  /// Launch the store's purchase sheet for the Pro unlock.
  Future<void> buyPro() async {
    if (!_available) {
      notice.value = _unavailableMsg;
      return;
    }
    try {
      final resp =
          await InAppPurchase.instance.queryProductDetails({kProProductId});
      if (resp.productDetails.isEmpty) {
        notice.value = tr(
          zh: '商品暂不可用,请稍后重试',
          en: 'Product not available yet, please try again later',
        );
        return;
      }
      await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
      );
    } catch (e) {
      debugPrint('buyPro failed: $e');
      notice.value =
          tr(zh: '购买失败,请稍后重试', en: 'Purchase failed, please try again');
    }
  }

  /// Re-deliver past purchases (new device, reinstall). Results arrive on the
  /// purchase stream as [PurchaseStatus.restored].
  Future<void> restore() async {
    if (!_available) {
      notice.value = _unavailableMsg;
      return;
    }
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('restore failed: $e');
      notice.value = tr(zh: '恢复购买失败', en: 'Could not restore purchases');
    }
  }

  @visibleForTesting
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _inited = false;
  }
}

/// Drop this into a settings list to surface purchase results (errors, pending,
/// unlocked) as snackbars while that page is open. Renders nothing itself.
///
/// Without it the store's failures are invisible: [PurchaseService] only writes
/// to [PurchaseService.notice] and something has to read it.
class PurchaseNotices extends StatefulWidget {
  const PurchaseNotices({super.key});

  @override
  State<PurchaseNotices> createState() => _PurchaseNoticesState();
}

class _PurchaseNoticesState extends State<PurchaseNotices> {
  void _show() {
    final msg = PurchaseService.instance.notice.value;
    if (msg == null || !mounted) return;
    PurchaseService.instance.notice.value = null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.notice.addListener(_show);
  }

  @override
  void dispose() {
    PurchaseService.instance.notice.removeListener(_show);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// "Restore purchases" — required by both stores for non-consumables, and the
/// only way a paying user gets Pro back after a reinstall or a new device.
/// Hide it once Pro is on by passing [pro].
class RestorePurchasesTile extends StatelessWidget {
  const RestorePurchasesTile({super.key, this.pro = false});

  final bool pro;

  @override
  Widget build(BuildContext context) {
    if (pro) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.restore),
      title: Text(tr(zh: '恢复购买', en: 'Restore purchases')),
      subtitle: Text(tr(
        zh: '换机或重装后找回已购的 Pro',
        en: 'Recover Pro after a reinstall or new device',
      )),
      onTap: () => PurchaseService.instance.restore(),
    );
  }
}

/// The store's real localized price for the Pro unlock once known, otherwise
/// [fallback] (the price written in PLAN.md). Rebuilds when the store answers.
///
/// Never hardcode a price in the UI: Play charges in the user's currency, and a
/// tile reading "¥18" to someone who will be charged €4.99 is a support ticket.
class ProPriceText extends StatelessWidget {
  const ProPriceText({super.key, required this.fallback, this.style});

  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: PurchaseService.instance.price,
      builder: (context, price, _) => Text(price ?? fallback, style: style),
    );
  }
}
