import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/inventory/metrics_models.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';
import '../../theme/theme_data_factory.dart';

/// Métricas de inventario (PRD 6.2, última sección del hub): valor a costo
/// con clasificación ABC, rotación (30 días) y stock envejecido/dormido —
/// sobre las vistas y RPC que ya existían en el backend.
class MetricsView extends ConsumerStatefulWidget {
  const MetricsView({super.key});

  @override
  ConsumerState<MetricsView> createState() => _MetricsViewState();
}

class _MetricsViewState extends ConsumerState<MetricsView> {
  List<ValuationItem> _valuation = const [];
  List<RotationItem> _rotation = const [];
  List<WasteEntry> _waste = const [];
  bool _loading = true;

  String? get _businessId =>
      ref.read(authGateViewModelProvider).profile?.businessId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final businessId = _businessId;
    if (businessId == null) return;
    final service = ref.read(inventoryDataServiceProvider);
    // Cargas independientes: si una falla, la otra pestaña sigue viva.
    try {
      final valuation = await service.loadValuationSummary(businessId);
      if (mounted) setState(() => _valuation = valuation);
    } catch (_) {}
    try {
      final rotation = await service.loadRotationAnalysis(businessId);
      if (mounted) setState(() => _rotation = rotation);
    } catch (_) {}
    try {
      final waste = await service.loadWasteMovements(businessId);
      if (mounted) setState(() => _waste = waste);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  double get _totalValue =>
      _valuation.fold(0.0, (sum, v) => sum + v.totalValue);

  int _abcCount(String cls) =>
      _valuation.where((v) => v.abcClass == cls).length;

  List<RotationItem> get _dormant => _rotation
      .where((r) => r.rotationClass == 'dormant' && r.currentStock > 0)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Métricas'),
          centerTitle: false,
          bottom: const TabBar(
            indicatorColor: MangoThemeFactory.mango,
            labelColor: MangoThemeFactory.mango,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Valor ABC'),
              Tab(text: 'Rotación'),
              Tab(text: 'Envejecido'),
              Tab(text: 'Merma'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Header de valor ──
                  Container(
                    margin: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(14),
                        dpi.space(16), dpi.space(6)),
                    padding: EdgeInsets.all(dpi.space(16)),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        MangoThemeFactory.mango,
                        MangoThemeFactory.mangoDeep,
                      ]),
                      borderRadius: BorderRadius.circular(dpi.radius(18)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('VALOR TOTAL A COSTO',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: dpi.font(9.5),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  )),
                              SizedBox(height: dpi.space(2)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  MangoFormatters.currency(_totalValue),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: dpi.font(22),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final cls in ['A', 'B', 'C']) ...[
                          SizedBox(width: dpi.space(6)),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: dpi.space(9),
                                vertical: dpi.space(6)),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius:
                                  BorderRadius.circular(dpi.radius(10)),
                            ),
                            child: Column(
                              children: [
                                Text(cls,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: dpi.font(12),
                                        fontWeight: FontWeight.w800)),
                                Text('${_abcCount(cls)}',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: dpi.font(10))),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _abcTab(context, dpi),
                        _rotationTab(context, dpi),
                        _dormantTab(context, dpi),
                        _wasteTab(context, dpi),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Color _abcColor(BuildContext context, String? cls) {
    switch (cls) {
      case 'A':
        return MangoThemeFactory.mango;
      case 'B':
        return MangoThemeFactory.info;
      default:
        return MangoThemeFactory.mutedText(context);
    }
  }

