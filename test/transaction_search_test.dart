import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/search/transaction_search.dart';
import 'package:openrc/models/rc_transaction.dart';

RcTransaction _tx(
  String id, {
  String sub = 'customer-1',
  String product = 'pro.monthly',
  String app = 'app1',
  String appName = 'Demo App',
  String store = 'App Store',
  String country = 'DE',
  String at = '2026-11-01T10:00:00Z',
}) => RcTransaction(
  app: RcTransactionApp(id: app, name: appName),
  storeTransactionIdentifier: id,
  subscriberId: sub,
  productIdentifier: product,
  store: store,
  subscriberCountryCode: country,
  purchaseDate: at,
  revenue: 9.99,
);

void main() {
  final pool = [
    _tx('1000001', sub: 'alice', at: '2026-11-01T10:00:00Z'),
    _tx(
      'GPA.3333-1111',
      sub: 'bob',
      product: 'pro.annual',
      store: 'Play Store',
      country: 'US',
      at: '2026-11-03T10:00:00Z',
    ),
    _tx('1000002', sub: 'alice-2', appName: 'Other App', app: 'app2'),
  ];

  test('an empty query finds nothing', () {
    expect(searchTransactions(pool, '   ').total, 0);
  });

  test('finds a sale by its store transaction id, ignoring case', () {
    final r = searchTransactions(pool, 'gpa.3333');
    expect(r.matches.single.subscriberId, 'bob');
  });

  test('an exact customer id ranks before partial matches', () {
    final r = searchTransactions(pool, 'alice');
    expect(r.total, 2);
    expect(r.matches.first.subscriberId, 'alice');
  });

  test('matches store and country names, and needs every word', () {
    expect(searchTransactions(pool, 'google').total, 1);
    expect(searchTransactions(pool, 'germany').total, 2);
    expect(searchTransactions(pool, 'germany other').total, 1);
    expect(searchTransactions(pool, 'annual germany').total, 0);
  });

  test('newest first among equal ranks', () {
    final r = searchTransactions(pool, 'pro.');
    expect(r.matches.first.subscriberId, 'bob');
  });

  test('caps the list but counts every match', () {
    final many = [for (var i = 0; i < 30; i++) _tx('t$i')];
    final r = searchTransactions(many, 'demo', limit: 10);
    expect(r.matches, hasLength(10));
    expect(r.total, 30);
  });

  test('customer lookup needs one word of three or more characters', () {
    expect(canLookUpCustomer('ab'), isFalse);
    expect(canLookUpCustomer('two words'), isFalse);
    expect(canLookUpCustomer(r'$RCAnonymousID:abc'), isTrue);
  });

  test('finds the newest loaded sale of a customer in a project', () {
    final sales = [
      _tx('a', sub: 'c', at: '2026-10-01T00:00:00Z'),
      _tx('b', sub: 'c', at: '2026-11-01T00:00:00Z'),
      _tx('c', sub: 'c', app: 'other', at: '2026-12-01T00:00:00Z'),
    ];
    expect(
      newestLoadedForCustomer(
        sales,
        projectId: 'app1',
        subscriberId: 'c',
      )?.storeTransactionIdentifier,
      'b',
    );
    expect(
      newestLoadedForCustomer(sales, projectId: 'app1', subscriberId: 'x'),
      isNull,
    );
  });

  test('a customer-only transaction is told apart from a sale', () {
    const lookup = RcTransaction(
      app: RcTransactionApp(id: 'app1'),
      subscriberId: 'c',
    );
    expect(lookup.isCustomerOnly, isTrue);
    expect(_tx('a').isCustomerOnly, isFalse);
  });
}
