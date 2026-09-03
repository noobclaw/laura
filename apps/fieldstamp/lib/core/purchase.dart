import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'l10n.dart';

/// Every factory app sells exactly one non-consumable: the Pro unlock.
/// The product must exist in Play Console (and later App Store Connect)
/// under this id for every app.
// ⚠️ App Store 的商品 ID 全账号唯一(Play 是按 app 隔离)。每个新 app 必须用
// '<applicationId>.pro_unlock'(new_app.mjs 会替换);裸 'pro_unlock' 已被 remcard 占用。
const String kProProductId = 'com.noobclaw.fieldstamp.pro_unlock';

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

  bool _priceLoading = false;
  DateTime? _lastPriceAttempt;

  /// Ask the store what it will actually charge, so the paywall can show that
  /// instead of a hardcoded figure. StoreKit is often not ready in the first
  /// seconds after launch and Play answers late on a cold start, so one
  /// failed lookup must not leave the price empty for the whole session:
  /// retry with a short backoff, and let the UI ask again via [ensurePrice].
  Future<void> _loadPrice() async {
    if (_priceLoading) return;
    _priceLoading = true;
    _lastPriceAttempt = DateTime.now();
    try {
      for (final delay in const [0, 2, 5, 10]) {
        if (delay > 0) await Future<void>.delayed(Duration(seconds: delay));
        try {
          final resp =
              await InAppPurchase.instance.queryProductDetails({kProProductId});
          if (resp.productDetails.isNotEmpty) {
            price.value = resp.productDetails.first.price;
            return;
          }
          debugPrint('price lookup: product not found (${resp.notFoundIDs})');
        } catch (e) {
          debugPrint('price lookup failed: $e');
        }
      }
    } finally {
      _priceLoading = false;
    }
  }

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
      if (!_available) _available = await InAppPurchase.instance.isAvailable();
      if (_available) await _loadPrice();
    } catch (e) {
      debugPrint('ensurePrice failed: $e');
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        if (p.status == PurchaseStatus.restored) _restoreDelivered = true;
        if (p.productID == kProProductId) {
          _onUnlocked?.call();
          notice.value = p.status == PurchaseStatus.restored
              ? tr(zh: '已恢复 Pro,欢迎回来!', en: 'Pro restored — welcome back!')
              : tr(zh: 'Pro 已解锁,感谢支持!', en: 'Pro unlocked — thank you!');
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
  /// purchase stream as [PurchaseStatus.restored]; if nothing has arrived a
  /// few seconds later, say so — silence reads as a broken button.
  Future<void> restore() async {
    if (!_available) {
      notice.value = _unavailableMsg;
      return;
    }
    _restoreDelivered = false;
    notice.value = tr(zh: '正在查找已购记录…', en: 'Looking for past purchases…');
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      debugPrint('restore failed: $e');
      notice.value = tr(zh: '恢复购买失败', en: 'Could not restore purchases');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!_restoreDelivered) {
      notice.value = tr(
        zh: '这个商店账号下没有找到可恢复的购买',
        en: 'No previous purchase was found for this store account',
      );
    }
  }

  @visibleForTesting
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _inited = false;
  }
}

/// Surfaces purchase results (errors, pending, unlocked, restored) as
/// snackbars. Mount it ONCE, above every route, via
/// `MaterialApp(builder: (_, child) => PurchaseNotices(child: child))`: the
/// snackbar then appears on whichever screen the user is on — the paywall,
/// a report page, settings — instead of only while settings is open.
///
/// Without it the store's failures are invisible: [PurchaseService] only writes
/// to [PurchaseService.notice] and something has to read it.
class PurchaseNotices extends StatefulWidget {
  const PurchaseNotices({super.key, this.child});

  final Widget? child;

  @override
  State<PurchaseNotices> createState() => _PurchaseNoticesState();
}

class _PurchaseNoticesState extends State<PurchaseNotices> {
  void _show() {
    final msg = PurchaseService.instance.notice.value;
    if (msg == null || !mounted) return;
    PurchaseService.instance.notice.value = null;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.notice.addListener(_show);
    // A notice that arrived before this widget existed (StoreKit replays
    // transactions at launch) is still worth showing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void dispose() {
    PurchaseService.instance.notice.removeListener(_show);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.child ?? const SizedBox.shrink();
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
/// [fallback] (the USD base price written in PLAN.md). Rebuilds when the
/// store answers, and nudges [PurchaseService.ensurePrice] on every build so
/// a lookup that failed at launch is retried the moment a price is shown.
///
/// The currency is whatever the user's App Store / Play account is billed
/// in — a Chinese UI with a US account correctly shows "$4.99". Never write
/// a "¥" figure into [fallback]: the apps are not sold in mainland China,
/// so a yuan fallback is wrong for everyone and only shows up while the
/// store has not answered yet.
class ProPriceText extends StatelessWidget {
  const ProPriceText({super.key, required this.fallback, this.style});

  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    PurchaseService.instance.ensurePrice();
    return ValueListenableBuilder<String?>(
      valueListenable: PurchaseService.instance.price,
      builder: (context, price, _) => Text(price ?? fallback, style: style),
    );
  }
}
