import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/constants/app_constants.dart';

/// Whether the hosted/self-hosted relay advertises `/llm/*`. Native never
/// needs it.
final relayLlmCapabilityProvider = FutureProvider<bool>((ref) async {
  if (!kIsWeb) return true;
  try {
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    ).get<Map<String, dynamic>>('${AppConstants.relayUrl}/');
    final llm = response.data?['llm'];
    return llm is List && llm.isNotEmpty;
  } catch (_) {
    return false;
  }
});
