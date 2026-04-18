import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';

/// All RevenueCat dashboard projects for the signed-in account (`/me/projects`).
///
/// Re-fetches when [isSignedInProvider] becomes true; returns empty when signed out.
final rcAccountProjectsProvider = FutureProvider<List<RcProject>>((ref) async {
  final signedIn = ref.watch(isSignedInProvider);
  if (!signedIn) return const [];

  final api = ref.watch(rcApiServiceProvider);
  try {
    return await api.projects();
  } catch (_) {
    return const [];
  }
});
