import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Latest USD-based rates from
/// [fawazahmed0/exchange-api](https://github.com/fawazahmed0/exchange-api)
/// (jsDelivr CDN with Cloudflare fallback).
///
/// Keys are **lowercase** codes (`eur`, `php`, …). Values are units of that
/// currency per **1 USD** (same basis as RevenueCat amounts in this app).
final usdExchangeRatesProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 14),
      receiveTimeout: const Duration(seconds: 14),
      validateStatus: (s) => s != null && s < 600,
      headers: const {'Accept': 'application/json'},
    ),
  );

  const urls = <String>[
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json',
    'https://latest.currency-api.pages.dev/v1/currencies/usd.json',
  ];

  for (final url in urls) {
    try {
      final res = await dio.get<Map<String, dynamic>>(url);
      final root = res.data;
      if (root == null) continue;
      final usd = root['usd'];
      if (usd is! Map) continue;
      final out = <String, double>{};
      for (final e in usd.entries) {
        final k = e.key.toString().toLowerCase();
        final v = e.value;
        if (v is num) {
          out[k] = v.toDouble();
        }
      }
      if (out.isNotEmpty) return out;
    } catch (_) {}
  }

  return {};
});
