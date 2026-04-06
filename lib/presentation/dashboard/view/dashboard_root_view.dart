import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/auth/role_mapper.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/auth/admin_access_profile.dart';
import '../../../domain/auth/saved_account.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/view/login_view.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/cash_register_view_model.dart';
import '../viewmodel/dashboard_data_view_model.dart';
import '../widgets/dashboard_kpi_cards.dart';
import '../widgets/dashboard_sales_chart.dart';
import '../widgets/dashboard_skeleton.dart';
import '../widgets/dashboard_top_products.dart';
import '../widgets/dashboard_top_seller.dart';
import 'kpi_detail_views.dart';

class DashboardRootView extends ConsumerStatefulWidget {
  const DashboardRootView({super.key});

  @override
  ConsumerState<DashboardRootView> createState() => _DashboardRootViewState();
}

class _DashboardRootViewState extends ConsumerState<DashboardRootView> {
  int _currentIndex = 0;
  String? _loadedBusinessId;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  void _goToTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authGateViewModelProvider.notifier).bootstrap());
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _isRefreshing) return;
      final authState = ref.read(authGateViewModelProvider);
      final profile = authState.profile;
      if (authState.isAuthenticated && profile != null && profile.allowed) {
        unawaited(_refreshActive(profile));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Refresca solo el tab activo (usado por el timer periódico).
  Future<void> _refreshActive(AdminAccessProfile profile) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      switch (_currentIndex) {
        case 0:
        case 2:
        case 3:
          await ref.read(dashboardHomeDataViewModelProvider.notifier).load(
            profile, filter: SalesDateFilter.today);
          break;
        case 1:
          final f = ref.read(salesDataViewModelProvider).summary?.filter ?? SalesDateFilter.month;
          await ref.read(salesDataViewModelProvider.notifier).load(profile, filter: f);
          break;
        case 4:
          await ref.read(cashRegisterViewModelProvider.notifier).load(profile.businessId);
          break;
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Carga todo (pull-to-refresh manual).
  Future<void> _refreshAll(AdminAccessProfile profile) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _startTimer();
    try {
      final currentSalesFilter = ref.read(salesDataViewModelProvider).summary?.filter ?? SalesDateFilter.month;
      await Future.wait([
        ref.read(dashboardHomeDataViewModelProvider.notifier).load(
          profile, filter: SalesDateFilter.today),
        ref.read(salesDataViewModelProvider.notifier).load(
          profile, filter: currentSalesFilter),
        ref.read(cashRegisterViewModelProvider.notifier).load(profile.businessId),
      ]);
    } finally {
      _isRefreshing = false;
    }
  }

  /// Cambio de negocio: limpia datos viejos y recarga todo.
  void _onBusinessChanged(AdminAccessProfile profile) {
    _loadedBusinessId = profile.businessId;
    ref.read(dashboardHomeDataViewModelProvider.notifier).reset();
    ref.read(salesDataViewModelProvider.notifier).reset();
    ref.read(cashRegisterViewModelProvider.notifier).reset();
    _isRefreshing = false;
    _startTimer();
    Future.microtask(() => _refreshAll(profile));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authGateViewModelProvider);
    final homeDataState = ref.watch(dashboardHomeDataViewModelProvider);
    final salesDataState = ref.watch(salesDataViewModelProvider);
    final cashRegisterState = ref.watch(cashRegisterViewModelProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (authState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!authState.isAuthenticated) {
      return const LoginView();
    }

    final profile = authState.profile;
    if (profile == null || !profile.allowed) {
      return AccessDeniedView(profile: profile, themeMode: themeMode);
    }

    if (_loadedBusinessId != profile.businessId) {
      Future.microtask(() => _onBusinessChanged(profile));
    }

    final pages = [
      HomeView(
        profile: profile,
        dataState: homeDataState,
        onOpenSales: () => _goToTab(1),
        onOpenItems: () => _goToTab(2),
        onOpenOrders: () => _goToTab(3),
        onRefresh: () => _refreshAll(profile),
      ),
      SalesView(profile: profile, dataState: salesDataState, onRefresh: () => _refreshAll(profile)),
      ItemsView(dataState: homeDataState, onRefresh: () => _refreshAll(profile)),
      OrdersView(dataState: homeDataState, onRefresh: () => _refreshAll(profile)),
      SettingsView(themeMode: themeMode, profile: profile, cashState: cashRegisterState, onRefresh: () => _refreshAll(profile)),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            IndexedStack(index: _currentIndex, children: pages),
            // Dynamic loading indicator that doesn't break Safe Area
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: (homeDataState.isRefreshing || salesDataState.isRefreshing || cashRegisterState.isLoading)
                    ? LinearProgressIndicator(
                        key: const ValueKey('loading_indicator'),
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(MangoThemeFactory.mango.withValues(alpha: 0.5)),
                      )
                    : const SizedBox(key: ValueKey('no_indicator'), height: 2),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (value) => setState(() => _currentIndex = value),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.space_dashboard_outlined), activeIcon: Icon(Icons.space_dashboard_rounded), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), activeIcon: Icon(Icons.insights_rounded), label: 'Ventas'),
          BottomNavigationBarItem(icon: Icon(Icons.fastfood_outlined), activeIcon: Icon(Icons.fastfood_rounded), label: 'Artículos'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), activeIcon: Icon(Icons.shopping_bag_rounded), label: 'Órdenes'),
          BottomNavigationBarItem(icon: Icon(Icons.tune_outlined), activeIcon: Icon(Icons.tune_rounded), label: 'Ajustes'),
        ],
      ),
    );
  }
}

class AccessDeniedView extends ConsumerWidget {
  const AccessDeniedView({super.key, required this.profile, required this.themeMode});

