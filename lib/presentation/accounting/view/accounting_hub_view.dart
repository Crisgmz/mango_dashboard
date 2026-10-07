import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/accounting/dgii_reports.dart';
import '../../dashboard/view/fiscal_view.dart';
import '../../dashboard/viewmodel/dashboard_data_view_model.dart';
import '../../dashboard/widgets/growth_chip.dart';
import '../../theme/theme_data_factory.dart';
import 'dgii_606_view.dart';
import 'dgii_607_view.dart';
import 'dgii_608_view.dart';
import 'ecf_request_view.dart';

/// Hub de **Contabilidad**: reúne todo lo fiscal del negocio en un solo lugar
/// —la facturación electrónica y los tres formatos de envío de la DGII— en vez
/// de tenerlo repartido entre Reportes y los ajustes de la POS.
///
/// El reporte de comprobantes (NCF / e-CF) sigue viviendo en Reportes; acá se
/// enlaza porque es el que cuadra contra el 607.
class AccountingHubView extends ConsumerWidget {
  const AccountingHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpi = DpiScale.of(context);
    // El período a declarar es siempre el mes cerrado anterior: es lo que
    // vence el 20 de este mes.
    final lastClosedMonth = DgiiPeriod.of(DateTime.now()).previous;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contabilidad'),
        centerTitle: false,
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(dpi.space(16), dpi.space(16), dpi.space(16),
            dpi.space(24) + MediaQuery.of(context).padding.bottom),
        children: [
          _AccountingTile(
            icon: Icons.verified_outlined,
            accent: MangoThemeFactory.mango,
            title: 'Facturación electrónica',
            subtitle: 'Solicitar el e-CF y seguir la certificación ante la DGII',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EcfRequestView()),
            ),
          ),
          SizedBox(height: dpi.space(16)),
          _SectionLabel(
            label: 'ENVÍOS A LA DGII',
            hint: 'Período a declarar: ${lastClosedMonth.label} · '
                'vence el 20 de ${DgiiPeriod.of(DateTime.now()).label}',
          ),
          _AccountingTile(
            icon: Icons.shopping_bag_outlined,
            accent: MangoThemeFactory.payTransfer,
            title: 'Formato 606',
            subtitle: 'Compras de bienes y servicios · recepciones con NCF',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Dgii606View()),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          _AccountingTile(
            icon: Icons.receipt_long_rounded,
            accent: MangoThemeFactory.info,
            title: 'Formato 607',
            subtitle: 'Ventas de bienes y servicios · comprobantes emitidos',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Dgii607View()),
            ),
          ),
          SizedBox(height: dpi.space(10)),
          _AccountingTile(
            icon: Icons.block_rounded,
            accent: MangoThemeFactory.danger,
            title: 'Formato 608',
            subtitle: 'Comprobantes anulados del período',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Dgii608View()),
            ),
          ),
          SizedBox(height: dpi.space(16)),
          _SectionLabel(
            label: 'CONTROL FISCAL',
            hint: 'Para cuadrar antes de enviar',
          ),
          const _FiscalReportTile(),
          SizedBox(height: dpi.space(16)),
          Container(
            padding: EdgeInsets.all(dpi.space(14)),
            decoration: BoxDecoration(
              color: MangoThemeFactory.altSurface(context),
              borderRadius: BorderRadius.circular(dpi.radius(14)),
              border: Border.all(color: MangoThemeFactory.borderColor(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    size: dpi.icon(18), color: MangoThemeFactory.warning),
                SizedBox(width: dpi.space(10)),
                Expanded(
                  child: Text(
                    'Cada formato se exporta como .txt para subirlo al '
                    'prevalidador de la DGII, y como CSV o PDF para revisarlo '
                    'con tu contador. El RNC del negocio sale de la '
                    'configuración fiscal de la POS.',
                    style: TextStyle(fontSize: dpi.font(12), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El reporte de comprobantes necesita el período que el dashboard tiene
/// cargado, igual que cuando se entra desde Reportes.
class _FiscalReportTile extends ConsumerWidget {
  const _FiscalReportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(salesDataViewModelProvider).summary;
    return _AccountingTile(
      icon: Icons.assured_workload_rounded,
      accent: MangoThemeFactory.success,
      title: 'Comprobantes fiscales (NCF / e-CF)',
      subtitle: 'NCF por tipo, impuestos recaudados y anulados del período',
      onTap: summary == null
          ? null
          : () {
              final start = summary.periodStart ??
                  DateTime.now().subtract(const Duration(days: 30));
              final end = summary.periodEnd ?? DateTime.now();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FiscalView(
                  start: start,
                  end: end,
                  periodLabel: periodLabelFor(summary.filter),
                ),
              ));
            },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: dpi.space(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: dpi.font(11.5),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: MangoThemeFactory.mutedText(context),
            ),
          ),
          if (hint != null) ...[
            SizedBox(height: dpi.space(2)),
            Text(
              hint!,
              style: TextStyle(
                fontSize: dpi.font(11),
                color: MangoThemeFactory.mutedText(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountingTile extends StatelessWidget {
  const _AccountingTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(16)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(dpi.radius(16)),
          child: Padding(
            padding: EdgeInsets.all(dpi.space(16)),
            child: Row(
              children: [
                Container(
                  width: dpi.scale(40),
                  height: dpi.scale(40),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(dpi.radius(10)),
                  ),
                  child: Icon(icon, color: accent, size: dpi.icon(22)),
                ),
                SizedBox(width: dpi.space(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: dpi.space(2)),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: dpi.font(11),
                          color: MangoThemeFactory.mutedText(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  onTap == null
                      ? Icons.hourglass_empty_rounded
                      : Icons.chevron_right_rounded,
                  color: MangoThemeFactory.mutedText(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
