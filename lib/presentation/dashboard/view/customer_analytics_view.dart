import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';
import 'customer_detail_view.dart';

/// Customer analytics: ranks customers (RNC or named) by spend in the
/// selected period and lets the user filter by recurrence pattern.
class CustomerAnalyticsView extends ConsumerStatefulWidget {
  const CustomerAnalyticsView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<CustomerAnalyticsView> createState() => _CustomerAnalyticsViewState();
}

enum _Filter { all, recurring, firstTime }

class _CustomerAnalyticsViewState extends ConsumerState<CustomerAnalyticsView> {
  late Future<List<CustomerSummary>> _future;
  _Filter _filter = _Filter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CustomerSummary>> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const [];
    return ref.read(dashboardDataServiceProvider).loadCustomerAnalytics(
          businessId: businessId,
          start: widget.start,
          end: widget.end,
        );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        centerTitle: false,
      ),
      body: FutureBuilder<List<CustomerSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(dpi.space(20)),
                child: Text(
                  'No se pudo cargar la información de clientes.',
                  style: TextStyle(color: MangoThemeFactory.danger),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final all = snapshot.data ?? const <CustomerSummary>[];
          final totalSpent = all.fold<double>(0, (s, c) => s + c.totalSpent);
          final totalVisits = all.fold<int>(0, (s, c) => s + c.visitCount);
          final recurringCount = all.where((c) => c.isRecurring).length;

          // Apply filters.
          final filtered = all.where((c) {
            switch (_filter) {
              case _Filter.recurring:
                if (!c.isRecurring) return false;
                break;
              case _Filter.firstTime:
                if (!c.isFirstTime) return false;
                break;
              case _Filter.all:
                break;
            }
            if (_query.isEmpty) return true;
            final q = _query.toLowerCase();
            return c.displayName.toLowerCase().contains(q) ||
                (c.rnc?.toLowerCase().contains(q) ?? false);
          }).toList();

          return Column(
            children: [
              _Header(
                customerCount: all.length,
                totalSpent: totalSpent,
                totalVisits: totalVisits,
                recurringCount: recurringCount,
                periodLabel: widget.periodLabel,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16), dpi.space(8)),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente o RNC…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: dpi.space(12), vertical: dpi.space(12)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(dpi.radius(12))),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'Todos (${all.length})',
                        selected: _filter == _Filter.all,
                        onTap: () => setState(() => _filter = _Filter.all),
                      ),
                      SizedBox(width: dpi.space(6)),
                      _FilterChip(
                        label: 'Recurrentes ($recurringCount)',
                        selected: _filter == _Filter.recurring,
                        onTap: () => setState(() => _filter = _Filter.recurring),
                      ),
                      SizedBox(width: dpi.space(6)),
                      _FilterChip(
                        label: 'Nuevos (${all.length - recurringCount})',
                        selected: _filter == _Filter.firstTime,
                        onTap: () => setState(() => _filter = _Filter.firstTime),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: dpi.space(8)),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No hay clientes en este filtro.'
                              : 'Sin resultados para "$_query".',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
                            dpi.space(16) + MediaQuery.of(context).padding.bottom),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
                        itemBuilder: (context, index) {
                          final customer = filtered[index];
                          return _CustomerTile(
                            rank: index + 1,
                            customer: customer,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CustomerDetailView(
                                  customer: customer,
                                  start: widget.start,
                                  end: widget.end,
                                  periodLabel: widget.periodLabel,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.customerCount,
    required this.totalSpent,
    required this.totalVisits,
    required this.recurringCount,
    this.periodLabel,
  });
  final int customerCount;
  final double totalSpent;
  final int totalVisits;
  final int recurringCount;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final retentionRate = customerCount == 0 ? 0 : (recurringCount / customerCount) * 100;
    return Container(
      margin: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(12)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.info, MangoThemeFactory.info.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                periodLabel == null ? 'Clientes' : 'Clientes · $periodLabel',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: dpi.font(12),
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gasto total',
                        style:
                            TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
                    SizedBox(height: dpi.space(2)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        MangoFormatters.currency(totalSpent),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: dpi.font(22),
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: dpi.space(12)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$customerCount',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: dpi.font(20),
                          fontWeight: FontWeight.w800)),
                  Text('clientes',
                      style: TextStyle(color: Colors.white70, fontSize: dpi.font(11))),
                  SizedBox(height: dpi.space(4)),
                  Text(
                    '$totalVisits visitas · ${retentionRate.toStringAsFixed(0)}% recurren',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: dpi.font(11),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: MangoThemeFactory.info.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? MangoThemeFactory.info : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: dpi.font(12),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.rank,
    required this.customer,
    required this.onTap,
  });

  final int rank;
  final CustomerSummary customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initials = _initialsFor(customer.displayName);
    final rankColor = rank == 1
        ? MangoThemeFactory.mango
        : rank == 2
            ? MangoThemeFactory.warning
            : rank == 3
                ? MangoThemeFactory.info
                : MangoThemeFactory.mutedText(context);

    final days = customer.daysSinceLastVisit(DateTime.now());
    final lastVisitLabel = days == 0
        ? 'hoy'
        : days == 1
            ? 'ayer'
            : 'hace $days días';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dpi.radius(14)),
      child: Container(
        padding: EdgeInsets.all(dpi.space(14)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          border: Border.all(color: MangoThemeFactory.borderColor(context)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: dpi.scale(38),
                  height: dpi.scale(38),
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: isDark ? 0.2 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: dpi.font(13),
                      fontWeight: FontWeight.w800,
                      color: rankColor,
                    ),
                  ),
                ),
                if (rank <= 3)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: dpi.scale(16),
                      height: dpi.scale(16),
                      decoration: BoxDecoration(
                        color: rankColor,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: MangoThemeFactory.cardColor(context), width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: dpi.font(8),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: dpi.space(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          customer.displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (customer.isRecurring) ...[
                        SizedBox(width: dpi.space(6)),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: dpi.space(6), vertical: dpi.space(2)),
                          decoration: BoxDecoration(
                            color: MangoThemeFactory.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(dpi.radius(4)),
                          ),
                          child: Text(
                            'RECURRENTE',
                            style: TextStyle(
                              fontSize: dpi.font(8),
                              fontWeight: FontWeight.w800,
                              color: MangoThemeFactory.success,
                            ),
                          ),
                        ),
                      ] else if (customer.isFirstTime) ...[
                        SizedBox(width: dpi.space(6)),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: dpi.space(6), vertical: dpi.space(2)),
                          decoration: BoxDecoration(
                            color: MangoThemeFactory.info.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(dpi.radius(4)),
                          ),
                          child: Text(
                            'NUEVO',
                            style: TextStyle(
                              fontSize: dpi.font(8),
                              fontWeight: FontWeight.w800,
                              color: MangoThemeFactory.info,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: dpi.space(2)),
                  Text(
                    _subtitleFor(customer, lastVisitLabel),
                    style: TextStyle(
                        fontSize: dpi.font(11),
                        color: MangoThemeFactory.mutedText(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: dpi.space(8)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  MangoFormatters.currency(customer.totalSpent),
                  style: TextStyle(
                    fontSize: dpi.font(14),
                    fontWeight: FontWeight.w800,
                    color: MangoThemeFactory.info,
                  ),
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  '${customer.visitCount} ${customer.visitCount == 1 ? 'visita' : 'visitas'}',
                  style: TextStyle(
                      fontSize: dpi.font(10),
                      color: MangoThemeFactory.mutedText(context)),
                ),
              ],
            ),
            SizedBox(width: dpi.space(4)),
            Icon(Icons.chevron_right_rounded,
                size: dpi.icon(18), color: MangoThemeFactory.mutedText(context)),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(CustomerSummary c, String lastVisitLabel) {
    final parts = <String>[];
    if (c.rnc != null && c.rnc!.isNotEmpty) parts.add('RNC ${c.rnc}');
    parts.add('Última $lastVisitLabel');
    parts.add('prom. ${MangoFormatters.currency(c.averageTicket)}');
    return parts.join(' · ');
  }

  static String _initialsFor(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
