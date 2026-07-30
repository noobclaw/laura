import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'l10n.dart';

/// Every factory app sells exactly one non-consumable: the Pro unlock.
/// The product must exist in Play Console (and later App Store Connect)
/// under this id for every app.
const String kProProductId = 'pro_unlock';

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
    } catch (e) {
      // No billing backend (emulator, tests, sideload) — stay silent.
      debugPrint('PurchaseService.init skipped: $e');
      _available = false;
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
