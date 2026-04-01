import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_mapper.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/auth/admin_access_profile.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/view/login_view.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_data_factory.dart';
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

  void _goToTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authGateViewModelProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authGateViewModelProvider);
    final homeDataState = ref.watch(dashboardHomeDataViewModelProvider);
    final salesDataState = ref.watch(salesDataViewModelProvider);
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
      _loadedBusinessId = profile.businessId;
      Future.microtask(() async {
        await ref.read(dashboardHomeDataViewModelProvider.notifier).load(
          profile,
          filter: SalesDateFilter.today,
        );
        await ref.read(salesDataViewModelProvider.notifier).load(
          profile,
          filter: SalesDateFilter.month,
        );
      });
    }

    final pages = [
      HomeView(
        profile: profile,
        dataState: homeDataState,
        onOpenSales: () => _goToTab(1),
        onOpenItems: () => _goToTab(2),
        onOpenOrders: () => _goToTab(3),
      ),
      SalesView(profile: profile, dataState: salesDataState),
      ItemsView(dataState: homeDataState),
      OrdersView(dataState: homeDataState),
      SettingsView(themeMode: themeMode, profile: profile),
    ];

    return Scaffold(
      appBar: (_currentIndex == 0 ? homeDataState.isRefreshing : salesDataState.isRefreshing)
          ? PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(MangoThemeFactory.mango.withValues(alpha: 0.5)),
              ),
            )
          : null,
      body: SafeArea(child: IndexedStack(index: _currentIndex, children: pages)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (value) => setState(() => _currentIndex = value),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Ventas'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded), label: 'Artículos'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Órdenes'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Ajustes'),
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
                    FilledButton.icon(
                      onPressed: () => ref.read(themeModeProvider.notifier).state = _nextMode(themeMode),
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
  });

  final AdminAccessProfile profile;
  final DashboardDataState dataState;
  final VoidCallback onOpenSales;
  final VoidCallback onOpenItems;
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (dataState.isLoading) return const DashboardSkeleton();

    if (dataState.error != null) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          _HomeHeader(profile: profile),
          SizedBox(height: dpi.space(18)),
          EmptyStateCard(title: 'Error', message: dataState.error!),
        ],
      );
    }

    if (dataState.summary == null) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          _HomeHeader(profile: profile),
          SizedBox(height: dpi.space(18)),
          const EmptyStateCard(title: 'Sin datos', message: 'No se pudo cargar el resumen.'),
        ],
      );
    }

    final summary = dataState.summary!;
    final gap = SizedBox(height: dpi.space(18));

    return ListView(
      physics: const BouncingScrollPhysics(),
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
    );
  }
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.profile});

  final AdminAccessProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final greeting = _greetingByTime();
    final hasMultiple = profile.memberships.length > 1;
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
                onTap: hasMultiple ? () => _showBusinessSelector(context, ref) : null,
                borderRadius: BorderRadius.circular(dpi.radius(12)),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(4)),
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
                            child: Text(
                              profile.userName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasMultiple) ...[
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

  void _showBusinessSelector(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _BusinessSelectorSheet(
        profile: profile,
        onSelected: (id) {
          Navigator.pop(context);
          ref.read(authGateViewModelProvider.notifier).switchBusiness(id);
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

class _BusinessSelectorSheet extends StatelessWidget {
  const _BusinessSelectorSheet({required this.profile, required this.onSelected});
  final AdminAccessProfile profile;
  final Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
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
              Text('Seleccionar Sucursal', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          SizedBox(height: dpi.space(16)),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: profile.memberships.length,
              itemBuilder: (context, index) {
                final membership = profile.memberships[index];
                final isSelected = membership.businessId == profile.businessId;
                final name = membership.branchName?.trim().isNotEmpty == true
                    ? membership.branchName!
                    : (membership.businessName ?? 'Sin nombre');

                return Padding(
                  padding: EdgeInsets.only(bottom: dpi.space(10)),
                  child: InkWell(
                    onTap: () => onSelected(membership.businessId),
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
              },
            ),
          ),
          SizedBox(height: dpi.space(10)),
        ],
      ),
    );
  }
}

class SalesView extends ConsumerWidget {
  const SalesView({super.key, required this.profile, required this.dataState});

  final AdminAccessProfile profile;
  final DashboardDataState dataState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final summary = dataState.summary;

    if (dataState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (summary == null) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          Text('Ventas', style: Theme.of(context).textTheme.headlineMedium),
          SizedBox(height: dpi.space(20)),
          EmptyStateCard(title: 'Sin datos', message: dataState.error ?? 'No hay resumen de ventas disponible.'),
        ],
      );
    }

    final gap = SizedBox(height: dpi.space(18));

    return ListView(
      physics: const BouncingScrollPhysics(),
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
            child: Text(
              value,
              style: TextStyle(
                fontSize: dpi.font(18),
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : color.withValues(alpha: 0.9),
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
                      widthFactor: percent.clamp(0, 1),
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

class ItemsView extends StatelessWidget {
  const ItemsView({super.key, required this.dataState});

  final DashboardDataState dataState;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final items = dataState.summary?.catalogItems ?? const <CatalogItem>[];
    
    if (dataState.isLoading) return const Center(child: CircularProgressIndicator());

    if (items.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.all(dpi.space(18)),
        children: [
          Text('Catálogo de Productos', style: Theme.of(context).textTheme.headlineMedium),
          SizedBox(height: dpi.space(20)),
          EmptyStateCard(title: 'Sin artículos', message: dataState.error ?? 'No se encontraron productos.'),
        ],
      );
    }

    // Group items by category
    final Map<String, List<CatalogItem>> grouped = {};
    for (final item in items) {
      final cat = item.category ?? 'General';
      grouped.putIfAbsent(cat, () => []).add(item);
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(dpi.space(18)),
      children: [
        Text('Catálogo de Productos', style: Theme.of(context).textTheme.headlineMedium),
        SizedBox(height: dpi.space(4)),
        Text('Organizado por categorías', style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: dpi.space(20)),
        ...grouped.entries.map((e) => _CategoryGroup(category: e.key, items: e.value)),
        SizedBox(height: dpi.space(30)),
      ],
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({required this.category, required this.items});
  final String category;
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(4),
                height: dpi.scale(16),
                decoration: BoxDecoration(
                  color: MangoThemeFactory.mango,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(width: dpi.space(8)),
              Text(
                category.toUpperCase(),
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: MangoThemeFactory.mango,
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(12)),
          ...items.map((item) => _ProductCard(item: item)),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isActive = item.status.toLowerCase() == 'activo';
    return Container(
      margin: EdgeInsets.only(bottom: dpi.space(10)),
      padding: EdgeInsets.all(dpi.space(12)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                SizedBox(height: dpi.space(2)),
                Text(
                  isActive ? 'Disponible' : 'No disponible',
                  style: TextStyle(
                    fontSize: dpi.font(10),
                    color: isActive ? MangoThemeFactory.success : MangoThemeFactory.mutedText(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (item.price != null)
            Text(
              MangoFormatters.currency(item.price!),
              style: TextStyle(
                fontSize: dpi.font(15),
                fontWeight: FontWeight.w800,
                color: MangoThemeFactory.textColor(context),
              ),
            ),
        ],
      ),
    );
  }
}

class OrdersView extends StatelessWidget {
  const OrdersView({super.key, required this.dataState});

  final DashboardDataState dataState;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final orders = dataState.summary?.liveOrders ?? const <LiveOrderItem>[];

    if (dataState.isLoading) return const Center(child: CircularProgressIndicator());

    return ListView(
      physics: const BouncingScrollPhysics(),
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
                    SizedBox(height: dpi.space(2)),
                    Text(order.subtitle, style: Theme.of(context).textTheme.bodySmall),
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
    return Container(
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
              Text('Detalles de la Orden', style: Theme.of(context).textTheme.titleLarge),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          SizedBox(height: dpi.space(12)),
          Text(order.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('Estado: ${order.status}', style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: dpi.space(24)),
          if (order.items.isEmpty)
            const Center(child: Text('No hay productos registrados en esta orden.'))
          else
            ...order.items.map((it) => Padding(
                  padding: EdgeInsets.only(bottom: dpi.space(14)),
                  child: Row(
                    children: [
                      Container(
                        width: dpi.scale(24),
                        height: dpi.scale(24),
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
                        child: Text(it.name, style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Text(
                        MangoFormatters.currency(it.total),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                )),
          SizedBox(height: dpi.space(20)),
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
    );
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
  const SettingsView({super.key, required this.themeMode, required this.profile});

  final ThemeMode themeMode;
  final AdminAccessProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
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
                onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.light,
              ),
              Divider(height: dpi.space(24), color: MangoThemeFactory.borderColor(context).withValues(alpha: 0.5)),
              _ThemeOption(
                icon: Icons.dark_mode_rounded,
                label: 'Modo Oscuro',
                selected: themeMode == ThemeMode.dark,
                onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.dark,
              ),
              Divider(height: dpi.space(24), color: MangoThemeFactory.borderColor(context).withValues(alpha: 0.5)),
              _ThemeOption(
                icon: Icons.brightness_auto_rounded,
                label: 'Sistema',
                selected: themeMode == ThemeMode.system,
                onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.system,
              ),
            ],
          ),
        ),

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

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: dpi.space(8)),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) ...[
            SizedBox(height: dpi.space(12)),
            action!,
          ],
        ],
      ),
    );
  }
}

