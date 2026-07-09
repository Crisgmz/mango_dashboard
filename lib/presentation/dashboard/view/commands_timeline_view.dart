import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/dashboard/dashboard_models.dart';
import '../../theme/theme_data_factory.dart';

/// Timeline view of every payment ("comanda") in the period, grouped by
/// hour-of-day buckets. Each ticket is tappable to lazy-load and reveal the
/// products that were sold in that order.
class CommandsTimelineView extends ConsumerStatefulWidget {
  const CommandsTimelineView({
    super.key,
    required this.tickets,
    required this.totalSales,
    this.periodLabel,
  });

  final List<TicketItem> tickets;
  final double totalSales;
  final String? periodLabel;

  @override
  ConsumerState<CommandsTimelineView> createState() => _CommandsTimelineViewState();
}

class _CommandsTimelineViewState extends ConsumerState<CommandsTimelineView> {
  String _methodFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    final filtered = _methodFilter == 'all'
        ? widget.tickets
        : widget.tickets.where((t) => t.paymentMethodCode == _methodFilter).toList();

    // Group by hour-of-day bucket, descending (latest first).
    final buckets = <int, List<TicketItem>>{};
    for (final t in filtered) {
      final hour = t.createdAt.toLocal().hour;
      buckets.putIfAbsent(hour, () => []).add(t);
    }
    final orderedHours = buckets.keys.toList()..sort((a, b) => b.compareTo(a));

    final filteredTotal = filtered.fold<double>(0, (s, t) => s + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comandas'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          _Header(
            count: filtered.length,
            total: filteredTotal,
            periodLabel: widget.periodLabel,
          ),
          _MethodFilter(
            selected: _methodFilter,
            onChanged: (v) => setState(() => _methodFilter = v),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No hay comandas en este periodo.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(8), dpi.space(16),
                        dpi.space(16) + MediaQuery.of(context).padding.bottom),
                    itemCount: orderedHours.length,
                    itemBuilder: (context, index) {
                      final hour = orderedHours[index];
                      final group = buckets[hour]!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                      return _HourBlock(hour: hour, tickets: group);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.total, this.periodLabel});
  final int count;
  final double total;
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16), dpi.space(8)),
      padding: EdgeInsets.all(dpi.space(18)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [MangoThemeFactory.mango, MangoThemeFactory.mango.withValues(alpha: 0.78)],
        ),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodLabel == null ? 'Total' : 'Total · $periodLabel',
                  style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
                ),
                SizedBox(height: dpi.space(2)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    MangoFormatters.currency(total),
                    style: TextStyle(color: Colors.white, fontSize: dpi.font(24), fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: dpi.space(12)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(color: Colors.white, fontSize: dpi.font(22), fontWeight: FontWeight.w800),
              ),
              Text(
                count == 1 ? 'comanda' : 'comandas',
                style: TextStyle(color: Colors.white70, fontSize: dpi.font(11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodFilter extends StatelessWidget {
  const _MethodFilter({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final options = [
      ('all', 'Todos'),
      ('cash', 'Efectivo'),
      ('card', 'Tarjeta'),
      ('transfer', 'Transferencia'),
    ];
    return SizedBox(
      height: dpi.scale(42),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: dpi.space(16)),
        children: [
          for (final opt in options) ...[
            ChoiceChip(
              label: Text(opt.$2),
              selected: selected == opt.$1,
              onSelected: (_) => onChanged(opt.$1),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selectedColor: MangoThemeFactory.mango.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: selected == opt.$1 ? MangoThemeFactory.mango : null,
                fontWeight: selected == opt.$1 ? FontWeight.w700 : FontWeight.w600,
                fontSize: dpi.font(12),
              ),
            ),
            SizedBox(width: dpi.space(8)),
          ],
        ],
      ),
    );
  }
}

class _HourBlock extends StatelessWidget {
  const _HourBlock({required this.hour, required this.tickets});
  final int hour;
  final List<TicketItem> tickets;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final hourLabel = '${hour.toString().padLeft(2, '0')}:00';
    final nextHour = '${((hour + 1) % 24).toString().padLeft(2, '0')}:00';
    final blockTotal = tickets.fold<double>(0, (s, t) => s + t.amount);

    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: dpi.space(8)),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: dpi.space(10), vertical: dpi.space(4)),
                  decoration: BoxDecoration(
                    color: MangoThemeFactory.mango.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(8)),
                  ),
                  child: Text(
                    '$hourLabel – $nextHour',
                    style: TextStyle(
                      fontSize: dpi.font(12),
                      fontWeight: FontWeight.w800,
                      color: MangoThemeFactory.mango,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${tickets.length} · ${MangoFormatters.currency(blockTotal)}',
                  style: TextStyle(
                    fontSize: dpi.font(11),
                    fontWeight: FontWeight.w700,
                    color: MangoThemeFactory.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          for (final t in tickets)
            Padding(
              padding: EdgeInsets.only(bottom: dpi.space(8)),
              child: _ComandaTile(ticket: t),
            ),
        ],
      ),
    );
  }
}

