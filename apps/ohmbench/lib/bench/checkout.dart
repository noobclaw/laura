import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'words.dart';

/// Every factory app sells exactly one non-consumable: the Pro unlock.
/// The product must exist in Play Console (and later App Store Connect)
/// under this id for every app.
// ⚠️ App Store 的商品 ID 全账号唯一(Play 是按 app 隔离)。每个新 app 必须用
// '<applicationId>.pro_unlock'(new_app.mjs 会替换);裸 'pro_unlock' 已被 remcard 占用。
const String kOhmProProductId = 'com.noobclaw.ohmbench.pro_unlock';

/// Store boundary so product availability and purchase recovery can be tested.
abstract class CheckoutStore {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});
  Future<void> restorePurchases();
  Future<void> completePurchase(PurchaseDetails purchase);
}

class _PluginStore implements CheckoutStore {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      InAppPurchase.instance.purchaseStream;
  @override
  Future<bool> isAvailable() => InAppPurchase.instance.isAvailable();
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      InAppPurchase.instance.queryProductDetails(ids);
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
  @override
  Future<void> restorePurchases() => InAppPurchase.instance.restorePurchases();
  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      InAppPurchase.instance.completePurchase(purchase);
}

/// Thin wrapper around the official in_app_purchase plugin (Play Billing /
/// StoreKit). Billing runs through the store app's own process, so the app
/// keeps working without the INTERNET permission.
///
/// Every failure degrades gracefully: on devices without a store (emulator,
/// sideload) nothing crashes — [notice] carries a user-facing message and the
/// buy/restore calls simply refuse. The app's ONLY unlock path in release
/// builds is a store purchase; local placeholder unlocks must not survive
/// past SOP gate G8.
class BenchCheckout {
  BenchCheckout._() : _store = _PluginStore();

  @visibleForTesting
  BenchCheckout.testing(
    this._store, {
    this.retryDelay = const Duration(seconds: 2),
  });

  final CheckoutStore _store;
  Duration retryDelay = const Duration(seconds: 2);
  final ValueNotifier<bool> busy = ValueNotifier(false);
  ProductDetails? _product;
  Future<void>? _productLoad;
  static final BenchCheckout instance = BenchCheckout._();

  /// Last user-facing purchase message (error, pending, restored…). UI shows
  /// it via a listener and may clear it after display.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  /// The store's own localized price for [kOhmProProductId] ("¥28.00", "€4,99"),
  /// once known. Null until the store answers; the paywall then falls back to
  /// its written price. Never show a currency the store will not charge.
  final ValueNotifier<String?> price = ValueNotifier<String?>(null);

  VoidCallback? _onUnlocked;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _available = false;
  bool _inited = false;

  /// Set by the purchase stream whenever a restore delivers something, so
  /// [restore] can tell the user when it delivered nothing. Both stores
  /// stay silent in that case, and Apple's reviewers tap "Restore" on a
  /// fresh account expecting a response.
  bool _restoreDelivered = false;

  static bool get _isApple => Platform.isIOS || Platform.isMacOS;

