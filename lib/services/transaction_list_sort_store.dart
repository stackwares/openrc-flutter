import 'package:flutter_riverpod/legacy.dart';
import 'package:revenuecat/models/transaction_list_sort_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

final transactionListSortProvider =
    StateNotifierProvider<TransactionListSortNotifier, TransactionListSortMode>(
      (ref) => TransactionListSortNotifier(),
    );

class TransactionListSortNotifier extends StateNotifier<TransactionListSortMode> {
  static const _key = 'transaction_list_sort_v1';

  TransactionListSortNotifier()
    : super(TransactionListSortMode.purchaseNewestFirst) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    state = transactionListSortModeFromStorage(prefs.getString(_key));
  }

  Future<void> setMode(TransactionListSortMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
