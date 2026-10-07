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

/// **Formato 608 — Comprobantes anulados.**
///
/// Tres columnas: NCF, fecha del comprobante y tipo de anulación. El tipo lo
/// decide el contador; acá se propone leyendo el motivo que escribió quien
/// anuló en caja, y se puede cambiar antes de exportar.
class Dgii608View extends ConsumerWidget {
  const Dgii608View({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    const format = DgiiFormat.f608;
    final state = ref.watch(dgiiReportViewModelProvider(format));
    final vm = ref.read(dgiiReportViewModelProvider(format).notifier);

    final rows = state.rows608;
    final exportable =
        rows.where((r) => r.ncf.isNotEmpty).toList(growable: false);
    final voidedAmount = rows.fold<double>(0, (sum, r) => sum + r.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formato 608'),
        centerTitle: false,
        actions: [
          DgiiExportButton(
            enabled: !state.loading && rows.isNotEmpty,
            txtEnabled: state.hasRnc && exportable.isNotEmpty,
            txtDisabledReason: state.hasRnc
                ? 'No hay comprobantes anulados para declarar en este período.'
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
              formatCode: '608',
              periodLabel: state.period.label,
              recordCount: exportable.length,
              accent: MangoThemeFactory.danger,
              figures: [
                (
                  label: 'Monto anulado',
                  value: MangoFormatters.currency(voidedAmount)
                ),
              ],
              warning: state.hasRnc
                  ? null
                  : 'Falta el RNC del negocio: sin él no se puede armar la '
                      'cabecera del archivo. Se configura en la POS, en '
                      'Ajustes → Comprobantes fiscales.',
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

  Widget _body(
    BuildContext context,
    DgiiReportState state,
    DgiiReportViewModel vm,
  ) {
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
    if (state.rows608.isEmpty) {
      return const DgiiEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Sin comprobantes anulados',
        message: 'No se anuló ningún comprobante fiscal en este período. El 608 '
            'se envía igual, vacío, si la DGII lo exige para el mes.',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16),
          dpi.space(16) + MediaQuery.of(context).padding.bottom),
      children: [
        DgiiSectionHeader(
          label: 'COMPROBANTES ANULADOS',
          count: state.rows608.length,
        ),
        for (final row in state.rows608)
          _VoidedCard(
            row: row,
            voidReason: state.classification.voidReasonFor(row),
            onVoidReason: (code) => vm.setVoidReason(row, code),
          ),
        SizedBox(height: dpi.space(10)),
        Text(
          'La fecha que se declara es la del comprobante, no la de la '
          'anulación. El tipo de anulación se propone a partir del motivo que '
          'escribió quien anuló; revísalo antes de exportar, porque la DGII '
          'solo acepta los once códigos de su catálogo.',
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
      'DGII_608_${state.rnc ?? 'SIN_RNC'}_${state.period.code}';

  Future<void> _exportTxt(DgiiReportState state, List<Dgii608Row> rows) {
    return ReportExportService.exportTxt(
      filename: _filename(state),
      content: DgiiTxtBuilder.build608(
        rnc: state.rnc ?? '',
        period: state.period,
        rows: rows,
        classification: state.classification,
      ),
      subject: '608 · ${state.period.label}',
    );
  }

  static const _headers = [
    'NCF',
    'Fecha comprobante',
    'Tipo anulación',
    'Descripción',
    'Monto anulado',
    'Anulado el',
    'Motivo registrado',
  ];

  List<List<String>> _tableRows(
      DgiiReportState state, List<Dgii608Row> rows) {
    return [
      for (final r in rows)
        [
          r.ncf,
          MangoFormatters.date(r.documentDate),
          state.classification.voidReasonFor(r),
          dgiiCodeOf(kDgiiVoidReasons, state.classification.voidReasonFor(r))
                  ?.label ??
              '',
          MangoFormatters.amount(r.total),
          r.cancelledAt == null ? '' : MangoFormatters.date(r.cancelledAt!),
          r.reason ?? '',
        ],
    ];
  }

  Future<void> _exportCsv(DgiiReportState state, List<Dgii608Row> rows) {
    return ReportExportService.exportCsv(
      filename: _filename(state),
      headers: _headers,
      rows: _tableRows(state, rows),
      subject: '608 · ${state.period.label}',
    );
  }

  Future<void> _exportPdf(DgiiReportState state, List<Dgii608Row> rows) {
    return ReportExportService.exportPdf(
      filename: _filename(state),
      title: 'Formato 608 · Comprobantes anulados',
      subtitle: '${state.legalName ?? ''}  RNC ${state.rnc ?? 'sin configurar'}  ·  '
          'Período ${state.period.code}  ·  ${rows.length} registros',
      headers: _headers,
      rows: _tableRows(state, rows),
    );
  }
}

class _VoidedCard extends StatelessWidget {
  const _VoidedCard({
    required this.row,
    required this.voidReason,
    required this.onVoidReason,
  });

  final Dgii608Row row;
  final String voidReason;
  final ValueChanged<String> onVoidReason;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return DgiiRowCard(
      leading: row.ncfType,
      accent: MangoThemeFactory.danger,
      flagged: row.ncf.isEmpty,
      title: row.ncf.isEmpty ? 'Comprobante sin NCF' : row.ncf,
      subtitle: [
        MangoFormatters.date(row.documentDate),
        MangoFormatters.currency(row.total),
        if (row.cancelledAt != null)
          'anulado ${MangoFormatters.date(row.cancelledAt!)}',
      ].join(' · '),
      detail: dgiiCodeOf(kDgiiVoidReasons, voidReason)?.label,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          DgiiCodeChip(
            code: voidReason,
            catalog: kDgiiVoidReasons,
            onPick: onVoidReason,
          ),
          if (row.reason != null) ...[
            SizedBox(height: dpi.space(4)),
            SizedBox(
              width: dpi.scale(96),
              child: Text(
                row.reason!,
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
        ],
      ),
    );
  }
}
