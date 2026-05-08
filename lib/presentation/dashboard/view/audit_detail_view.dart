import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';

/// Loss-prevention view: lists voided items, cancelled payments, and
/// discounted orders for a period in three tabs.
class AuditDetailView extends ConsumerStatefulWidget {
  const AuditDetailView({
    super.key,
    required this.start,
    required this.end,
    this.periodLabel,
  });

  final DateTime start;
  final DateTime end;
  final String? periodLabel;

  @override
  ConsumerState<AuditDetailView> createState() => _AuditDetailViewState();
}

class _AuditDetailViewState extends ConsumerState<AuditDetailView> {
  late Future<({AuditSummary summary, AuditDetail detail})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({AuditSummary summary, AuditDetail detail})> _load() async {
    final profile = ref.read(authGateViewModelProvider).profile;
    final businessId = profile?.businessId;
    if (businessId == null) {
      return (
        summary: const AuditSummary(),
        detail: const AuditDetail(),
      );
    }
    return ref.read(dashboardDataServiceProvider).loadAuditDetail(
          businessId: businessId,
          start: widget.start,
          end: widget.end,
        );
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Auditoría'),
          centerTitle: false,
          bottom: const TabBar(
            indicatorColor: MangoThemeFactory.mango,
            labelColor: MangoThemeFactory.mango,
            tabs: [
              Tab(icon: Icon(Icons.block_rounded), text: 'Voids'),
              Tab(icon: Icon(Icons.cancel_rounded), text: 'Cancelaciones'),
              Tab(icon: Icon(Icons.discount_rounded), text: 'Descuentos'),
            ],
          ),
        ),
        body: FutureBuilder<({AuditSummary summary, AuditDetail detail})>(
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
                    'No se pudo cargar la auditoría.',
                    style: TextStyle(color: MangoThemeFactory.danger),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final data = snapshot.data;
            final summary = data?.summary ?? const AuditSummary();
            final detail = data?.detail ?? const AuditDetail();

            return Column(
              children: [
                _AuditHeader(summary: summary, periodLabel: widget.periodLabel),
                Expanded(
                  child: TabBarView(
                    children: [
                      _VoidedItemsTab(items: detail.voidedItems),
                      _CancelledPaymentsTab(items: detail.cancelledPayments),
                      _DiscountedOrdersTab(items: detail.discountedOrders),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AuditHeader extends StatelessWidget {
  const _AuditHeader({required this.summary, this.periodLabel});

  final AuditSummary summary;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(8)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.danger, MangoThemeFactory.danger.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: dpi.icon(18)),
              SizedBox(width: dpi.space(6)),
              Text(
                periodLabel == null ? 'Periodo' : 'Auditoría · $periodLabel',
                style: TextStyle(color: Colors.white, fontSize: dpi.font(12), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: dpi.space(10)),
          Text(
            'Pérdida total registrada',
            style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MangoFormatters.currency(summary.totalLoss),
              style: TextStyle(color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Voids',
                  value: '${summary.voidedItemsCount}',
                  amount: MangoFormatters.currency(summary.voidedAmount),
                ),
              ),
              _verticalDivider(dpi),
              Expanded(
                child: _MiniStat(
                  label: 'Cancelaciones',
                  value: '${summary.cancelledPaymentsCount}',
                  amount: MangoFormatters.currency(summary.cancelledAmount),
                ),
              ),
              _verticalDivider(dpi),
              Expanded(
                child: _MiniStat(
                  label: 'Descuentos',
                  value: '${summary.discountsAppliedCount}',
                  amount: MangoFormatters.currency(summary.discountsAmount),
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
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.amount});
  final String label;
  final String value;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dpi.space(4)),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: dpi.font(10))),
          SizedBox(height: dpi.space(2)),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: dpi.font(15),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: dpi.space(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(color: Colors.white70, fontSize: dpi.font(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoidedItemsTab extends StatelessWidget {
  const _VoidedItemsTab({required this.items});
  final List<VoidedItem> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (items.isEmpty) {
      return _EmptyTab(message: 'Sin items anulados en este periodo.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
      itemBuilder: (context, index) => _AuditTile(
        accent: MangoThemeFactory.warning,
        icon: Icons.block_rounded,
        title: items[index].productName,
        amount: items[index].amount,
        subtitleParts: _voidSubtitle(items[index]),
      ),
    );
  }

  static List<String> _voidSubtitle(VoidedItem v) {
    final parts = <String>[];
    parts.add('${v.quantity.toStringAsFixed(0)} ${v.quantity == 1 ? 'unidad' : 'unidades'}');
    if (v.tableLabel != null) parts.add(v.tableLabel!);
    if (v.waiterName != null) parts.add('Mesero: ${v.waiterName}');
    parts.add(_formatTime(v.createdAt));
    return parts;
  }
}

class _CancelledPaymentsTab extends StatelessWidget {
  const _CancelledPaymentsTab({required this.items});
  final List<CancelledPayment> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (items.isEmpty) {
      return _EmptyTab(message: 'Sin pagos cancelados en este periodo.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
      itemBuilder: (context, index) => _AuditTile(
        accent: MangoThemeFactory.danger,
        icon: Icons.cancel_rounded,
        title: items[index].status == 'void' ? 'Pago anulado' : 'Pago cancelado',
        amount: items[index].amount,
        subtitleParts: _cancelSubtitle(items[index]),
      ),
    );
  }

  static List<String> _cancelSubtitle(CancelledPayment p) {
    final parts = <String>[];
    if (p.methodCode != null) parts.add(_methodLabel(p.methodCode!));
    if (p.tableLabel != null) parts.add(p.tableLabel!);
    if (p.cashierName != null) parts.add('Cajero: ${p.cashierName}');
    parts.add(_formatTime(p.createdAt));
    return parts;
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
}

class _DiscountedOrdersTab extends StatelessWidget {
  const _DiscountedOrdersTab({required this.items});
  final List<DiscountedOrder> items;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    if (items.isEmpty) {
      return _EmptyTab(message: 'Sin descuentos aplicados en este periodo.');
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(16) + MediaQuery.of(context).padding.bottom),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: dpi.space(8)),
      itemBuilder: (context, index) {
        final d = items[index];
        return _AuditTile(
          accent: MangoThemeFactory.info,
          icon: Icons.discount_rounded,
          title: d.tableLabel ?? 'Orden',
          amount: d.discount,
          amountSuffix: '(${(d.percent * 100).toStringAsFixed(1)}%)',
          subtitleParts: _discountSubtitle(d),
        );
      },
    );
  }

  static List<String> _discountSubtitle(DiscountedOrder d) {
    final parts = <String>[];
    parts.add('Total ${MangoFormatters.currency(d.total)}');
    if (d.customerName != null && d.customerName!.trim().isNotEmpty) {
      parts.add(d.customerName!);
    }
    if (d.waiterName != null) parts.add('Mesero: ${d.waiterName}');
    parts.add(_formatTime(d.createdAt));
    return parts;
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.amount,
    required this.subtitleParts,
    this.amountSuffix,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final double amount;
  final String? amountSuffix;
  final List<String> subtitleParts;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            width: dpi.scale(38),
            height: dpi.scale(38),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(dpi.radius(10)),
            ),
            child: Icon(icon, color: accent, size: dpi.icon(20)),
          ),
          SizedBox(width: dpi.space(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: dpi.space(2)),
                Text(
                  subtitleParts.join(' · '),
                  style: TextStyle(fontSize: dpi.font(11), color: MangoThemeFactory.mutedText(context)),
                  maxLines: 2,
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
                MangoFormatters.currency(amount),
                style: TextStyle(
                  fontSize: dpi.font(13),
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              if (amountSuffix != null)
                Text(
                  amountSuffix!,
                  style: TextStyle(
                      fontSize: dpi.font(10), color: MangoThemeFactory.mutedText(context)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(40)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: dpi.icon(48), color: MangoThemeFactory.success),
            SizedBox(height: dpi.space(12)),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '${t.day}/${t.month} $h:$m';
}
