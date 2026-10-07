import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/biometric_auth_service.dart';
import '../../data/accounting/dgii_classification_store.dart';
import '../../data/accounting/dgii_report_service.dart';
import '../../data/accounting/ecf_request_service.dart';
import '../../data/auth/admin_access_service.dart';
import '../../data/auth/saved_accounts_service.dart';
import '../../data/billing/billing_data_service.dart';
import '../../data/catalog/catalog_admin_service.dart';
import '../../data/cash_register/cash_register_data_service.dart';
import '../../data/dashboard/business_day_service.dart';
import '../../data/dashboard/dashboard_data_service.dart';
import '../../data/dashboard/dashboard_summary_cache.dart';
import '../../data/dashboard/sales_layout_service.dart';
import '../../data/floor/floor_admin_service.dart';
import '../../data/inventory/inventory_data_service.dart';
import '../../data/inventory/physical_count_service.dart';
import '../../data/inventory/stock_transfer_service.dart';
import '../../data/notifications/notification_preferences_service.dart';
import '../../data/notifications/notification_service.dart';
import '../../data/purchasing/purchasing_data_service.dart';

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

final salesLayoutServiceProvider = Provider<SalesLayoutService>((ref) {
  return SalesLayoutService();
});

/// Servicio que persiste la hora de corte del día operativo por negocio.
/// Determina dónde empieza "Hoy" y "Ayer" en el dashboard (default: 5 AM).
final businessDayServiceProvider = Provider<BusinessDayService>((ref) {
  return BusinessDayService();
});

final inventoryDataServiceProvider = Provider<InventoryDataService>((ref) {
  return InventoryDataService(ref.read(supabaseClientProvider));
});

final cashRegisterDataServiceProvider = Provider<CashRegisterDataService>((ref) {
  return CashRegisterDataService(ref.read(supabaseClientProvider));
});

final billingDataServiceProvider = Provider<BillingDataService>((ref) {
  return BillingDataService(ref.read(supabaseClientProvider));
});

final catalogAdminServiceProvider = Provider<CatalogAdminService>((ref) {
  return CatalogAdminService(ref.read(supabaseClientProvider));
});

final floorAdminServiceProvider = Provider<FloorAdminService>((ref) {
  return FloorAdminService(ref.read(supabaseClientProvider));
});

final purchasingDataServiceProvider = Provider<PurchasingDataService>((ref) {
  return PurchasingDataService(ref.read(supabaseClientProvider));
});

/// Solicitud de facturación electrónica: habla con la Edge Function
/// `ecf-onboarding` del backend compartido con la POS.
final ecfRequestServiceProvider = Provider<EcfRequestService>((ref) {
  return EcfRequestService(ref.read(supabaseClientProvider));
});

/// Formatos de envío de la DGII (606 / 607 / 608).
final dgiiReportServiceProvider = Provider<DgiiReportService>((ref) {
  return DgiiReportService(ref.read(supabaseClientProvider));
});

/// Recuerda la clasificación contable que el usuario elige para el 606 y el
/// 608 (el backend no tiene columna para ella).
final dgiiClassificationStoreProvider = Provider<DgiiClassificationStore>((ref) {
  return DgiiClassificationStore();
});

final physicalCountServiceProvider = Provider<PhysicalCountService>((ref) {
  return PhysicalCountService(ref.read(supabaseClientProvider));
});

final stockTransferServiceProvider = Provider<StockTransferService>((ref) {
  return StockTransferService(ref.read(supabaseClientProvider));
});

final savedAccountsServiceProvider = Provider<SavedAccountsService>((ref) {
  return SavedAccountsService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.read(supabaseClientProvider));
});

final notificationPreferencesServiceProvider =
    Provider<NotificationPreferencesService>((ref) {
  return NotificationPreferencesService(ref.read(supabaseClientProvider));
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