  final AdminAccessProfile? profile;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final roleLabel = profile == null ? 'sin rol' : normalizeBusinessRole(profile!.rawRole);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(dpi.space(22)),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(dpi.space(22)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(22)),
              border: Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: dpi.scale(60),
                  height: dpi.scale(60),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.mango.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(18)),
                  ),
                  child: Icon(Icons.lock_rounded, color: MangoThemeFactory.mango, size: dpi.icon(30)),
                ),
                SizedBox(height: dpi.space(16)),
                Text('Acceso restringido', style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: dpi.space(8)),
                Text(
                  'Tu rol actual es "$roleLabel". Esta app administrativa solo permite owner o admin.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: dpi.space(16)),
                Wrap(
                  spacing: dpi.space(10),
                  runSpacing: dpi.space(10),
                  children: [
                    if (profile != null &&
                        profile!.memberships.any(
                          (m) => m.allowed && m.businessId != profile!.businessId,
                        ))
                      FilledButton.icon(
                        onPressed: () {
                          final allowed = profile!.memberships.firstWhere(
                            (m) => m.allowed && m.businessId != profile!.businessId,
                          );
                          ref.read(authGateViewModelProvider.notifier).switchBusiness(allowed.businessId);
                        },
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Cambiar negocio'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(themeModeProvider.notifier).setMode(_nextMode(themeMode)),
                      icon: const Icon(Icons.palette_rounded),
                      label: const Text('Cambiar tema'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(authGateViewModelProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Salir'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ThemeMode _nextMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return ThemeMode.light;
      case ThemeMode.light:
        return ThemeMode.dark;
      case ThemeMode.dark:
        return ThemeMode.system;
    }
  }
}

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.profile,
    required this.dataState,
    required this.onOpenSales,
    required this.onOpenItems,
    required this.onOpenOrders,
    required this.onRefresh,
  });

  final AdminAccessProfile profile;
  final DashboardDataState dataState;
  final VoidCallback onOpenSales;
  final VoidCallback onOpenItems;
  final VoidCallback onOpenOrders;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _buildHomeContent(context, dpi),
    );
  }

  Widget _buildHomeContent(BuildContext context, DpiScale dpi) {
    if (dataState.isLoading) {
      return const DashboardSkeleton(key: ValueKey('skeleton_home'));
    }

    if (dataState.error != null) {
      return RefreshIndicator(
        key: const ValueKey('error_home'),
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.all(dpi.space(18)),
          children: [
            _HomeHeader(profile: profile),
            SizedBox(height: dpi.space(18)),
            EmptyStateCard(title: 'Error', message: dataState.error!),
          ],
        ),
      );
    }

    if (dataState.summary == null) {
      return RefreshIndicator(
        key: const ValueKey('empty_home'),
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.all(dpi.space(18)),
          children: [
            _HomeHeader(profile: profile),
            SizedBox(height: dpi.space(18)),
            const EmptyStateCard(title: 'Sin datos', message: 'No se pudo cargar el resumen.'),
          ],
        ),
      );
    }

    final summary = dataState.summary!;
    final gap = SizedBox(height: dpi.space(18));

    return RefreshIndicator(
      key: const ValueKey('content_home'),
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          _HomeHeader(profile: profile),
          gap,
          DashboardKpiCards(
            summary: summary,
            onSalesTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SalesDetailView(summary: summary)),
            ),
            onOrdersTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => OrdersDetailView(summary: summary)),
            ),
            onPendingTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PendingDetailView(summary: summary)),
            ),
            onAverageTicketTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AverageTicketDetailView(summary: summary)),
            ),
          ),
          gap,
          if (summary.salesByMethod.isNotEmpty)
            _SalesByMethodCard(methods: summary.salesByMethod),
          if (summary.salesByMethod.isNotEmpty) gap,
          DashboardSalesChart(
            hourlySales: summary.hourlySales,
            title: 'Ventas por hora',
            subtitle: 'Flujo de ventas del día',
            onTap: onOpenSales,
          ),
          gap,
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 700) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DashboardTopProducts(
                        products: summary.topProducts,
                        onTap: onOpenItems,
                      ),
                    ),
                    SizedBox(width: dpi.space(14)),
                    Expanded(
                      child: summary.topSeller != null
                          ? DashboardTopSeller(
                              seller: summary.topSeller!,
                              onTap: onOpenSales,
                            )
                          : const EmptyStateCard(
                              title: 'Mejor vendedor',
                              message: 'Sin datos de vendedores aún.',
                            ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  DashboardTopProducts(
                    products: summary.topProducts,
                    onTap: onOpenItems,
                  ),
                  gap,
                  if (summary.topSeller != null)
                    DashboardTopSeller(
                      seller: summary.topSeller!,
                      onTap: onOpenSales,
                    )
                  else
                    const EmptyStateCard(
                      title: 'Mejor vendedor',
                      message: 'Sin datos de vendedores aún.',
                    ),
                ],
              );
            },
          ),
          SizedBox(height: dpi.space(22)),
        ],
      ),
    );
  }
}

class _HomeHeader extends ConsumerStatefulWidget {
  const _HomeHeader({required this.profile});

  final AdminAccessProfile profile;

  @override
  ConsumerState<_HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<_HomeHeader> {
  List<SavedAccount> _otherAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadOtherAccounts();
  }

  @override
  void didUpdateWidget(covariant _HomeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.email != widget.profile.email) {
      _loadOtherAccounts();
    }
  }

  Future<void> _loadOtherAccounts() async {
    final all = await ref.read(savedAccountsServiceProvider).loadAccounts();
    if (mounted) {
      setState(() {
        _otherAccounts = all
            .where((a) => a.email != widget.profile.email)
            .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final profile = widget.profile;
    final greeting = _greetingByTime();
    final hasMultipleBranches = profile.memberships.where((m) => m.allowed).length > 1;
    final canSwitch = hasMultipleBranches || _otherAccounts.isNotEmpty;
    final businessName = profile.branchName?.trim().isNotEmpty == true
        ? profile.branchName!
        : (profile.businessName ?? 'Sin nombre');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: canSwitch ? () => _showSelector(context) : null,
                borderRadius: BorderRadius.circular(dpi.radius(12)),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: MangoThemeFactory.mutedText(context),
                            ),
                      ),
                      SizedBox(height: dpi.space(2)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                profile.userName,
                                key: ValueKey(profile.userName),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (canSwitch) ...[
                            SizedBox(width: dpi.space(4)),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: MangoThemeFactory.mango,
                              size: dpi.icon(24),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        businessName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              letterSpacing: 0.5,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: dpi.space(8)),
            Container(
              width: dpi.scale(46),
              height: dpi.scale(46),
              padding: EdgeInsets.all(dpi.space(8)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.cardColor(context),
                borderRadius: BorderRadius.circular(dpi.radius(16)),
                border: Border.all(color: MangoThemeFactory.borderColor(context)),
              ),
              child: Image.asset('assets/logo/logo.png', fit: BoxFit.contain),
            ),
          ],
        ),
      ],
    );
  }

  void _showSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _BusinessAccountSelectorSheet(
        profile: widget.profile,
        otherAccounts: _otherAccounts,
        onBranchSelected: (id) {
          Navigator.pop(ctx);
          ref.read(authGateViewModelProvider.notifier).switchBusiness(id);
        },
        onAccountSwitchByToken: (refreshToken) async {
          final error = await ref
              .read(authGateViewModelProvider.notifier)
              .switchAccountByToken(refreshToken);
          if (error == null && ctx.mounted) Navigator.pop(ctx);
          return error;
        },
        onAccountSwitchWithPassword: (email, password) async {
          final error = await ref
              .read(authGateViewModelProvider.notifier)
              .switchAccountWithPassword(email: email, password: password);
          if (error == null && ctx.mounted) Navigator.pop(ctx);
          return error;
        },
      ),
    );
  }

  String _greetingByTime() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }
}

class _BusinessAccountSelectorSheet extends StatefulWidget {
  const _BusinessAccountSelectorSheet({
    required this.profile,
    required this.otherAccounts,
    required this.onBranchSelected,
    required this.onAccountSwitchByToken,
    required this.onAccountSwitchWithPassword,
  });

  final AdminAccessProfile profile;
  final List<SavedAccount> otherAccounts;
  final Function(String) onBranchSelected;
  final Future<String?> Function(String refreshToken) onAccountSwitchByToken;
  final Future<String?> Function(String email, String password) onAccountSwitchWithPassword;

  @override
  State<_BusinessAccountSelectorSheet> createState() => _BusinessAccountSelectorSheetState();
}

