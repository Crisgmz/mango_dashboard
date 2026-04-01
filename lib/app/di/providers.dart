import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth/admin_access_service.dart';
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