  String get _unavailableMsg => _isApple
      ? tr(
          zh: '应用商店不可用(请确认已登录 App Store)',
          en: 'Store unavailable (make sure you are signed in to the App Store)',
        )
      : tr(
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
      _sub = _store.purchaseStream.listen(
        _handlePurchases,
        onError: (Object e) {
          busy.value = false;
          debugPrint('purchase stream error: $e');
        },
      );
      _available = await _store.isAvailable().timeout(
        const Duration(seconds: 8),
      );
      if (_available) await _loadPrice();
    } catch (e) {
      // No billing backend (emulator, tests, sideload) — stay silent.
      debugPrint('checkout init skipped: $e');
      _available = false;
    }
  }

  bool _priceLoading = false;
  DateTime? _lastPriceAttempt;

  /// Ask the store what it will actually charge, so the paywall can show that
  /// instead of a hardcoded figure. StoreKit is often not ready in the first
  /// seconds after launch and Play answers late on a cold start, so one
  /// failed lookup must not leave the price empty for the whole session:
  /// retry with a short backoff, and let the UI ask again via [ensurePrice].
  Future<void> _loadPrice() {
    return _productLoad ??= _queryProduct().whenComplete(
      () => _productLoad = null,
    );
  }

  Future<void> _queryProduct() async {
    _priceLoading = true;
    _lastPriceAttempt = DateTime.now();
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) await Future<void>.delayed(retryDelay);
        try {
          _available = await _store.isAvailable().timeout(
            const Duration(seconds: 8),
          );
          if (!_available) continue;
          final response = await _store
              .queryProductDetails({kOhmProProductId})
              .timeout(const Duration(seconds: 12));
          debugPrint(
            'OhmBench product query: error=${response.error}, '
            'missing=${response.notFoundIDs}',
          );
          for (final product in response.productDetails) {
            if (product.id == kOhmProProductId) {
              _product = product;
              price.value = product.price;
              return;
            }
          }
        } catch (e) {
          debugPrint('OhmBench product query failed: $e');
        }
      }
    } finally {
      _priceLoading = false;
    }
  }

  Future<void> retryProduct() =>
      _product != null ? Future<void>.value() : _loadPrice();

  /// Called by every widget that displays the price. A no-op once the store
  /// has answered; otherwise re-checks store availability and looks the price
  /// up again (at most once per 20 s), so opening Settings or the Pro sheet
  /// after the network came up shows the real figure instead of the fallback.
  Future<void> ensurePrice() async {
    if (price.value != null || _priceLoading) return;
    final last = _lastPriceAttempt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 20)) {
      return;
    }
    try {
      if (!_available) {
        _available = await _store.isAvailable().timeout(
          const Duration(seconds: 8),
        );
      }
      if (_available) await _loadPrice();
    } catch (e) {
      debugPrint('ensurePrice failed: $e');
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != kOhmProProductId) continue;
      busy.value = p.status == PurchaseStatus.pending;
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        if (p.status == PurchaseStatus.restored) _restoreDelivered = true;
        if (p.productID == kOhmProProductId) {
          _onUnlocked?.call();
          notice.value = p.status == PurchaseStatus.restored
              ? tr(
                  zh: '实验台已恢复 Pro,不限元件',
                  en: 'Bench restored to Pro — no part limit',
                )
              : tr(
                  zh: '实验台已解锁:元件和电路不再限量',
                  en: 'Bench unlocked: no more part or circuit limits',
                );
        }
      } else if (p.status == PurchaseStatus.error) {
        notice.value =
            p.error?.message ??
            tr(
              zh: '这次没有买成,钱没有扣,可以再试一次',
              en: 'That purchase did not go through and nothing was charged. Try again any time.',
            );
      } else if (p.status == PurchaseStatus.pending) {
        notice.value = tr(
          zh: '商店正在确认付款,确认后会自动解锁',
          en: 'The store is confirming the payment; the bench unlocks by itself when it does',
        );
      }
      if (p.pendingCompletePurchase) {
        try {
          await _store.completePurchase(p);
        } catch (e) {
          debugPrint('completePurchase failed: $e');
        }
      }
    }
  }

  /// Launch the store's purchase sheet for the Pro unlock.
  Future<void> buyPro() async {
    if (busy.value) return;
    busy.value = true;
    var launched = false;
    try {
      // Recheck on every user attempt: a cold-start failure is not permanent.
      _available = await _store.isAvailable().timeout(
        const Duration(seconds: 8),
      );
      if (!_available) {
        notice.value = _unavailableMsg;
        return;
      }
      if (_product == null) await _loadPrice();
      final product = _product;
      if (product == null) {
        notice.value = tr(
          zh: '暂时无法加载 Pro,请检查网络后重试。',
          en: 'Unable to load Pro. Check your connection and try again.',
        );
        return;
      }
      launched = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!launched) {
        notice.value = tr(
          zh: '无法打开购买窗口,请重试。',
          en: 'Unable to open the purchase sheet. Please try again.',
        );
      }
    } catch (e) {
      debugPrint('OhmBench buyPro failed: $e');
      notice.value = tr(
        zh: '购买未完成,请稍后重试。',
        en: 'Purchase could not be completed. Please try again.',
      );
    } finally {
      if (!launched) busy.value = false;
    }
  }

  /// Re-deliver past purchases (new device, reinstall). Results arrive on the
  /// purchase stream as [PurchaseStatus.restored]; if nothing has arrived a
  /// few seconds later, say so — silence reads as a broken button.
  Future<void> restore() async {
    try {
      _available = await _store.isAvailable().timeout(
        const Duration(seconds: 8),
      );
    } catch (e) {
      _available = false;
      debugPrint('restore availability failed: $e');
    }
    if (!_available) {
      notice.value = _unavailableMsg;
      return;
    }
    _restoreDelivered = false;
    notice.value = tr(
      zh: '正在向商店核对你的 Pro…',
      en: 'Checking your Pro with the store…',
    );
    try {
      await _store.restorePurchases();
    } catch (e) {
      debugPrint('restore failed: $e');
      notice.value = tr(
        zh: '商店没有回应恢复请求,稍后再试',
        en: 'The store did not answer the restore request. Try again later.',
      );
      return;
    }
    // Stores can take a while to replay; saying "nothing found" too early
    // reads as a lost purchase (audit P2). If the restore lands later, the
    // stream still unlocks and replaces this line.
    await Future<void>.delayed(const Duration(seconds: 12));
    if (!_restoreDelivered) {
      notice.value = tr(
        zh: '这个商店账号下还没有 OhmBench Pro 的购买记录',
        en: 'This store account has no OhmBench Pro purchase yet',
      );
    }
  }

  @visibleForTesting
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _inited = false;
    busy.value = false;
  }
}