class _BusinessAccountSelectorSheetState extends State<_BusinessAccountSelectorSheet> {
  // Para el mini-formulario de contraseña (solo si el token expiró)
  String? _needsPasswordEmail;
  final _passwordController = TextEditingController();
  String? _switchError;
  bool _switchLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _tryTokenSwitch(SavedAccount account) async {
    if (account.refreshToken == null) {
      // No tiene token guardado, pedir contraseña directamente
      setState(() { _needsPasswordEmail = account.email; _switchError = null; });
      return;
    }
    setState(() { _switchLoading = true; _switchError = null; _needsPasswordEmail = null; });
    final error = await widget.onAccountSwitchByToken(account.refreshToken!);
    if (!mounted) return;
    if (error == null) return; // éxito, el sheet ya se cerró
    // Token expirado, pedir contraseña
    setState(() {
      _switchLoading = false;
      _needsPasswordEmail = account.email;
    });
  }

  Future<void> _tryPasswordSwitch() async {
    if (_needsPasswordEmail == null) return;
    setState(() { _switchLoading = true; _switchError = null; });
    final error = await widget.onAccountSwitchWithPassword(
      _needsPasswordEmail!,
      _passwordController.text,
    );
    if (mounted) {
      setState(() {
        _switchLoading = false;
        _switchError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final allowedBranches = widget.profile.memberships.where((m) => m.allowed).toList();

    return SafeArea(
      top: false,
      child: Container(
      padding: EdgeInsets.all(dpi.space(22)),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(dpi.radius(28))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cambiar negocio', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),

          // --- Sucursales de la cuenta actual ---
          if (allowedBranches.length > 1) ...[
            SizedBox(height: dpi.space(12)),
            Text(
              'SUCURSALES',
              style: TextStyle(
                fontSize: dpi.font(11),
                fontWeight: FontWeight.w800,
                color: MangoThemeFactory.mutedText(context),
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: dpi.space(10)),
            ...allowedBranches.map((membership) {
              final isSelected = membership.businessId == widget.profile.businessId;
              final name = membership.branchName?.trim().isNotEmpty == true
                  ? membership.branchName!
                  : (membership.businessName ?? 'Sin nombre');

              return Padding(
                padding: EdgeInsets.only(bottom: dpi.space(10)),
                child: InkWell(
                  onTap: () => widget.onBranchSelected(membership.businessId),
                  borderRadius: BorderRadius.circular(dpi.radius(16)),
                  child: Container(
                    padding: EdgeInsets.all(dpi.space(16)),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? MangoThemeFactory.mango.withValues(alpha: 0.1)
                          : MangoThemeFactory.cardColor(context),
                      borderRadius: BorderRadius.circular(dpi.radius(16)),
                      border: Border.all(
                        color: isSelected
                            ? MangoThemeFactory.mango
                            : MangoThemeFactory.borderColor(context),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          color: isSelected ? MangoThemeFactory.mango : MangoThemeFactory.mutedText(context),
                        ),
                        SizedBox(width: dpi.space(14)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                      color: isSelected ? MangoThemeFactory.mango : null,
                                    ),
                              ),
                              Text(
                                membership.normalizedRole,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, color: MangoThemeFactory.mango),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],

          // --- Otras cuentas guardadas ---
          if (widget.otherAccounts.isNotEmpty) ...[
            SizedBox(height: dpi.space(12)),
            Text(
              'OTRAS CUENTAS',
              style: TextStyle(
                fontSize: dpi.font(11),
                fontWeight: FontWeight.w800,
                color: MangoThemeFactory.mutedText(context),
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: dpi.space(10)),
            ...widget.otherAccounts.map((account) {
              final needsPassword = _needsPasswordEmail == account.email;

              return Padding(
                padding: EdgeInsets.only(bottom: dpi.space(10)),
                child: InkWell(
                  onTap: _switchLoading ? null : () => _tryTokenSwitch(account),
                  borderRadius: BorderRadius.circular(dpi.radius(16)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.all(dpi.space(16)),
                    decoration: BoxDecoration(
                      color: needsPassword
                          ? MangoThemeFactory.mango.withValues(alpha: 0.05)
                          : MangoThemeFactory.cardColor(context),
                      borderRadius: BorderRadius.circular(dpi.radius(16)),
                      border: Border.all(
                        color: needsPassword
                            ? MangoThemeFactory.mango.withValues(alpha: 0.5)
                            : MangoThemeFactory.borderColor(context),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: dpi.scale(36),
                              height: dpi.scale(36),
                              decoration: BoxDecoration(
                                color: MangoThemeFactory.mango.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                account.displayName.isNotEmpty
                                    ? account.displayName[0].toUpperCase()
                                    : account.email[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: dpi.font(15),
                                  fontWeight: FontWeight.w800,
                                  color: MangoThemeFactory.mango,
                                ),
                              ),
                            ),
                            SizedBox(width: dpi.space(14)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.displayName,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    account.businessName ?? account.email,
                                    style: Theme.of(context).textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (_switchLoading && (needsPassword || _needsPasswordEmail == null))
                              SizedBox(
                                width: dpi.scale(22),
                                height: dpi.scale(22),
                                child: CircularProgressIndicator(strokeWidth: 2, color: MangoThemeFactory.mango),
                              )
                            else
                              Icon(
                                needsPassword ? Icons.expand_less_rounded : Icons.swap_horiz_rounded,
                                color: MangoThemeFactory.mango,
                                size: dpi.icon(22),
                              ),
                          ],
                        ),

                        // Campo de contraseña (solo si el token expiró)
                        if (needsPassword) ...[
                          SizedBox(height: dpi.space(14)),
                          Text(
                            'La sesión expiró. Ingresa tu contraseña.',
                            style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context)),
                          ),
                          SizedBox(height: dpi.space(10)),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              isDense: true,
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(dpi.radius(10))),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(dpi.radius(10)),
                                borderSide: const BorderSide(color: MangoThemeFactory.mango, width: 1.5),
                              ),
                            ),
                            onSubmitted: (_) => _tryPasswordSwitch(),
                          ),
                          if (_switchError != null) ...[
                            SizedBox(height: dpi.space(8)),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(dpi.space(8)),
                              decoration: BoxDecoration(
                                color: MangoThemeFactory.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(dpi.radius(8)),
                              ),
                              child: Text(
                                _switchError!,
                                style: TextStyle(color: MangoThemeFactory.danger, fontSize: dpi.font(12)),
                              ),
                            ),
                          ],
                          SizedBox(height: dpi.space(10)),
                          SizedBox(
                            width: double.infinity,
                            height: dpi.scale(40),
                            child: FilledButton(
                              onPressed: _switchLoading ? null : _tryPasswordSwitch,
                              style: FilledButton.styleFrom(
                                backgroundColor: MangoThemeFactory.mango,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(dpi.radius(10))),
                              ),
                              child: _switchLoading
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withValues(alpha: 0.8)),
                                    )
                                  : Text('Cambiar', style: TextStyle(fontSize: dpi.font(14), fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],

          SizedBox(height: dpi.space(10)),
        ],
      ),
    ));
  }
}

class SalesView extends ConsumerWidget {
  const SalesView({super.key, required this.profile, required this.dataState, required this.onRefresh});

  final AdminAccessProfile profile;
  final DashboardDataState dataState;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _buildSalesContent(context, ref, dpi),
    );
  }

  Widget _buildSalesContent(BuildContext context, WidgetRef ref, DpiScale dpi) {
    final summary = dataState.summary;

    if (dataState.isLoading) {
      return const DashboardSkeleton(key: ValueKey('skeleton_sales'));
    }

    if (summary == null) {
      return RefreshIndicator(
        key: const ValueKey('empty_sales'),
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.all(dpi.space(18)),
          children: [
            Text('Ventas', style: Theme.of(context).textTheme.headlineMedium),
            SizedBox(height: dpi.space(20)),
            EmptyStateCard(title: 'Sin datos', message: dataState.error ?? 'No hay resumen de ventas disponible.'),
          ],
        ),
      );
    }

    final gap = SizedBox(height: dpi.space(18));

    return RefreshIndicator(
      key: const ValueKey('content_sales'),
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reporte de Ventas', style: Theme.of(context).textTheme.headlineMedium),
                  Text('Resumen mensual y diario', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              _FilterBadge(filter: summary.filter),
            ],
          ),
        SizedBox(height: dpi.space(16)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _SalesFilterChip(
                label: 'Hoy',
                selected: summary.filter == SalesDateFilter.today,
                onSelected: () => ref.read(salesDataViewModelProvider.notifier).load(
                      profile,
                      filter: SalesDateFilter.today,
                    ),
              ),
              _SalesFilterChip(
                label: 'Ayer',
                selected: summary.filter == SalesDateFilter.yesterday,
                onSelected: () => ref.read(salesDataViewModelProvider.notifier).load(
                      profile,
                      filter: SalesDateFilter.yesterday,
                    ),
              ),
              _SalesFilterChip(
                label: '7 días',
                selected: summary.filter == SalesDateFilter.week,
                onSelected: () => ref.read(salesDataViewModelProvider.notifier).load(
                      profile,
                      filter: SalesDateFilter.week,
                    ),
              ),
              _SalesFilterChip(
                label: 'Mes',
                selected: summary.filter == SalesDateFilter.month,
                onSelected: () => ref.read(salesDataViewModelProvider.notifier).load(
                      profile,
                      filter: SalesDateFilter.month,
                    ),
              ),
              _SalesFilterChip(
                label: 'Mes Pasado',
                selected: summary.filter == SalesDateFilter.lastMonth,
                onSelected: () => ref.read(salesDataViewModelProvider.notifier).load(
                      profile,
                      filter: SalesDateFilter.lastMonth,
                    ),
              ),
              _SalesFilterChip(
                label: '90 días',
                selected: summary.filter == SalesDateFilter.last3Months,
                onSelected: () => ref.read(salesDataViewModelProvider.notifier).load(
                      profile,
                      filter: SalesDateFilter.last3Months,
                    ),
              ),
            ],
          ),
        ),
        gap,
        // Small KPI row for sales tab
        Row(
          children: [
            Expanded(
              child: _SmallKpi(
                label: 'Ventas Totales',
                value: MangoFormatters.currency(summary.totalSales),
                color: MangoThemeFactory.success,
              ),
            ),
            SizedBox(width: dpi.space(10)),
            Expanded(
              child: _SmallKpi(
                label: 'Tickets',
                value: MangoFormatters.number(summary.totalTickets),
                color: MangoThemeFactory.info,
              ),
            ),
          ],
        ),
        SizedBox(height: dpi.space(10)),
        _SmallKpi(
          label: 'Ticket Promedio',
          value: MangoFormatters.currency(summary.averageTicket),
          color: MangoThemeFactory.mango,
        ),
        gap,
        if (summary.salesByMethod.isNotEmpty)
          _SalesByMethodCard(methods: summary.salesByMethod),
        if (summary.salesByMethod.isNotEmpty) gap,
        DashboardSalesChart(hourlySales: summary.hourlySales, title: 'Ventas por hora', subtitle: 'Flujo de ventas del día'),
        gap,
        Text('Rendimiento por Producto', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: dpi.space(12)),
        if (summary.topProducts.isEmpty)
          const EmptyStateCard(title: 'Sin productos', message: 'No hay ventas registradas aún.')
        else
          ...summary.topProducts.map((p) => _ProductSaleRow(product: p, maxAmount: summary.topProducts.first.amount)),
          SizedBox(height: dpi.space(22)),
        ],
      ),
    );
  }
}

