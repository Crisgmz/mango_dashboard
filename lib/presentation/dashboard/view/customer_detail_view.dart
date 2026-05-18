import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';

/// Customer drill-down — header with summary stats + a chronological list
/// of every visit (payment) the customer made in the period.
class CustomerDetailView extends ConsumerStatefulWidget {
  const CustomerDetailView({
    super.key,
    required this.customer,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final CustomerSummary customer;
  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<CustomerDetailView> createState() => _CustomerDetailViewState();
}

class _CustomerDetailViewState extends ConsumerState<CustomerDetailView> {
  late Future<List<CustomerVisit>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CustomerVisit>> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const [];
    return ref.read(dashboardDataServiceProvider).loadCustomerVisits(
          businessId: businessId,
          customerKey: widget.customer.customerKey,
          start: widget.start,
          end: widget.end,
        );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cliente'),
        centerTitle: false,
      ),
      body: FutureBuilder<List<CustomerVisit>>(
        future: _future,
        builder: (context, snapshot) {
          final visits = snapshot.data ?? const <CustomerVisit>[];
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16),
                dpi.space(16) + MediaQuery.of(context).padding.bottom),
            children: [
              _Header(customer: widget.customer, periodLabel: widget.periodLabel),
              SizedBox(height: dpi.space(16)),
              Text('Visitas en este periodo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: dpi.space(10)),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(20)),
                  child: Center(
                    child: Text('No se pudo cargar el detalle.',
                        style: TextStyle(color: MangoThemeFactory.danger)),
                  ),
                )
              else if (visits.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(20)),
                  child: Center(
                    child: Text('Sin visitas registradas.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                )
              else
                ...visits.map((v) => Padding(
                      padding: EdgeInsets.only(bottom: dpi.space(8)),
                      child: _VisitTile(visit: v),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.customer, this.periodLabel});
  final CustomerSummary customer;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final initials = _initialsFor(customer.displayName);
    final days = customer.daysSinceLastVisit(DateTime.now());
    final lastLabel = days == 0
        ? 'hoy'
        : days == 1
            ? 'ayer'
            : 'hace $days días';
    return Container(
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
              Container(
                width: dpi.scale(48),
                height: dpi.scale(48),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: dpi.font(16),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: dpi.space(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.displayName,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: dpi.font(18),
                          fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _subtitle(customer, periodLabel),
                      style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(14)),
          Row(
            children: [
              Expanded(
                  child:
                      _Stat(label: 'Gastado', value: MangoFormatters.currency(customer.totalSpent))),
              _verticalDivider(dpi),
              Expanded(child: _Stat(label: 'Visitas', value: '${customer.visitCount}')),
              _verticalDivider(dpi),
              Expanded(
                  child: _Stat(
                      label: 'Ticket prom.',
                      value: MangoFormatters.currency(customer.averageTicket))),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Icon(Icons.schedule_rounded, color: Colors.white70, size: dpi.icon(14)),
              SizedBox(width: dpi.space(6)),
              Text(
                'Última visita $lastLabel',
                style: TextStyle(color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(CustomerSummary c, String? periodLabel) {
    final parts = <String>[];
    if (c.rnc != null && c.rnc!.isNotEmpty) parts.add('RNC ${c.rnc}');
    if (periodLabel != null) parts.add(periodLabel);
    return parts.isEmpty ? 'Cliente' : parts.join(' · ');
  }

  Widget _verticalDivider(DpiScale dpi) => Container(
        width: 1,
        height: dpi.scale(26),
        color: Colors.white.withValues(alpha: 0.22),
      );

  static String _initialsFor(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(6)),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: dpi.font(10))),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: dpi.font(15),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitTile extends StatelessWidget {
  const _VisitTile({required this.visit});
  final CustomerVisit visit;

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
  static const _methodLabels = <String, String>{
    'cash': 'Efectivo',
    'card': 'Tarjeta',
    'transfer': 'Transferencia',
  };

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pmColor = _methodColors[visit.paymentMethodCode] ?? MangoThemeFactory.mutedText(context);
    final pmIcon = _methodIcons[visit.paymentMethodCode] ?? Icons.receipt_rounded;
    final pmLabel = _methodLabels[visit.paymentMethodCode] ?? 'Otro';

    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: dpi.scale(36),
            height: dpi.scale(36),
            decoration: BoxDecoration(
              color: pmColor.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(pmIcon, color: pmColor, size: dpi.icon(18)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MangoFormatters.dateTime(visit.createdAt),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  _subtitleFor(visit, pmLabel),
                  style: TextStyle(
                    fontSize: dpi.font(11),
                    color: MangoThemeFactory.mutedText(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: dpi.space(8)),
          Text(
            MangoFormatters.currency(visit.amount),
            style: TextStyle(
              fontSize: dpi.font(14),
              fontWeight: FontWeight.w800,
              color: pmColor,
            ),
          ),
        ],
      ),
    );
  }

  String _subtitleFor(CustomerVisit v, String pmLabel) {
    final parts = <String>[pmLabel];
    if (v.tableLabel != null && v.tableLabel!.isNotEmpty) parts.add(v.tableLabel!);
    return parts.join(' · ');
  }
}