  Widget _abcTab(BuildContext context, DpiScale dpi) {
    final withValue =
        _valuation.where((v) => v.totalValue > 0).toList(growable: false);
    if (withValue.isEmpty) {
      return _empty(context, 'Sin stock valorado todavía.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(24)),
        itemCount: withValue.length,
        itemBuilder: (context, index) {
          final v = withValue[index];
          final color = _abcColor(context, v.abcClass);
          final share =
              _totalValue > 0 ? v.totalValue / _totalValue * 100 : 0.0;
          return Container(
            margin: EdgeInsets.only(bottom: dpi.space(6)),
            padding: EdgeInsets.symmetric(
                horizontal: dpi.space(12), vertical: dpi.space(10)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(12)),
              border:
                  Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(28),
                  height: dpi.scale(28),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    v.abcClass ?? '—',
                    style: TextStyle(
                        fontSize: dpi.font(12),
                        fontWeight: FontWeight.w800,
                        color: color),
                  ),
                ),
                SizedBox(width: dpi.space(10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.name,
                          style: TextStyle(
                              fontSize: dpi.font(13),
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${MangoFormatters.number(v.totalQuantity)} ${v.unit} · ${share.toStringAsFixed(1)}% del valor',
                        style: TextStyle(
                            fontSize: dpi.font(10.5),
                            color: MangoThemeFactory.mutedText(context)),
                      ),
                    ],
                  ),
                ),
                Text(
                  MangoFormatters.currency(v.totalValue),
                  style: TextStyle(
                      fontSize: dpi.font(13), fontWeight: FontWeight.w800),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _rotationColor(String cls) {
    switch (cls) {
      case 'star':
        return MangoThemeFactory.success;
      case 'active':
        return MangoThemeFactory.info;
      case 'slow':
        return MangoThemeFactory.warning;
      default:
        return MangoThemeFactory.danger;
    }
  }

  Widget _rotationTab(BuildContext context, DpiScale dpi) {
    final moving = _rotation
        .where((r) => r.rotationClass != 'dormant')
        .toList(growable: false)
      ..sort((a, b) => b.outflowQty.compareTo(a.outflowQty));
    if (moving.isEmpty) {
      return _empty(context,
          'Sin movimientos de salida en los últimos 30 días.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(24)),
        itemCount: moving.length,
        itemBuilder: (context, index) {
          final r = moving[index];
          final color = _rotationColor(r.rotationClass);
          return Container(
            margin: EdgeInsets.only(bottom: dpi.space(6)),
            padding: EdgeInsets.symmetric(
                horizontal: dpi.space(12), vertical: dpi.space(10)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(12)),
              border:
                  Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(r.name,
                                style: TextStyle(
                                    fontSize: dpi.font(13),
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          SizedBox(width: dpi.space(6)),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: dpi.space(6),
                                vertical: dpi.space(1)),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(dpi.radius(5)),
                            ),
                            child: Text(
                              r.classLabel.toUpperCase(),
                              style: TextStyle(
                                  fontSize: dpi.font(8.5),
                                  fontWeight: FontWeight.w800,
                                  color: color),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Salen ${MangoFormatters.number(r.outflowPerDay)} ${r.unit}/día · '
                        'vendido ${MangoFormatters.number(r.outflowQty)} en 30d',
                        style: TextStyle(
                            fontSize: dpi.font(10.5),
                            color: MangoThemeFactory.mutedText(context)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      r.daysOfSupply != null
                          ? '~${r.daysOfSupply!.toStringAsFixed(0)}d'
                          : '—',
                      style: TextStyle(
                        fontSize: dpi.font(14),
                        fontWeight: FontWeight.w800,
                        color: r.daysOfSupply != null && r.daysOfSupply! < 7
                            ? MangoThemeFactory.danger
                            : MangoThemeFactory.textColor(context),
                      ),
                    ),
                    Text('cobertura',
                        style: TextStyle(
                            fontSize: dpi.font(9),
                            color: MangoThemeFactory.mutedText(context))),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dormantTab(BuildContext context, DpiScale dpi) {
    final dormant = _dormant;
    if (dormant.isEmpty) {
      return _empty(context,
          'Nada envejecido: todo tu stock se movió en los últimos 30 días.');
    }
    final valuationById = {for (final v in _valuation) v.itemId: v};
    final frozenValue = dormant.fold<double>(
        0,
        (sum, r) =>
            sum + (valuationById[r.itemId]?.totalValue ?? 0));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(24)),
        children: [
          Container(
            margin: EdgeInsets.only(bottom: dpi.space(10)),
            padding: EdgeInsets.all(dpi.space(12)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.danger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(dpi.radius(12)),
              border: Border.all(
                  color: MangoThemeFactory.danger.withValues(alpha: 0.3)),
            ),
            child: Text(
              '${dormant.length} artículo(s) sin salida en 30 días — '
              '${MangoFormatters.currency(frozenValue)} congelados en tablilla.',
              style: TextStyle(
                fontSize: dpi.font(12.5),
                fontWeight: FontWeight.w700,
                color: MangoThemeFactory.danger,
              ),
            ),
          ),
          ...dormant.map((r) {
            final v = valuationById[r.itemId];
            return Container(
              margin: EdgeInsets.only(bottom: dpi.space(6)),
              padding: EdgeInsets.symmetric(
                  horizontal: dpi.space(12), vertical: dpi.space(10)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.cardColor(context),
                borderRadius: BorderRadius.circular(dpi.radius(12)),
                border:
                    Border.all(color: MangoThemeFactory.borderColor(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name,
                            style: TextStyle(
                                fontSize: dpi.font(13),
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          'Stock: ${MangoFormatters.number(r.currentStock)} ${r.unit}'
                          '${v?.lastMovementAt != null ? ' · último mov. ${MangoFormatters.date(v!.lastMovementAt!)}' : ''}',
                          style: TextStyle(
                              fontSize: dpi.font(10.5),
                              color: MangoThemeFactory.mutedText(context)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    v != null ? MangoFormatters.currency(v.totalValue) : '—',
                    style: TextStyle(
                        fontSize: dpi.font(13),
                        fontWeight: FontWeight.w800,
                        color: MangoThemeFactory.danger),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _wasteColor(String reason) {
    switch (reason) {
      case 'expiration':
        return MangoThemeFactory.danger;
      case 'breakage':
        return MangoThemeFactory.warning;
      case 'theft':
        return MangoThemeFactory.mangoDeep;
      default: // donation
        return MangoThemeFactory.info;
    }
  }

  Widget _wasteTab(BuildContext context, DpiScale dpi) {
    if (_waste.isEmpty) {
      return _empty(context,
          'Sin merma en los últimos 30 días. Los ajustes por rotura, vencimiento, robo o donación aparecen aquí con su costo.');
    }
    final total = _waste.fold<double>(0, (sum, w) => sum + w.value);

    // Totales por motivo, para las chips del resumen.
    final byReason = <String, double>{};
    for (final w in _waste) {
      byReason[w.reasonCode] = (byReason[w.reasonCode] ?? 0) + w.value;
    }
    final reasons = byReason.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    // Agregado por artículo+motivo, ordenado por lo que más duele.
    final grouped = <String, WasteEntry>{};
    for (final w in _waste) {
      final key = '${w.itemId}|${w.reasonCode}';
      final prev = grouped[key];
      grouped[key] = prev == null
          ? w
          : WasteEntry(
              itemId: w.itemId,
              name: w.name,
              unit: w.unit,
              reasonCode: w.reasonCode,
              quantity: prev.quantity + w.quantity,
              value: prev.value + w.value,
              createdAt: prev.createdAt,
            );
    }
    final rows = grouped.values.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(
            dpi.space(16), dpi.space(8), dpi.space(16), dpi.space(24)),
        children: [
          // ── Resumen: total perdido + desglose por motivo ──
          Container(
            margin: EdgeInsets.only(bottom: dpi.space(10)),
            padding: EdgeInsets.all(dpi.space(14)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.cardColor(context),
              borderRadius: BorderRadius.circular(dpi.radius(14)),
              border:
                  Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MERMA ÚLTIMOS 30 DÍAS',
                    style: TextStyle(
                      fontSize: dpi.font(9.5),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: MangoThemeFactory.mutedText(context),
                    )),
                SizedBox(height: dpi.space(2)),
                Text(
                  MangoFormatters.currency(total),
                  style: TextStyle(
                    fontSize: dpi.font(22),
                    fontWeight: FontWeight.w800,
                    color: MangoThemeFactory.danger,
                  ),
                ),
                SizedBox(height: dpi.space(10)),
                Wrap(
                  spacing: dpi.space(6),
                  runSpacing: dpi.space(6),
                  children: [
                    for (final r in reasons)
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: dpi.space(9),
                            vertical: dpi.space(5)),
                        decoration: BoxDecoration(
                          color: _wasteColor(r.key).withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(dpi.radius(8)),
                        ),
                        child: Text(
                          '${WasteEntry.reasonLabel(r.key)} · ${MangoFormatters.currency(r.value)}',
                          style: TextStyle(
                            fontSize: dpi.font(10.5),
                            fontWeight: FontWeight.w700,
                            color: _wasteColor(r.key),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ── Detalle por artículo y motivo ──
          for (final w in rows)
            Container(
              margin: EdgeInsets.only(bottom: dpi.space(6)),
              padding: EdgeInsets.symmetric(
                  horizontal: dpi.space(12), vertical: dpi.space(10)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.cardColor(context),
                borderRadius: BorderRadius.circular(dpi.radius(12)),
                border:
                    Border.all(color: MangoThemeFactory.borderColor(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(w.name,
                                  style: TextStyle(
                                      fontSize: dpi.font(13),
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            SizedBox(width: dpi.space(6)),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: dpi.space(6),
                                  vertical: dpi.space(1)),
                              decoration: BoxDecoration(
                                color: _wasteColor(w.reasonCode)
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(dpi.radius(5)),
                              ),
                              child: Text(
                                WasteEntry.reasonLabel(w.reasonCode)
                                    .toUpperCase(),
                                style: TextStyle(
                                    fontSize: dpi.font(8.5),
                                    fontWeight: FontWeight.w800,
                                    color: _wasteColor(w.reasonCode)),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${MangoFormatters.number(w.quantity)} ${w.unit} perdida(s)',
                          style: TextStyle(
                              fontSize: dpi.font(10.5),
                              color: MangoThemeFactory.mutedText(context)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    MangoFormatters.currency(w.value),
                    style: TextStyle(
                        fontSize: dpi.font(13),
                        fontWeight: FontWeight.w800,
                        color: MangoThemeFactory.danger),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String message) {
    final dpi = DpiScale.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(dpi.space(24)),
      children: [
        SizedBox(height: dpi.space(60)),
        Icon(Icons.query_stats_rounded,
            size: dpi.icon(44),
            color: MangoThemeFactory.mutedText(context).withValues(alpha: 0.5)),
        SizedBox(height: dpi.space(12)),
        Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
