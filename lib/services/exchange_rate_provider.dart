import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// USD → [currencyCode] rate from Frankfurter (ECB). Returns null on failure.
final exchangeRateProvider =
    FutureProvider.family<double?, String>((ref, currencyCode) async {
  final code = currencyCode.trim().toUpperCase();
  if (code.isEmpty || code == 'USD') return 1.0;

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  try {
    final response = await dio.get<Map<String, dynamic>>(
      'https://api.frankfurter.app/latest',
      queryParameters: {'from': 'USD', 'to': code},
    );
    final data = response.data;
    if (data == null) return null;
    final rates = data['rates'] as Map<String, dynamic>?;
    final raw = rates?[code] ?? rates?[code.toUpperCase()];
    if (raw is num) return raw.toDouble();
  } catch (_) {}
  return null;
});