class _FilterBadge extends StatelessWidget {
  const _FilterBadge({required this.filter});
  final SalesDateFilter filter;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    String label;
    switch (filter) {
      case SalesDateFilter.today: label = 'Hoy'; break;
      case SalesDateFilter.yesterday: label = 'Ayer'; break;
      case SalesDateFilter.week: label = '7 días'; break;
      case SalesDateFilter.month: label = 'Mensual'; break;
      case SalesDateFilter.lastMonth: label = 'Mes Pasado'; break;
      case SalesDateFilter.last3Months: label = 'Trimestral'; break;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(12), vertical: dpi.space(6)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.mango.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(dpi.radius(10)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: MangoThemeFactory.mango,
          fontWeight: FontWeight.w700,
          fontSize: dpi.font(10),
        ),
      ),
    );
  }
}

class _SalesFilterChip extends StatelessWidget {
  const _SalesFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(right: dpi.space(8)),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        selectedColor: MangoThemeFactory.mango.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: selected ? MangoThemeFactory.mango : null,
          fontWeight: selected ? FontWeight.w700 : null,
          fontSize: dpi.font(12),
        ),
      ),
    );
  }
}

class _SalesByMethodCard extends StatelessWidget {
  const _SalesByMethodCard({required this.methods});
  final List<SalesByMethod> methods;

  static const _methodIcons = <String, IconData>{
    'cash': Icons.payments_rounded,
    'card': Icons.credit_card_rounded,
    'transfer': Icons.swap_horiz_rounded,
  };

