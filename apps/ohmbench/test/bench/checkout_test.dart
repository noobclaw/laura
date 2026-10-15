import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:ohmbench/bench/checkout.dart';

final product = ProductDetails(
  id: kOhmProProductId,
  title: 'OhmBench Pro',
  description: 'Unlimited circuits',
  price: r'$4.99',
  rawPrice: 4.99,
  currencyCode: 'USD',
);

class FakeStore implements CheckoutStore {
  final events = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  bool available = true;
  bool launch = true;
  int missingQueries = 0;
  int queries = 0;
  int purchases = 0;
  int completed = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    expect(ids, {kOhmProProductId});
    queries++;
    return ProductDetailsResponse(
      productDetails: queries <= missingQueries ? [] : [product],
      notFoundIDs: queries <= missingQueries ? [kOhmProProductId] : [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    expect(purchaseParam.productDetails.id, kOhmProProductId);
    purchases++;
    return launch;
  }

  @override
  Future<void> restorePurchases() async {}
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeStore store;
  late BenchCheckout checkout;
  setUp(() {
    store = FakeStore();
    checkout = BenchCheckout.testing(store, retryDelay: Duration.zero);
  });
  tearDown(() async {
    checkout.dispose();
    await store.events.close();
  });

  test('cold-start unavailable store recovers when user buys', () async {
    store.available = false;
    await checkout.init(onUnlocked: () {});
    store.available = true;
    await checkout.buyPro();
    expect(store.purchases, 1);
    expect(checkout.price.value, r'$4.99');
  });

  test('temporarily missing product retries before buying', () async {
    store.missingQueries = 2;
    await checkout.buyPro();
    expect(store.queries, 3);
    expect(store.purchases, 1);
  });

  test('missing product never launches purchase and can recover', () async {
    store.missingQueries = 3;
    await checkout.buyPro();
    expect(store.purchases, 0);
    expect(checkout.busy.value, false);
    expect(checkout.notice.value, isNotNull);
    await checkout.buyPro();
    expect(store.purchases, 1);
  });

  test('duplicate taps launch only one purchase', () async {
    await Future.wait([checkout.buyPro(), checkout.buyPro()]);
    expect(store.purchases, 1);
    expect(checkout.busy.value, true);
  });

  test('failed store launch releases button for retry', () async {
    store.launch = false;
    await checkout.buyPro();
    expect(checkout.busy.value, false);
    expect(checkout.notice.value, isNotNull);
    store.launch = true;
    await checkout.buyPro();
    expect(store.purchases, 2);
  });

  test('successful transaction unlocks and completes purchase', () async {
    var unlocked = 0;
    await checkout.init(onUnlocked: () => unlocked++);
    await checkout.buyPro();
    final purchase = PurchaseDetails(
      productID: kOhmProProductId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'test',
      ),
      transactionDate: '1',
      status: PurchaseStatus.purchased,
    )..pendingCompletePurchase = true;
    store.events.add([purchase]);
    await Future<void>.delayed(Duration.zero);
    expect(unlocked, 1);
    expect(store.completed, 1);
    expect(checkout.busy.value, false);
  });
}
