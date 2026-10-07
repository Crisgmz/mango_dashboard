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

/// **Formato 606 — Compras de bienes y servicios.**
///
/// Una fila por recepción de mercancía con NCF del proveedor. Los montos, las
/// retenciones y la forma de pago los capturó la recepción en Compras; lo único
/// que se decide acá es el *tipo de bien o servicio comprado* (columna 3), que
/// es criterio del contador y se recuerda por proveedor.
class Dgii606View extends ConsumerWidget {
  const Dgii606View({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    const format = DgiiFormat.f606;
    final state = ref.watch(dgiiReportViewModelProvider(format));
    final vm = ref.read(dgiiReportViewModelProvider(format).notifier);

    final exportable =
        state.rows606.where((r) => r.isExportable).toList(growable: false);
    final missingNcf = state.rows606.length - exportable.length;
    final totalInvoiced =
        exportable.fold<double>(0, (sum, r) => sum + r.totalInvoiced);
    final totalItbis =
        exportable.fold<double>(0, (sum, r) => sum + r.itbisInvoiced);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formato 606'),
        centerTitle: false,
        actions: [
          DgiiExportButton(
            enabled: !state.loading && state.rows606.isNotEmpty,
            txtEnabled: state.hasRnc && exportable.isNotEmpty,
            txtDisabledReason: state.hasRnc
                ? 'No hay compras con NCF para declarar en este período.'
                : 'Falta el RNC del negocio. Configúralo en la POS '
                    '(Ajustes → Comprobantes fiscales) antes de generar el archivo.',
            onExportTxt: () => _exportTxt(state, exportable),
            onExportCsv: () => _exportCsv(state, exportable),
            onExportPdf: () => _exportPdf(state, exportable),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                dpi.space(16), dpi.space(16), dpi.space(16), 0),
            child: DgiiSummaryHeader(
              formatCode: '606',
              periodLabel: state.period.label,
              recordCount: exportable.length,
              accent: MangoThemeFactory.payTransfer,
              figures: [
                (
                  label: 'Total facturado',
                  value: MangoFormatters.currency(totalInvoiced)
                ),
                (
                  label: 'ITBIS facturado',
                  value: MangoFormatters.currency(totalItbis)
                ),
              ],
              warning: _warningFor(state, missingNcf),
            ),
          ),
          SizedBox(height: dpi.space(12)),
          DgiiPeriodBar(period: state.period, onChanged: vm.setPeriod),
          SizedBox(height: dpi.space(12)),
          Expanded(child: _body(context, state, vm)),
        ],
      ),
    );
  }

  String? _warningFor(DgiiReportState state, int missingNcf) {
    if (!state.hasRnc) {
      return 'Falta el RNC del negocio: sin él no se puede armar la cabecera '
          'del archivo. Se configura en la POS, en Ajustes → Comprobantes '
          'fiscales.';
    }
    if (missingNcf > 0) {
      return missingNcf == 1
          ? '1 recepción del período no tiene NCF y queda fuera del archivo. '
              'Está marcada en la lista.'
          : '$missingNcf recepciones del período no tienen NCF y quedan fuera '
              'del archivo. Están marcadas en la lista.';
    }
    return null;
  }

  Widget _body(
    BuildContext context,
    DgiiReportState state,
    DgiiReportViewModel vm,
  ) {
    final dpi = DpiScale.of(context);
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.unavailable != null) {
      return DgiiEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Compras no disponible',
        message: state.unavailable!,
      );
    }
    if (state.error != null) {
      return DgiiEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'No se pudo cargar',
        message: state.error!,
        isError: true,
      );
    }
    if (state.rows606.isEmpty) {
      return const DgiiEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Sin compras en este período',
        message: 'El 606 se arma con las recepciones de mercancía que tengan el '
            'NCF del proveedor. Regístralas en Inventario → Compras → Recibir '
            'y aparecerán acá.',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
          dpi.space(16) + MediaQuery.of(context).padding.bottom),
      children: [
        DgiiSectionHeader(
          label: 'COMPRAS DEL PERÍODO',
          count: state.rows606.length,
        ),
        for (final row in state.rows606)
          _PurchaseCard(
            row: row,
            expenseType: state.classification.expenseTypeFor(row),
            onExpenseType: (code) => vm.setExpenseType(row, code),
          ),
        SizedBox(height: dpi.space(10)),
        Text(
          'El tipo de bien o servicio (columna 3 del 606) lo eliges tú: se '
          'guarda por proveedor y se reusa el mes siguiente. Las columnas que '
          'el sistema no registra (ITBIS por adelantar, proporcionalidad del '
          'Art. 349, ISR percibido) van vacías en el archivo, como espera el '
          'prevalidador.',
          style: TextStyle(
            fontSize: dpi.font(11.5),
            color: MangoThemeFactory.mutedText(context),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ── Exportación ─────────────────────────────────────────────────────────

  String _filename(DgiiReportState state) =>
      'DGII_606_${state.rnc ?? 'SIN_RNC'}_${state.period.code}';

  Future<void> _exportTxt(DgiiReportState state, List<Dgii606Row> rows) {
    return ReportExportService.exportTxt(
      filename: _filename(state),
      content: DgiiTxtBuilder.build606(
        rnc: state.rnc ?? '',
        period: state.period,
        rows: rows,
        classification: state.classification,
      ),
      subject: '606 · ${state.period.label}',
    );
  }

  static const _headers = [
    'RNC/Cédula',
    'Tipo ID',
    'Tipo bien/servicio',
    'NCF',
    'NCF modificado',
    'Fecha comprobante',
    'Fecha pago',
    'Servicios',
    'Bienes',
    'Total facturado',
    'ITBIS facturado',
    'ITBIS retenido',
    'Retención renta',
    'ISC',
    'Propina legal',
    'Forma de pago',
  ];

  List<List<String>> _tableRows(
      DgiiReportState state, List<Dgii606Row> rows) {
    return [
      for (final r in rows)
        [
          r.taxId ?? '',
          r.idType ?? '',
          state.classification.expenseTypeFor(r),
          r.ncf ?? '',
          r.ncfModified ?? '',
          r.documentDate == null ? '' : MangoFormatters.date(r.documentDate!),
          r.paymentDate == null ? '' : MangoFormatters.date(r.paymentDate!),
          MangoFormatters.amount(r.servicesAmount),
          MangoFormatters.amount(r.goodsAmount),
          MangoFormatters.amount(r.totalInvoiced),
          MangoFormatters.amount(r.itbisInvoiced),
          MangoFormatters.amount(r.itbisWithheld),
          MangoFormatters.amount(r.isrWithheld),
          MangoFormatters.amount(r.isc),
          MangoFormatters.amount(r.legalTip),
          r.paymentForm,
        ],
    ];
  }

  Future<void> _exportCsv(DgiiReportState state, List<Dgii606Row> rows) {
    return ReportExportService.exportCsv(
      filename: _filename(state),
      headers: _headers,
      rows: _tableRows(state, rows),
      subject: '606 · ${state.period.label}',
    );
  }

  Future<void> _exportPdf(DgiiReportState state, List<Dgii606Row> rows) {
    return ReportExportService.exportPdf(
      filename: _filename(state),
      title: 'Formato 606 · Compras de bienes y servicios',
      subtitle: '${state.legalName ?? ''}  RNC ${state.rnc ?? 'sin configurar'}  ·  '
          'Período ${state.period.code}  ·  ${rows.length} registros',
      headers: _headers,
      rows: _tableRows(state, rows),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    required this.row,
    required this.expenseType,
    required this.onExpenseType,
  });

  final Dgii606Row row;
  final String expenseType;
  final ValueChanged<String> onExpenseType;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final idLabel = dgiiCodeOf(kDgiiIdTypes, row.idType)?.label;
    return DgiiRowCard(
      leading: row.supplierName.isEmpty
          ? '?'
          : row.supplierName[0].toUpperCase(),
      accent: MangoThemeFactory.payTransfer,
      flagged: !row.isExportable,
      title: row.supplierName,
      subtitle: [
        row.isExportable ? 'NCF ${row.ncf}' : 'Sin NCF · no se declara',
        if (row.taxId != null) '${idLabel ?? 'ID'} ${row.taxId}',
        if (row.documentDate != null) MangoFormatters.date(row.documentDate!),
      ].join(' · '),
      detail: [
        'Total ${MangoFormatters.currency(row.totalInvoiced)}',
        if (row.itbisInvoiced > 0)
          'ITBIS ${MangoFormatters.amount(row.itbisInvoiced)}',
        if (row.itbisWithheld > 0)
          'ITBIS ret. ${MangoFormatters.amount(row.itbisWithheld)}',
        if (row.isrWithheld > 0)
          'ISR ${MangoFormatters.amount(row.isrWithheld)}',
      ].join(' · '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DgiiCodeChip(
            code: expenseType,
            catalog: kDgiiExpenseTypes,
            onPick: onExpenseType,
          ),
          SizedBox(height: dpi.space(4)),
          SizedBox(
            width: dpi.scale(96),
            child: Text(
              dgiiCodeOf(kDgiiPurchasePaymentForms, row.paymentForm)?.label ?? '',
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dpi.font(9.5),
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
