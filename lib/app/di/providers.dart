import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth/admin_access_service.dart';
import '../../data/auth/saved_accounts_service.dart';
import '../../data/cash_register/cash_register_data_service.dart';
import '../../data/dashboard/dashboard_data_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final adminAccessServiceProvider = Provider<AdminAccessService>((ref) {
  return AdminAccessService(ref.read(supabaseClientProvider));
});

final dashboardDataServiceProvider = Provider<DashboardDataService>((ref) {
  return DashboardDataService(ref.read(supabaseClientProvider));
});

final cashRegisterDataServiceProvider = Provider<CashRegisterDataService>((ref) {
  return CashRegisterDataService(ref.read(supabaseClientProvider));
});

final savedAccountsServiceProvider = Provider<SavedAccountsService>((ref) {
  return SavedAccountsService();
});
