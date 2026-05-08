import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/biometric_auth_service.dart';
import '../../data/auth/admin_access_service.dart';
import '../../data/auth/saved_accounts_service.dart';
import '../../data/cash_register/cash_register_data_service.dart';
import '../../data/dashboard/dashboard_data_service.dart';
import '../../data/dashboard/dashboard_summary_cache.dart';
import '../../data/notifications/notification_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final adminAccessServiceProvider = Provider<AdminAccessService>((ref) {
  return AdminAccessService(ref.read(supabaseClientProvider));
});

final dashboardDataServiceProvider = Provider<DashboardDataService>((ref) {
  return DashboardDataService(ref.read(supabaseClientProvider));
});

/// Singleton cache keeping the last [DashboardSummary] per account.
/// Survives account switches so we can show prior data instantly.
final dashboardSummaryCacheProvider = Provider<DashboardSummaryCache>((ref) {
  return DashboardSummaryCache();
});

final cashRegisterDataServiceProvider = Provider<CashRegisterDataService>((ref) {
  return CashRegisterDataService(ref.read(supabaseClientProvider));
});

final savedAccountsServiceProvider = Provider<SavedAccountsService>((ref) {
  return SavedAccountsService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.read(supabaseClientProvider));
});

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return BiometricAuthService();
});

/// Cached availability check — null while loading, true/false once resolved.
final biometricAvailableProvider = FutureProvider<bool>((ref) async {
  return ref.read(biometricAuthServiceProvider).isAvailable();
});

/// Cached biometric label ("Face ID", "Huella", etc.) for UI text.
final biometricLabelProvider = FutureProvider<String>((ref) async {
  return ref.read(biometricAuthServiceProvider).primaryBiometricLabel();
});
