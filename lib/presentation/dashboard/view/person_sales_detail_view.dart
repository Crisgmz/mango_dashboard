import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';

/// Drill-down screen used by both waiter and cashier performance cards.
/// Lists the sessions/mesas attributed to a single user in [start..end].
class PersonSalesDetailView extends ConsumerStatefulWidget {
  const PersonSalesDetailView({
    super.key,
    required this.userId,
    required this.userName,
    required this.role,
    required this.start,
    required this.end,
    required this.totalSales,
    required this.ticketCount,
    required this.tablesCount,
    this.periodLabel,
  });

  final String userId;
  final String userName;
  final PersonRole role;
  final DateTime start;
  final DateTime end;
  final double totalSales;
  final int ticketCount;
  final int tablesCount;
  final String? periodLabel;

  @override
  ConsumerState<PersonSalesDetailView> createState() => _PersonSalesDetailViewState();
}

enum PersonRole { waiter, cashier }

class _PersonSalesDetailViewState extends ConsumerState<PersonSalesDetailView> {
  late Future<List<PersonSession>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PersonSession>> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) return const [];
    final service = ref.read(dashboardDataServiceProvider);
    if (widget.role == PersonRole.waiter) {
      return service.loadSessionsForWaiter(
        businessId: businessId,
        waiterUserId: widget.userId,
        start: widget.start,
        end: widget.end,
      );
    }
    return service.loadPaymentsForCashier(
      businessId: businessId,
      cashierUserId: widget.userId,
      start: widget.start,
      end: widget.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final roleAccent =
        widget.role == PersonRole.waiter ? MangoThemeFactory.mango : MangoThemeFactory.info;
    final roleLabel = widget.role == PersonRole.waiter ? 'Mesero' : 'Cajero';
    final emptyMessage = widget.role == PersonRole.waiter
        ? 'No tiene mesas servidas en este periodo.'
        : 'No procesó pagos en este periodo.';

    return Scaffold(
      appBar: AppBar(
        title: Text(roleLabel),
        centerTitle: false,
      ),
      body: FutureBuilder<List<PersonSession>>(
        future: _future,
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? const <PersonSession>[];
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16),
                dpi.space(16) + MediaQuery.of(context).padding.bottom),
            children: [
              _PersonHeader(
                name: widget.userName,
                roleLabel: roleLabel,
                accent: roleAccent,
                totalSales: widget.totalSales,
                ticketCount: widget.ticketCount,
                tablesCount: widget.tablesCount,
                periodLabel: widget.periodLabel,
              ),
              SizedBox(height: dpi.space(16)),
              if (isLoading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(40)),
                  child: const Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(20)),
                  child: Center(
                    child: Text(
                      'No se pudo cargar el detalle.',
                      style: TextStyle(color: MangoThemeFactory.danger),
                    ),
                  ),
                )
              else if (sessions.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: dpi.space(40)),
                  child: Center(
                    child: Text(
                      emptyMessage,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              else
                ...sessions.map(
                  (s) => Padding(
                    padding: EdgeInsets.only(bottom: dpi.space(10)),
                    child: _SessionTile(session: s, accent: roleAccent),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({
    required this.name,
    required this.roleLabel,
    required this.accent,
    required this.totalSales,
    required this.ticketCount,
    required this.tablesCount,
    this.periodLabel,
  });

  final String name;
  final String roleLabel;
  final Color accent;
  final double totalSales;
  final int ticketCount;
  final int tablesCount;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final initials = _initialsFor(name);
    return Container(
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.78)]),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: dpi.scale(44),
                height: dpi.scale(44),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: dpi.font(14),
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
                      name,
                      style: TextStyle(
                          color: Colors.white, fontSize: dpi.font(18), fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      periodLabel == null ? roleLabel : '$roleLabel · $periodLabel',
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
                child: _HeaderStat(
                  label: 'Ventas',
                  value: MangoFormatters.currency(totalSales),
                ),
              ),
              _verticalDivider(dpi),
              Expanded(
                child: _HeaderStat(
                  label: 'Tickets',
                  value: '$ticketCount',
                ),
              ),
              _verticalDivider(dpi),
              Expanded(
                child: _HeaderStat(
                  label: 'Mesas',
                  value: '$tablesCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(DpiScale dpi) => Container(
        width: 1,
        height: dpi.scale(28),
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

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});
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

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.accent});
  final PersonSession session;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final timeLabel = _formatTime(session.openedAt);
    final isOpen = session.isOpen;

    return Container(
      padding: EdgeInsets.all(dpi.space(14)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(14)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: dpi.scale(40),
            height: dpi.scale(40),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(
              isOpen ? Icons.table_restaurant_rounded : Icons.check_circle_rounded,
              color: accent,
              size: dpi.icon(20),
            ),
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
                        session.tableLabel,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (session.zoneName != null) ...[
                      SizedBox(width: dpi.space(6)),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: dpi.space(6), vertical: dpi.space(2)),
                        decoration: BoxDecoration(
                          color: MangoThemeFactory.altSurface(context),
                          borderRadius: BorderRadius.circular(dpi.radius(20)),
                        ),
                        child: Text(
                          session.zoneName!,
                          style: TextStyle(
                            fontSize: dpi.font(10),
                            color: MangoThemeFactory.mutedText(context),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  _subtitle(session, timeLabel),
                  style: TextStyle(
                      fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
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
                MangoFormatters.currency(session.total),
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              if (session.paymentMethodCode != null)
                Text(
                  _methodLabel(session.paymentMethodCode!),
                  style: TextStyle(
                      fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context)),
                )
              else if (isOpen)
                Container(
                  margin: EdgeInsets.only(top: dpi.space(2)),
                  padding: EdgeInsets.symmetric(horizontal: dpi.space(6), vertical: dpi.space(2)),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(20)),
                  ),
                  child: Text(
                    'Abierta',
                    style: TextStyle(
                      fontSize: dpi.font(9),
                      fontWeight: FontWeight.w700,
                      color: MangoThemeFactory.warning,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(PersonSession s, String timeLabel) {
    final parts = <String>[timeLabel];
    if (s.customerName != null && s.customerName!.trim().isNotEmpty) {
      parts.add(s.customerName!);
    }
    if (s.peopleCount != null && s.peopleCount! > 0) {
      parts.add('${s.peopleCount} ${s.peopleCount == 1 ? 'persona' : 'personas'}');
    }
    if (s.origin != null && s.origin!.isNotEmpty && s.origin != 'dine_in') {
      parts.add(_originLabel(s.origin!));
    }
    return parts.join(' · ');
  }

  static String _originLabel(String origin) {
    switch (origin) {
      case 'quick':
        return 'venta rápida';
      case 'manual':
        return 'venta manual';
      case 'delivery':
        return 'delivery';
      case 'self_service':
        return 'autoservicio';
      default:
        return origin;
    }
  }

  static String _methodLabel(String code) {
    switch (code) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      default:
        return code;
    }
  }

  static String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month} $h:$m';
  }
}