  static const _methodColors = <String, Color>{
    'cash': MangoThemeFactory.success,
    'card': Colors.blueAccent,
    'transfer': Colors.deepPurpleAccent,
  };

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final total = methods.fold<double>(0, (s, m) => s + m.amount);

    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ventas por método de pago', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          SizedBox(height: dpi.space(4)),
          Text('Total del día', style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: dpi.space(14)),
          // Barra de proporción
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(dpi.radius(6)),
              child: SizedBox(
                height: dpi.scale(10),
                child: Row(
                  children: methods.map((m) {
                    final fraction = m.amount / total;
                    return Flexible(
                      flex: (fraction * 1000).round().clamp(1, 1000),
                      child: Container(
                        color: _methodColors[m.code] ?? Colors.grey,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          SizedBox(height: dpi.space(14)),
          ...methods.map((m) {
            final icon = _methodIcons[m.code] ?? Icons.more_horiz_rounded;
            final color = _methodColors[m.code] ?? Colors.grey;
            final percent = total > 0 ? (m.amount / total * 100) : 0.0;
            return Padding(
              padding: EdgeInsets.only(bottom: dpi.space(10)),
              child: Row(
                children: [
                  Container(
                    width: dpi.scale(36),
                    height: dpi.scale(36),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(dpi.radius(10)),
                    ),
                    child: Icon(icon, color: color, size: dpi.icon(18)),
                  ),
                  SizedBox(width: dpi.space(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text('${percent.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(
                    MangoFormatters.currency(m.amount),
                    style: TextStyle(fontSize: dpi.font(14), fontWeight: FontWeight.w800, color: color),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SmallKpi extends StatelessWidget {
  const _SmallKpi({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1),
          SizedBox(height: dpi.space(4)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Text(
                value,
                key: ValueKey(value),
                style: TextStyle(
                  fontSize: dpi.font(18),
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : color.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductSaleRow extends StatelessWidget {
  const _ProductSaleRow({required this.product, required this.maxAmount});
  final TopProduct product;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final percent = maxAmount == 0 ? 0.0 : (product.amount / maxAmount);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  product.label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${product.quantity.toStringAsFixed(0)} uds',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          SizedBox(height: dpi.space(4)),
          Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: dpi.space(8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: MangoThemeFactory.borderColor(context),
                        borderRadius: BorderRadius.circular(dpi.radius(4)),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: percent.clamp(0.0, 1.0),
                      child: Container(
                        height: dpi.space(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(dpi.radius(4)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(12)),
              Text(
                MangoFormatters.currency(product.amount),
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w700,
                  color: MangoThemeFactory.mango,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ItemsView extends StatefulWidget {
  const ItemsView({super.key, required this.dataState, required this.onRefresh});

  final DashboardDataState dataState;
  final Future<void> Function() onRefresh;

  @override
  State<ItemsView> createState() => _ItemsViewState();
}

class _ItemsViewState extends State<ItemsView> {
  String _selectedCategory = 'Todas';

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _buildItemsContent(context, dpi),
    );
  }

  Widget _buildItemsContent(BuildContext context, DpiScale dpi) {
    final items = widget.dataState.summary?.catalogItems ?? const <CatalogItem>[];

    if (widget.dataState.isLoading) {
      return const DashboardSkeleton(key: ValueKey('skeleton_items'));
    }

    if (items.isEmpty) {
      return RefreshIndicator(
        key: const ValueKey('empty_items'),
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.all(dpi.space(18)),
          children: [
            Text('Catálogo de Productos', style: Theme.of(context).textTheme.headlineMedium),
            SizedBox(height: dpi.space(20)),
            EmptyStateCard(title: 'Sin artículos', message: widget.dataState.error ?? 'No se encontraron productos.'),
          ],
        ),
      );
    }

    final Map<String, List<CatalogItem>> grouped = {};
    for (final item in items) {
      final cat = (item.category?.trim().isNotEmpty == true) ? item.category!.trim() : 'General';
      grouped.putIfAbsent(cat, () => []).add(item);
    }

    final categories = ['Todas', ...grouped.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))];
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'Todas';
    }

    final visibleItems = _selectedCategory == 'Todas'
        ? items
        : (grouped[_selectedCategory] ?? const <CatalogItem>[]);

    return RefreshIndicator(
      key: const ValueKey('content_items'),
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          Text('Catálogo de Productos', style: Theme.of(context).textTheme.headlineMedium),
          SizedBox(height: dpi.space(4)),
          Text('Filtra por categoría y revisa todos los productos', style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: dpi.space(16)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: EdgeInsets.only(right: dpi.space(8)),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    selectedColor: MangoThemeFactory.mango.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? MangoThemeFactory.mango : null,
                      fontWeight: isSelected ? FontWeight.w700 : null,
                      fontSize: dpi.font(12),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: dpi.space(14)),
          _CategorySummaryCard(
            selectedCategory: _selectedCategory,
            totalCategories: grouped.length,
            totalProducts: visibleItems.length,
          ),
          SizedBox(height: dpi.space(16)),
          ...visibleItems.map((item) => _ProductCard(item: item)),
          SizedBox(height: dpi.space(30)),
        ],
      ),
    );
  }
}

class _CategorySummaryCard extends StatelessWidget {
  const _CategorySummaryCard({
    required this.selectedCategory,
    required this.totalCategories,
    required this.totalProducts,
  });

  final String selectedCategory;
  final int totalCategories;
  final int totalProducts;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: dpi.scale(38),
            height: dpi.scale(38),
            decoration: BoxDecoration(
              color: MangoThemeFactory.mango.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(12)),
            ),
            child: Icon(Icons.category_rounded, color: MangoThemeFactory.mango, size: dpi.icon(20)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedCategory == 'Todas' ? 'Todas las categorías' : selectedCategory,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  '$totalProducts productos · $totalCategories categorías',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({required this.item});
  final CatalogItem item;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final item = widget.item;
    final isActive = item.status.toLowerCase() == 'activo';
    final statusColor = isActive ? MangoThemeFactory.success : MangoThemeFactory.mutedText(context);

    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(10)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: item.hasModifiers ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(dpi.radius(16)),
            child: Padding(
              padding: EdgeInsets.all(dpi.space(14)),
              child: Row(
                children: [
                  Container(
                    width: dpi.scale(38),
                    height: dpi.scale(38),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(dpi.radius(10)),
                    ),
                    child: Icon(Icons.fastfood_rounded, color: statusColor, size: dpi.icon(18)),
                  ),
                  SizedBox(width: dpi.space(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(height: dpi.space(2)),
                        Row(
                          children: [
                            Container(
                              width: dpi.scale(6),
                              height: dpi.scale(6),
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: dpi.space(5)),
                            Text(
                              isActive ? 'Disponible' : 'No disponible',
                              style: TextStyle(fontSize: dpi.font(11), color: statusColor, fontWeight: FontWeight.w600),
                            ),
                            if (item.category != null && item.category!.trim().isNotEmpty) ...[
                              SizedBox(width: dpi.space(8)),
                              Text(
                                item.category!.trim(),
                                style: TextStyle(fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context)),
                              ),
                            ],
                            if (item.hasModifiers) ...[
                              SizedBox(width: dpi.space(8)),
                              Icon(
                                _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                size: dpi.icon(16),
                                color: MangoThemeFactory.mutedText(context),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (item.price != null)
                    Text(
                      MangoFormatters.currency(item.price!),
                      style: TextStyle(fontSize: dpi.font(15), fontWeight: FontWeight.w800, color: MangoThemeFactory.textColor(context)),
                    ),
                ],
              ),
            ),
          ),
          // Extras expandidos
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildModifiers(context, dpi, item),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildModifiers(BuildContext context, DpiScale dpi, CatalogItem item) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(dpi.space(14), 0, dpi.space(14), dpi.space(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: MangoThemeFactory.borderColor(context), height: 1),
          SizedBox(height: dpi.space(10)),
          ...item.modifierGroups.map((group) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      group.name,
                      style: TextStyle(fontSize: dpi.font(12), fontWeight: FontWeight.w800, color: MangoThemeFactory.textColor(context)),
                    ),
                    SizedBox(width: dpi.space(6)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: dpi.space(6), vertical: dpi.space(2)),
                      decoration: BoxDecoration(
                        color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(dpi.radius(4)),
                      ),
                      child: Text(
                        group.modeLabel,
                        style: TextStyle(fontSize: dpi.font(9), fontWeight: FontWeight.w700, color: MangoThemeFactory.mango),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: dpi.space(6)),
                ...group.modifiers.map((mod) {
                  final modColor = mod.isActive ? MangoThemeFactory.textColor(context) : MangoThemeFactory.mutedText(context);
                  return Padding(
                    padding: EdgeInsets.only(left: dpi.space(8), bottom: dpi.space(4)),
                    child: Row(
                      children: [
                        Icon(
                          mod.isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: dpi.icon(14),
                          color: mod.isActive ? MangoThemeFactory.success : MangoThemeFactory.mutedText(context),
                        ),
                        SizedBox(width: dpi.space(6)),
                        Expanded(
                          child: Text(mod.name, style: TextStyle(fontSize: dpi.font(12), color: modColor)),
                        ),
                        if (mod.priceDelta != 0)
                          Text(
                            '${mod.priceDelta > 0 ? '+' : ''}${MangoFormatters.currency(mod.priceDelta)}',
                            style: TextStyle(fontSize: dpi.font(11), fontWeight: FontWeight.w700, color: mod.priceDelta > 0 ? MangoThemeFactory.mango : Colors.redAccent),
                          ),
                      ],
                    ),
                  );
                }),
                SizedBox(height: dpi.space(6)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class OrdersView extends StatelessWidget {
  const OrdersView({super.key, required this.dataState, required this.onRefresh});

  final DashboardDataState dataState;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _buildOrdersContent(context, dpi),
    );
  }

  Widget _buildOrdersContent(BuildContext context, DpiScale dpi) {
    final orders = dataState.summary?.liveOrders ?? const <LiveOrderItem>[];

    if (dataState.isLoading) {
      return const DashboardSkeleton(key: ValueKey('skeleton_orders'));
    }

    return RefreshIndicator(
      key: const ValueKey('content_orders'),
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          Text('Órdenes Activas', style: Theme.of(context).textTheme.headlineMedium),
          SizedBox(height: dpi.space(4)),
          Text('Selecciona una para ver detalles', style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: dpi.space(20)),
          if (orders.isEmpty)
            const EmptyStateCard(title: 'Sin órdenes', message: 'No hay órdenes abiertas ahora mismo.')
          else
            ...orders.map((order) => _OrderCard(order: order)),
          SizedBox(height: dpi.space(30)),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final LiveOrderItem order;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(12)),
      child: InkWell(
        onTap: () => _showOrderDetails(context, order),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        child: Container(
          padding: EdgeInsets.all(dpi.space(16)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            borderRadius: BorderRadius.circular(dpi.radius(20)),
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: dpi.scale(42),
                height: dpi.scale(42),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(dpi.radius(12)),
                ),
                child: Icon(Icons.restaurant_rounded, color: MangoThemeFactory.mango, size: dpi.icon(22)),
              ),
              SizedBox(width: dpi.space(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (order.subtitle.toLowerCase() != 'sent_to_kitchen') ...[
                      SizedBox(height: dpi.space(2)),
                      Text(order.subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MangoFormatters.currency(order.total),
                    style: TextStyle(
                      fontSize: dpi.font(16),
                      fontWeight: FontWeight.w800,
                      color: MangoThemeFactory.textColor(context),
                    ),
                  ),
                  SizedBox(height: dpi.space(4)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(3)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(dpi.radius(6)),
                    ),
                    child: Text(
                      'ACTIVA',
                      style: TextStyle(
                        fontSize: dpi.font(10),
                        fontWeight: FontWeight.w800,
                        color: MangoThemeFactory.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOrderDetails(BuildContext context, LiveOrderItem order) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _OrderDetailsSheet(order: order),
    );
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  const _OrderDetailsSheet({required this.order});
  final LiveOrderItem order;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      top: false,
      child: Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      padding: EdgeInsets.all(dpi.space(22)),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(dpi.radius(28))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - fixed
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Detalles de la Orden',
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          SizedBox(height: dpi.space(8)),
          Text(
            order.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (order.status.toLowerCase() != 'sent_to_kitchen') ...[
            SizedBox(height: dpi.space(2)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: dpi.space(8), vertical: dpi.space(3)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(dpi.radius(6)),
              ),
              child: Text(
                order.status.toUpperCase(),
                style: TextStyle(fontSize: dpi.font(10), fontWeight: FontWeight.w800, color: MangoThemeFactory.success),
              ),
            ),
          ],
          SizedBox(height: dpi.space(16)),

          // Items list - scrollable
          if (order.items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: dpi.space(16)),
              child: Center(
                child: Text(
                  'No hay productos registrados en esta orden.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: order.items.length,
                separatorBuilder: (context, index) => SizedBox(height: dpi.space(10)),
                itemBuilder: (context, index) {
                  final it = order.items[index];
                  return Row(
                    children: [
                      Container(
                        width: dpi.scale(28),
                        height: dpi.scale(28),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          it.quantity.toStringAsFixed(0),
                          style: TextStyle(fontSize: dpi.font(12), fontWeight: FontWeight.bold, color: MangoThemeFactory.mango),
                        ),
                      ),
                      SizedBox(width: dpi.space(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.name,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                            if (it.extras.isNotEmpty) ...[
                              SizedBox(height: dpi.space(2)),
                              Text(
                                it.extras.join(' · '),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: dpi.font(10),
                                      color: MangoThemeFactory.mutedText(context),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: dpi.space(8)),
                      Text(
                        MangoFormatters.currency(it.total),
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: dpi.font(14)),
                      ),
                    ],
                  );
                },
              ),
            ),

          // Total - fixed at bottom
          SizedBox(height: dpi.space(12)),
          const Divider(),
          SizedBox(height: dpi.space(10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total de la Orden', style: Theme.of(context).textTheme.titleMedium),
              Text(
                MangoFormatters.currency(order.total),
                style: TextStyle(fontSize: dpi.font(20), fontWeight: FontWeight.w900, color: MangoThemeFactory.mango),
              ),
            ],
          ),
          SizedBox(height: dpi.space(16)),
        ],
      ),
    ));
  }
}


class BusinessSelectorCard extends ConsumerWidget {
  const BusinessSelectorCard({super.key, required this.profile});

  final AdminAccessProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = profile.memberships;
    return EmptyStateCard(
      title: 'Negocio / sucursal',
      message: profile.branchName?.trim().isNotEmpty == true
          ? profile.branchName!
          : (profile.businessName ?? 'Sin nombre'),
      action: memberships.length <= 1
          ? Text(
              'Solo tienes un negocio asignado.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : DropdownButtonFormField<String>(
              initialValue: profile.businessId,
              decoration: const InputDecoration(labelText: 'Seleccionar negocio'),
              items: memberships
                  .where((item) => item.allowed)
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.businessId,
                      child: Text(
                        item.branchName?.trim().isNotEmpty == true
                            ? '${item.branchName} · ${item.normalizedRole}'
                            : '${item.businessName ?? item.businessId} · ${item.normalizedRole}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) async {
                if (value == null || value == profile.businessId) return;
                await ref.read(authGateViewModelProvider.notifier).switchBusiness(value);
              },
            ),
    );
  }
}

class SettingsView extends ConsumerWidget {
  const SettingsView({
    super.key,
    required this.themeMode,
    required this.profile,
    required this.cashState,
    required this.onRefresh,
  });

  final ThemeMode themeMode;
  final AdminAccessProfile profile;
  final CashRegisterState cashState;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.symmetric(horizontal: dpi.space(18), vertical: dpi.space(12)),
      children: [
        Text('Ajustes', style: Theme.of(context).textTheme.headlineMedium),
        SizedBox(height: dpi.space(20)),
        
        // --- Profile Section ---
        Container(
          padding: EdgeInsets.all(dpi.space(20)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            borderRadius: BorderRadius.circular(dpi.radius(24)),
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: Column(
            children: [
              Container(
                width: dpi.scale(70),
                height: dpi.scale(70),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.7)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: MangoThemeFactory.mango.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  profile.userName.isNotEmpty ? profile.userName[0].toUpperCase() : 'U',
                  style: TextStyle(fontSize: dpi.font(28), fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
              SizedBox(height: dpi.space(14)),
              Text(profile.userName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: dpi.font(18))),
              Text(profile.email ?? '', style: Theme.of(context).textTheme.bodySmall),
              SizedBox(height: dpi.space(12)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: dpi.space(14), vertical: dpi.space(5)),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(dpi.radius(10)),
                ),
                child: Text(
                  profile.normalizedRole.toUpperCase(),
                  style: TextStyle(fontSize: dpi.font(10), fontWeight: FontWeight.w800, color: MangoThemeFactory.mango, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: dpi.space(24)),
        _SettingsHeader(title: 'Apariencia'),
        SizedBox(height: dpi.space(12)),
        
        Container(
          padding: EdgeInsets.all(dpi.space(16)),
          decoration: BoxDecoration(
            color: MangoThemeFactory.cardColor(context),
            borderRadius: BorderRadius.circular(dpi.radius(20)),
            border: Border.all(color: MangoThemeFactory.borderColor(context)),
          ),
          child: Column(
            children: [
              _ThemeOption(
                icon: Icons.light_mode_rounded,
                label: 'Modo Claro',
                selected: themeMode == ThemeMode.light,
                onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.light),
              ),
              Divider(height: dpi.space(24), color: MangoThemeFactory.borderColor(context).withValues(alpha: 0.5)),
              _ThemeOption(
                icon: Icons.dark_mode_rounded,
                label: 'Modo Oscuro',
                selected: themeMode == ThemeMode.dark,
                onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark),
              ),
              Divider(height: dpi.space(24), color: MangoThemeFactory.borderColor(context).withValues(alpha: 0.5)),
              _ThemeOption(
                icon: Icons.brightness_auto_rounded,
                label: 'Sistema',
                selected: themeMode == ThemeMode.system,
                onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.system),
              ),
            ],
          ),
        ),

        SizedBox(height: dpi.space(32)),
        _SettingsHeader(title: 'Caja'),
        SizedBox(height: dpi.space(12)),

        // --- Caja Summary Cards ---
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _CashSummaryCard(
                title: 'Cajas registradas',
                value: cashState.summary != null
                    ? MangoFormatters.number(cashState.summary!.activeRegisters)
                    : (cashState.isLoading ? '...' : '—'),
                subtitle: cashState.summary != null
                    ? '${cashState.summary!.totalRegisters} total · ${cashState.summary!.inactiveRegistersCount} inactivas'
                    : 'Cajas activas del negocio',
                icon: Icons.point_of_sale_rounded,
                color: MangoThemeFactory.info,
              ),
              _CashSummaryCard(
                title: 'Cajas abiertas',
                value: cashState.summary != null
                    ? MangoFormatters.number(cashState.summary!.openRegistersCount)
                    : (cashState.isLoading ? '...' : '—'),
                subtitle: cashState.summary != null
                    ? 'Con sesión abierta ahora'
                    : 'Sesiones abiertas',
                icon: Icons.lock_open_rounded,
                color: MangoThemeFactory.mango,
              ),
              _CashSummaryCard(
                title: 'Top caja (ventas)',
                value: cashState.summary?.topRegister != null
                    ? MangoFormatters.currency(cashState.summary!.topRegister!.totalSales)
                    : (cashState.isLoading ? '...' : '—'),
                subtitle: cashState.summary?.topRegister != null
                    ? cashState.summary!.topRegister!.registerName
                    : 'Caja con más ventas visibles',
                icon: Icons.emoji_events_rounded,
                color: MangoThemeFactory.success,
              ),
            ];
            final crossCount = constraints.maxWidth >= 760 ? 3 : 1;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossCount,
              crossAxisSpacing: dpi.space(12),
              mainAxisSpacing: dpi.space(12),
              childAspectRatio: crossCount == 3 ? 1.3 : 2.1,
              children: cards,
            );
          },
        ),
        SizedBox(height: dpi.space(12)),

        // --- Gestionar Cierres Button ---
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CashRegisterDetailView(summary: cashState.summary, error: cashState.error),
            ),
          ),
          borderRadius: BorderRadius.circular(dpi.radius(16)),
          child: Container(
            padding: EdgeInsets.all(dpi.space(16)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(16)),
              border: Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(36),
                  height: dpi.scale(36),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Icon(Icons.assignment_rounded, color: MangoThemeFactory.mango, size: dpi.icon(20)),
                ),
                SizedBox(width: dpi.space(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestionar Cierres',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: dpi.font(15), color: MangoThemeFactory.textColor(context)),
                      ),
                      Text(
                        cashState.summary != null
                            ? '${cashState.summary!.openRegistersCount} abiertas · ${cashState.summary!.closings.length} cierres recientes'
                            : 'Ver historial de cierres de caja',
                        style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: MangoThemeFactory.mutedText(context)),
              ],
            ),
          ),
        ),

        SizedBox(height: dpi.space(32)),
        _SettingsHeader(title: 'Cuentas'),
        SizedBox(height: dpi.space(12)),

        _AccountsSection(currentProfile: profile),

        SizedBox(height: dpi.space(32)),
        _SettingsHeader(title: 'Sesión'),
        SizedBox(height: dpi.space(12)),

        InkWell(
          onTap: () => ref.read(authGateViewModelProvider.notifier).signOut(),
          borderRadius: BorderRadius.circular(dpi.radius(16)),
          child: Container(
            padding: EdgeInsets.all(dpi.space(16)),
            decoration: BoxDecoration(
              color: isDark ? Colors.red.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(dpi.radius(16)),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.logout_rounded, color: Colors.redAccent, size: dpi.icon(22)),
                SizedBox(width: dpi.space(14)),
                Text(
                  'Cerrar sesión',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: dpi.font(15)),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: Colors.redAccent.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
        SizedBox(height: dpi.space(40)),
      ],
      ),
    );
  }
}

class _CashSummaryCard extends StatelessWidget {
  const _CashSummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dpi.scale(36),
            height: dpi.scale(36),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(icon, color: color, size: dpi.icon(20)),
          ),
          SizedBox(height: dpi.space(10)),
          Text(
            title,
            style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context), fontWeight: FontWeight.w500),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dpi.font(22), fontWeight: FontWeight.w800, color: MangoThemeFactory.textColor(context)),
            ),
          ),
          SizedBox(height: dpi.space(4)),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context)),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: dpi.font(11),
        fontWeight: FontWeight.w800,
        color: MangoThemeFactory.mutedText(context),
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dpi.radius(12)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dpi.space(4)),
        child: Row(
          children: [
            Container(
              width: dpi.scale(36),
              height: dpi.scale(36),
              decoration: BoxDecoration(
                color: selected ? MangoThemeFactory.mango.withValues(alpha: 0.1) : MangoThemeFactory.borderColor(context).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(dpi.radius(10)),
              ),
              child: Icon(icon, color: selected ? MangoThemeFactory.mango : MangoThemeFactory.mutedText(context), size: dpi.icon(20)),
            ),
            SizedBox(width: dpi.space(14)),
            Text(
              label,
              style: TextStyle(
                fontSize: dpi.font(15),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? MangoThemeFactory.mango : MangoThemeFactory.textColor(context),
              ),
            ),
            const Spacer(),
            if (selected)
              Icon(Icons.check_circle_rounded, color: MangoThemeFactory.mango, size: dpi.icon(20)),
          ],
        ),
      ),
    );
  }
}

class _AccountsSection extends ConsumerStatefulWidget {
  const _AccountsSection({required this.currentProfile});
  final AdminAccessProfile currentProfile;