/// Surfaces purchase results (errors, pending, unlocked, restored) as
/// snackbars. Mount it ONCE, above every route, via
/// `MaterialApp(builder: (_, child) => CheckoutNotices(child: child))`: the
/// snackbar then appears on whichever screen the user is on — the paywall,
/// a report page, settings — instead of only while settings is open.
///
/// Without it the store's failures are invisible: [BenchCheckout] only writes
/// to [BenchCheckout.notice] and something has to read it.
class CheckoutNotices extends StatefulWidget {
  const CheckoutNotices({super.key, this.child});

  final Widget? child;

  @override
  State<CheckoutNotices> createState() => _CheckoutNoticesState();
}

class _CheckoutNoticesState extends State<CheckoutNotices> {
  void _show() {
    final msg = BenchCheckout.instance.notice.value;
    if (msg == null || !mounted) return;
    BenchCheckout.instance.notice.value = null;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    BenchCheckout.instance.notice.addListener(_show);
    // A notice that arrived before this widget existed (StoreKit replays
    // transactions at launch) is still worth showing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void dispose() {
    BenchCheckout.instance.notice.removeListener(_show);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}

/// The store's real localized price for the Pro unlock once known, otherwise
/// [fallback] (the USD base price written in PLAN.md). Rebuilds when the
/// store answers, and nudges [BenchCheckout.ensurePrice] on every build so
/// a lookup that failed at launch is retried the moment a price is shown.
///
/// The currency is whatever the user's App Store / Play account is billed
/// in — a Chinese UI with a US account correctly shows "$4.99". Never write
/// a "¥" figure into [fallback]: the apps are not sold in mainland China,
/// so a yuan fallback is wrong for everyone and only shows up while the
/// store has not answered yet.
class StorePrice extends StatelessWidget {
  const StorePrice({super.key, required this.fallback, this.style});

  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    BenchCheckout.instance.ensurePrice();
    return ValueListenableBuilder<String?>(
      valueListenable: BenchCheckout.instance.price,
      builder: (context, price, _) => Text(price ?? fallback, style: style),
    );
  }
}
