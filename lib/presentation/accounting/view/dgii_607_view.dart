import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/accounting/dgii_txt_builder.dart';
import '../../../data/export/report_export_service.dart';
import '../../../domain/accounting/dgii_catalogs.dart';
import '../../../domain/accounting/dgii_reports.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/dgii_report_view_model.dart';
import '../widgets/dgii_export_button.dart';
import '../widgets/dgii_period_bar.dart';
import '../widgets/dgii_shared.dart';

/// **Formato 607 — Ventas de bienes y servicios.**
///
/// Una fila por comprobante emitido en el mes, con el desglose por forma de
/// cobro (efectivo, transferencia, tarjeta, crédito, otras) que la DGII pide en
/// las columnas 17–23.
///
/// A diferencia de los reportes de ventas, este va por **fecha del
/// comprobante** (`issued_at`), no por cierre de la orden: es lo que se declara.
class Dgii607View extends ConsumerWidget {
  const Dgii607View({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    const format = DgiiFormat.f607;
    final state = ref.watch(dgiiReportViewModelProvider(format));
    final vm = ref.read(dgiiReportViewModelProvider(format).notifier);

    final rows = state.rows607;
    final totalInvoiced =
        rows.fold<double>(0, (sum, r) => sum + r.amountInvoiced);
    final totalItbis = rows.fold<double>(0, (sum, r) => sum + r.itbisInvoiced);
    final totalTip = rows.fold<double>(0, (sum, r) => sum + r.legalTip);
    final mismatches = rows.where((r) => r.paymentsMismatch).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formato 607'),
        centerTitle: false,
        actions: [
          DgiiExportButton(
            enabled: !state.loading && rows.isNotEmpty,
            txtEnabled: state.hasRnc && rows.isNotEmpty,
            txtDisabledReason: state.hasRnc
                ? 'No hay comprobantes para declarar en este período.'
                : 'Falta el RNC del negocio. Configúralo en la POS '
                    '(Ajustes → Comprobantes fiscales) antes de generar el archivo.',
            onExportTxt: () => _exportTxt(state),
            onExportCsv: () => _exportCsv(state),
            onExportPdf: () => _exportPdf(state),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                dpi.space(16), dpi.space(16), dpi.space(16), 0),
            child: DgiiSummaryHeader(
              formatCode: '607',
              periodLabel: state.period.label,
              recordCount: rows.length,
              accent: MangoThemeFactory.info,
              figures: [
                (
                  label: 'Monto facturado',
                  value: MangoFormatters.currency(totalInvoiced)
                ),
                (
                  label: 'ITBIS facturado',
                  value: MangoFormatters.currency(totalItbis)
                ),
                if (totalTip > 0)
                  (
                    label: 'Propina legal',
                    value: MangoFormatters.currency(totalTip)
                  ),
              ],
              warning: _warningFor(state, mismatches),
            ),
          ),
          SizedBox(height: dpi.space(12)),
          DgiiPeriodBar(period: state.period, onChanged: vm.setPeriod),
          SizedBox(height: dpi.space(12)),
          Expanded(child: _body(context, state)),
        ],
      ),
    );
  }

  String? _warningFor(DgiiReportState state, int mismatches) {
    if (!state.hasRnc) {
      return 'Falta el RNC del negocio: sin él no se puede armar la cabecera '
          'del archivo. Se configura en la POS, en Ajustes → Comprobantes '
          'fiscales.';
    }
    if (mismatches > 0) {
      return mismatches == 1
          ? '1 comprobante tiene el desglose de cobro descuadrado del total '
              'facturado. Está marcado en la lista.'
          : '$mismatches comprobantes tienen el desglose de cobro descuadrado '
              'del total facturado. Están marcados en la lista.';
    }
    return null;
  }

  Widget _body(BuildContext context, DgiiReportState state) {
    final dpi = DpiScale.of(context);
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return DgiiEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'No se pudo cargar',
        message: state.error!,
        isError: true,
      );
    }
    final rows = state.rows607;
    if (rows.isEmpty) {
      return const DgiiEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Sin comprobantes en este período',
        message: 'El 607 se arma con los comprobantes fiscales emitidos en el '
            'mes. Si el negocio facturó, revisa que la caja esté emitiendo NCF.',
      );
    }

    // Un mes de consumo puede traer miles de comprobantes: la lista se
    // construye por demanda en vez de armar todas las cards de golpe.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
          dpi.space(16) + MediaQuery.of(context).padding.bottom),
      itemCount: rows.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return DgiiSectionHeader(
            label: 'COMPROBANTES EMITIDOS',
            count: rows.length,
          );
        }
        if (index == rows.length + 1) {
          return Padding(
            padding: EdgeInsets.only(top: dpi.space(10)),
            child: Text(
              'El monto facturado va sin ITBIS ni propina legal, como pide la '
              'columna 8. La propina legal se declara aparte (columna 16) y el '
              'desglose de cobro sale de los pagos reales de cada pedido o '
              'división.',
              style: TextStyle(
                fontSize: dpi.font(11.5),
                color: MangoThemeFactory.mutedText(context),
                height: 1.4,
              ),
            ),
          );
        }
        return _SaleCard(row: rows[index - 1]);
      },
    );
  }

  // ── Exportación ─────────────────────────────────────────────────────────

  String _filename(DgiiReportState state) =>
      'DGII_607_${state.rnc ?? 'SIN_RNC'}_${state.period.code}';

  Future<void> _exportTxt(DgiiReportState state) {
    return ReportExportService.exportTxt(
      filename: _filename(state),
      content: DgiiTxtBuilder.build607(
        rnc: state.rnc ?? '',
        period: state.period,
        rows: state.rows607,
      ),
      subject: '607 · ${state.period.label}',
    );
  }

  static const _headers = [
    'RNC/Cédula',
    'Tipo ID',
    'NCF',
    'NCF modificado',
    'Tipo ingreso',
    'Fecha comprobante',
    'Monto facturado',
    'ITBIS facturado',
    'Propina legal',
    'Efectivo',
    'Cheque/Transf.',
    'Tarjeta',
    'Crédito',
    'Otras',
  ];

  List<List<String>> _tableRows(DgiiReportState state) {
    return [
      for (final r in state.rows607)
        [
          r.taxId ?? '',
          r.idType ?? '',
          r.ncf,
          r.ncfModified ?? '',
          kDgiiDefaultIncomeType,
          MangoFormatters.date(r.issuedAt),
          MangoFormatters.amount(r.amountInvoiced),
          MangoFormatters.amount(r.itbisInvoiced),
          MangoFormatters.amount(r.legalTip),
          MangoFormatters.amount(r.cash),
          MangoFormatters.amount(r.transfer),
          MangoFormatters.amount(r.card),
          MangoFormatters.amount(r.credit),
          MangoFormatters.amount(r.other),
        ],
    ];
  }

  Future<void> _exportCsv(DgiiReportState state) {
    return ReportExportService.exportCsv(
      filename: _filename(state),
      headers: _headers,
      rows: _tableRows(state),
      subject: '607 · ${state.period.label}',
    );
  }

  Future<void> _exportPdf(DgiiReportState state) {
    return ReportExportService.exportPdf(
      filename: _filename(state),
      title: 'Formato 607 · Ventas de bienes y servicios',
      subtitle: '${state.legalName ?? ''}  RNC ${state.rnc ?? 'sin configurar'}  ·  '
          'Período ${state.period.code}  ·  ${state.rows607.length} registros',
      headers: _headers,
      rows: _tableRows(state),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.row});

  final Dgii607Row row;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final splits = <String>[
      if (row.cash > 0) 'Efectivo ${MangoFormatters.amount(row.cash)}',
      if (row.transfer > 0) 'Transf. ${MangoFormatters.amount(row.transfer)}',
      if (row.card > 0) 'Tarjeta ${MangoFormatters.amount(row.card)}',
      if (row.credit > 0) 'Crédito ${MangoFormatters.amount(row.credit)}',
      if (row.other > 0) 'Otras ${MangoFormatters.amount(row.other)}',
    ];
    return DgiiRowCard(
      leading: row.ncfType,
      accent: MangoThemeFactory.info,
      flagged: row.paymentsMismatch,
      title: row.ncf.isEmpty ? 'Comprobante sin NCF' : row.ncf,
      subtitle: [
        MangoFormatters.date(row.issuedAt),
        if (row.taxId != null) 'RNC ${row.taxId}',
        if (row.customerName != null && row.customerName!.isNotEmpty)
          row.customerName!,
        if (row.ncfModified != null) 'modifica ${row.ncfModified}',
      ].join(' · '),
      detail: splits.isEmpty
          ? 'Sin cobros registrados para este comprobante'
          : splits.join(' · '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            MangoFormatters.currency(row.amountInvoiced),
            style: TextStyle(
              fontSize: dpi.font(13),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (row.itbisInvoiced > 0)
            Text(
              'ITBIS ${MangoFormatters.amount(row.itbisInvoiced)}',
              style: TextStyle(
                fontSize: dpi.font(10),
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
          if (row.legalTip > 0)
            Text(
              'Propina ${MangoFormatters.amount(row.legalTip)}',
              style: TextStyle(
                fontSize: dpi.font(10),
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
        ],
      ),
    );
  }
}