  @override
  ConsumerState<_AccountsSection> createState() => _AccountsSectionState();
}

class _AccountsSectionState extends ConsumerState<_AccountsSection> {
  List<SavedAccount> _otherAccounts = [];
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final all = await ref.read(savedAccountsServiceProvider).loadAccounts();
    if (mounted) {
      setState(() {
        _otherAccounts = all
            .where((a) => a.email != widget.currentProfile.email)
            .toList();
      });
    }
  }

  Future<void> _switchTo(SavedAccount account) async {
    if (_switching) return;
    setState(() => _switching = true);

    // Intentar con token guardado primero
    if (account.refreshToken != null) {
      final error = await ref
          .read(authGateViewModelProvider.notifier)
          .switchAccountByToken(account.refreshToken!);
      if (error == null) return; // éxito
    }

    // Token expirado o no existe → pedir contraseña en dialog
    if (mounted) {
      setState(() => _switching = false);
      _showPasswordDialog(account);
    }
  }

  void _showPasswordDialog(SavedAccount account) {
    final passwordController = TextEditingController();
    String? dialogError;
    bool dialogLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final dpi = DpiScale.of(context);

          Future<void> doSwitch() async {
            setDialogState(() { dialogLoading = true; dialogError = null; });
            final error = await ref
                .read(authGateViewModelProvider.notifier)
                .switchAccountWithPassword(
                  email: account.email,
                  password: passwordController.text,
                );
            if (error != null) {
              setDialogState(() { dialogLoading = false; dialogError = error; });
            } else if (context.mounted) {
              Navigator.pop(context);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(dpi.radius(20))),
            title: Text('Cambiar a ${account.displayName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'La sesión expiró. Ingresa tu contraseña.',
                  style: TextStyle(fontSize: dpi.font(13), color: MangoThemeFactory.mutedText(context)),
                ),
                SizedBox(height: dpi.space(16)),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  enabled: !dialogLoading,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(dpi.radius(10))),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(dpi.radius(10)),
                      borderSide: const BorderSide(color: MangoThemeFactory.mango, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => doSwitch(),
                ),
                if (dialogError != null) ...[
                  SizedBox(height: dpi.space(12)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(dpi.space(10)),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(dpi.radius(8)),
                    ),
                    child: Text(
                      dialogError!,
                      style: TextStyle(color: MangoThemeFactory.danger, fontSize: dpi.font(12)),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: dialogLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: dialogLoading ? null : doSwitch,
                style: FilledButton.styleFrom(backgroundColor: MangoThemeFactory.mango),
                child: dialogLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Entrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        children: [
          // Otras cuentas guardadas
          if (_otherAccounts.isNotEmpty)
            ..._otherAccounts.map((account) => Padding(
              padding: EdgeInsets.only(bottom: dpi.space(8)),
              child: InkWell(
                onTap: _switching ? null : () => _switchTo(account),
                borderRadius: BorderRadius.circular(dpi.radius(14)),
                child: Container(
                  padding: EdgeInsets.all(dpi.space(14)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(dpi.radius(14)),
                    border: Border.all(color: MangoThemeFactory.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: dpi.scale(38),
                        height: dpi.scale(38),
                        decoration: BoxDecoration(
                          color: MangoThemeFactory.mango.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          account.displayName.isNotEmpty
                              ? account.displayName[0].toUpperCase()
                              : account.email[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: dpi.font(16),
                            fontWeight: FontWeight.w800,
                            color: MangoThemeFactory.mango,
                          ),
                        ),
                      ),
                      SizedBox(width: dpi.space(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.displayName,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: dpi.font(14)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              account.email,
                              style: TextStyle(fontSize: dpi.font(12), color: MangoThemeFactory.mutedText(context)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (account.businessName != null)
                              Text(
                                account.businessName!,
                                style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      _switching
                          ? SizedBox(
                              width: dpi.scale(22),
                              height: dpi.scale(22),
                              child: CircularProgressIndicator(strokeWidth: 2, color: MangoThemeFactory.mango),
                            )
                          : Icon(Icons.swap_horiz_rounded, color: MangoThemeFactory.mango, size: dpi.icon(22)),
                    ],
                  ),
                ),
              ),
            )),

          // Agregar otra cuenta
          InkWell(
            onTap: () {
              // Cerrar sesión para ir al login donde se pueden agregar cuentas
              ref.read(authGateViewModelProvider.notifier).signOut();
            },
            borderRadius: BorderRadius.circular(dpi.radius(14)),
            child: Container(
              padding: EdgeInsets.all(dpi.space(14)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(dpi.radius(14)),
                border: Border.all(
                  color: MangoThemeFactory.mango.withValues(alpha: 0.3),
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add_alt_1_rounded, color: MangoThemeFactory.mango, size: dpi.icon(20)),
                  SizedBox(width: dpi.space(10)),
                  Text(
                    'Agregar otra cuenta',
                    style: TextStyle(
                      color: MangoThemeFactory.mango,
                      fontWeight: FontWeight.w700,
                      fontSize: dpi.font(14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isError = title.toLowerCase().contains('error');
    final color = isError ? Colors.redAccent : MangoThemeFactory.textColor(context);
    final bgColor = isError ? Colors.red.withValues(alpha: 0.05) : MangoThemeFactory.cardColor(context);
    final borderColor = isError ? Colors.red.withValues(alpha: 0.2) : MangoThemeFactory.borderColor(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isError) ...[
                Icon(Icons.error_outline_rounded, color: color, size: dpi.icon(20)),
                SizedBox(width: dpi.space(8)),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: isError ? color.withValues(alpha: 0.8) : null,
                ),
          ),
          if (action != null) ...[
            SizedBox(height: dpi.space(16)),
            action!,
          ],
        ],
      ),
    );
  }
}

