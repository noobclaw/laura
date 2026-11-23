import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// The single non-consumable OhmBench sells.
const String ohmProProductId = 'com.noobclaw.ohmbench.pro_unlock';

/// Events from the store that the user should hear about. The screens turn
/// them into words (see `unlockMessageText`), so this file stays free of
/// presentation.
enum UnlockMessage {
  storeMissing,
  unlocked,
  restored,
  failed,
  waitingForPayment,
  productMissing,
  checkingRestore,
  restoreUnanswered,
  nothingToRestore,
}

/// Talks to StoreKit / Play Billing through the official plugin.
///
/// Billing runs inside the store's own process, so the app itself still
/// needs no network permission. On a device with no store (simulator,
/// side-load, widget tests) every call becomes a quiet no-op plus a
/// [UnlockMessage.storeMissing] when the user actually taps something.
class UnlockService {
  UnlockService._();
  static final UnlockService shared = UnlockService._();

  /// The latest thing to tell the user; cleared by whoever shows it.
  final ValueNotifier<UnlockMessage?> message =
      ValueNotifier<UnlockMessage?>(null);

  /// The store's own error text for the last failed purchase, when it gave
  /// one. Shown instead of the generic "did not go through" line.
  String? storeErrorText;

  /// The price string the store will charge this account, once it is known.
  final ValueNotifier<String?> priceLabel = ValueNotifier<String?>(null);

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _updates;
  VoidCallback? _grantPro;
  bool? _storeUp;
  Future<ProductDetails?>? _product;
  DateTime _productRetryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  Completer<void>? _restoreWatch;

  /// Hook the purchase stream. [grantPro] persists the unlock; it runs for
  /// new purchases and for restores alike.
  Future<void> start({required VoidCallback grantPro}) async {
    _grantPro = grantPro;
    if (_updates != null) return;
    try {
      _updates = _iap.purchaseStream.listen(
        _onUpdates,
        onError: (Object e) => debugPrint('store stream: $e'),
      );
      if (await _storeAvailable()) unawaited(_lookUpProduct());
    } catch (e) {
      debugPrint('store unavailable: $e');
      _storeUp = false;
    }
  }

  Future<bool> _storeAvailable() async {
    if (_storeUp == true) return true;
    try {
      _storeUp = await _iap.isAvailable();
    } catch (_) {
      _storeUp = false;
    }
    return _storeUp!;
  }

  /// Fetches the product once; a failed lookup may be repeated after 15 s.
  /// StoreKit regularly answers empty in the first seconds after launch.
  Future<ProductDetails?> _lookUpProduct() {
    final pending = _product;
    if (pending != null) return pending;
    if (DateTime.now().isBefore(_productRetryAfter)) return Future.value(null);
    final lookup = () async {
      try {
        final reply = await _iap.queryProductDetails({ohmProProductId});
        for (final p in reply.productDetails) {
          if (p.id == ohmProProductId) {
            priceLabel.value = p.price;
            return p;
          }
        }
      } catch (e) {
        debugPrint('product lookup: $e');
      }
      _product = null;
      _productRetryAfter = DateTime.now().add(const Duration(seconds: 15));
      return null;
    }();
    _product = lookup;
    return lookup;
  }

  /// Ask again for the price if it is still unknown. Cheap to call from a
  /// build method: it does nothing once the price is in.
  void wantPrice() {
    if (priceLabel.value != null) return;
    unawaited(() async {
      if (await _storeAvailable()) await _lookUpProduct();
    }());
  }

  Future<void> _onUpdates(List<PurchaseDetails> updates) async {
    for (final u in updates) {
      switch (u.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (u.productID == ohmProProductId) {
            _grantPro?.call();
            final restored = u.status == PurchaseStatus.restored;
            if (restored) _restoreWatch?.complete();
            _restoreWatch = null;
            message.value =
                restored ? UnlockMessage.restored : UnlockMessage.unlocked;
          }
        case PurchaseStatus.error:
          storeErrorText = u.error?.message;
          message.value = UnlockMessage.failed;
        case PurchaseStatus.pending:
          message.value = UnlockMessage.waitingForPayment;
        case PurchaseStatus.canceled:
          break;
      }
      if (u.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(u);
        } catch (e) {
          debugPrint('complete purchase: $e');
        }
      }
    }
  }

  /// Opens the store's purchase sheet.
  Future<void> purchase() async {
    storeErrorText = null;
    if (!await _storeAvailable()) {
      message.value = UnlockMessage.storeMissing;
      return;
    }
    final product = await _lookUpProduct();
    if (product == null) {
      message.value = UnlockMessage.productMissing;
      return;
    }
    try {
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      debugPrint('purchase: $e');
      message.value = UnlockMessage.failed;
    }
  }

  /// Asks the store to replay earlier purchases. Stores say nothing when
  /// there is nothing to replay, so after a grace period the user is told.
  Future<void> restorePurchases() async {
    if (!await _storeAvailable()) {
      message.value = UnlockMessage.storeMissing;
      return;
    }
    final watch = Completer<void>();
    _restoreWatch = watch;
    message.value = UnlockMessage.checkingRestore;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('restore: $e');
      _restoreWatch = null;
      message.value = UnlockMessage.restoreUnanswered;
      return;
    }
    var arrived = true;
    await watch.future.timeout(const Duration(seconds: 12), onTimeout: () {
      arrived = false;
    });
    if (!arrived && identical(_restoreWatch, watch)) {
      _restoreWatch = null;
      message.value = UnlockMessage.nothingToRestore;
    }
  }

  @visibleForTesting
  Future<void> stop() async {
    await _updates?.cancel();
    _updates = null;
  }
}