class _ComandaTile extends ConsumerStatefulWidget {
  const _ComandaTile({required this.ticket});
  final TicketItem ticket;

  @override
  ConsumerState<_ComandaTile> createState() => _ComandaTileState();
}

class _ComandaTileState extends ConsumerState<_ComandaTile> {
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

  bool _expanded = false;
  Future<List<LiveChildItem>>? _itemsFuture;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      // Lazy: only fire the query the first time the user expands.
      _itemsFuture ??= ref
          .read(dashboardDataServiceProvider)
          .loadItemsForOrder(widget.ticket.orderId,
              checkId: widget.ticket.checkId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final ticket = widget.ticket;
    final time = ticket.createdAt.toLocal();
    final hour =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final pmCode = ticket.paymentMethodCode;
    final pmColor = _methodColors[pmCode] ?? MangoThemeFactory.mutedText(context);
    final pmIcon = _methodIcons[pmCode] ?? Icons.receipt_rounded;
    final pmLabel = _methodLabels[pmCode] ?? 'Otro';

    return InkWell(
      onTap: ticket.orderId.isEmpty ? null : _toggle,
      borderRadius: BorderRadius.circular(dpi.radius(14)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(dpi.space(14)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.cardColor(context),
          borderRadius: BorderRadius.circular(dpi.radius(14)),
          border: Border.all(
            color: _expanded
                ? pmColor.withValues(alpha: 0.5)
                : MangoThemeFactory.borderColor(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: dpi.scale(36),
                  height: dpi.scale(36),
                  decoration: BoxDecoration(
                    color: pmColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Icon(pmIcon, color: pmColor, size: dpi.icon(18)),
                ),
                SizedBox(width: dpi.space(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            hour,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(width: dpi.space(8)),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: dpi.space(6), vertical: dpi.space(2)),
                            decoration: BoxDecoration(
                              color: pmColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(dpi.radius(4)),
                            ),
                            child: Text(
                              pmLabel,
                              style: TextStyle(
                                fontSize: dpi.font(9),
                                fontWeight: FontWeight.w800,
                                color: pmColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (ticket.orderId.isNotEmpty) ...[
                        SizedBox(height: dpi.space(2)),
                        Text(
                          '#${_short(ticket.orderId)}',
                          style: TextStyle(
                            fontSize: dpi.font(10),
                            color: MangoThemeFactory.mutedText(context),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: dpi.space(8)),
                Text(
                  MangoFormatters.currency(ticket.amount),
                  style: TextStyle(
                    fontSize: dpi.font(15),
                    fontWeight: FontWeight.w800,
                    color: MangoThemeFactory.textColor(context),
                  ),
                ),
                if (ticket.orderId.isNotEmpty) ...[
                  SizedBox(width: dpi.space(4)),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: dpi.icon(18),
                      color: MangoThemeFactory.mutedText(context),
                    ),
                  ),
                ],
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topLeft,
              child: !_expanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: EdgeInsets.only(top: dpi.space(12)),
                      child: FutureBuilder<List<LiveChildItem>>(
                        future: _itemsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return Text(
                              'No se pudieron cargar los productos.',
                              style: TextStyle(
                                fontSize: dpi.font(11),
                                color: MangoThemeFactory.danger,
                              ),
                            );
                          }
                          final items = snapshot.data ?? const <LiveChildItem>[];
                          if (items.isEmpty) {
                            return Text(
                              'Sin productos registrados en esta orden.',
                              style: TextStyle(
                                fontSize: dpi.font(11),
                                color: MangoThemeFactory.mutedText(context),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(
                                  height: 1,
                                  color: MangoThemeFactory.borderColor(context)),
                              SizedBox(height: dpi.space(8)),
                              ...items.map((it) => Padding(
                                    padding: EdgeInsets.only(bottom: dpi.space(8)),
                                    child: _ItemRow(item: it),
                                  )),
                            ],
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(String id) {
    if (id.length <= 8) return id;
    return id.substring(0, 8);
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final LiveChildItem item;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: dpi.scale(26),
          height: dpi.scale(26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MangoThemeFactory.mango.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            item.quantity.toStringAsFixed(0),
            style: TextStyle(
                fontSize: dpi.font(11),
                fontWeight: FontWeight.bold,
                color: MangoThemeFactory.mango),
          ),
        ),
        SizedBox(width: dpi.space(10)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.extras.isNotEmpty) ...[
                SizedBox(height: dpi.space(2)),
                Text(
                  item.extras.join(' · '),
                  style: TextStyle(
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
          MangoFormatters.currency(item.total),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: dpi.font(12)),
        ),
      ],
    );
  }
}
