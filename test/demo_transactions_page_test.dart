import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/demo/demo_data.dart';

void main() {
  test('demo transaction pages honor start_date and end_date', () {
    final data = DemoData.instance;
    final newest = DateTime.fromMillisecondsSinceEpoch(
      data.transactions.first['_ms'] as int,
    );
    final day = DateTime(newest.year, newest.month, newest.day);
    final ymd =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';

    final page = data.transactionsPage(
      limit: 500,
      startDate: ymd,
      endDate: ymd,
    );
    final txs = page['transactions'] as List<dynamic>;
    expect(txs, isNotEmpty);
    for (final raw in txs) {
      final map = raw as Map<String, dynamic>;
      final at = DateTime.parse(map['purchase_date'] as String).toLocal();
      expect(DateTime(at.year, at.month, at.day), day);
    }

    final empty = data.transactionsPage(
      limit: 20,
      startDate: '2018-01-01',
      endDate: '2018-01-02',
    );
    expect(empty['transactions'], isEmpty);
  });
}
