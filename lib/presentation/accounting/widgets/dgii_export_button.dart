import 'package:flutter/material.dart';

/// Acción de exportar de las pantallas de formatos DGII. Igual que
/// `ExportMenuButton`, pero con la opción que de verdad importa acá: el **TXT
/// del prevalidador**, que es el archivo que se sube a la Oficina Virtual. El
/// CSV y el PDF quedan para revisar y para el contador.
class DgiiExportButton extends StatelessWidget {
  const DgiiExportButton({
    super.key,
    required this.onExportTxt,
    required this.onExportCsv,
    required this.onExportPdf,
    this.txtEnabled = true,
    this.enabled = true,
    this.txtDisabledReason,
  });

  final Future<void> Function() onExportTxt;
  final Future<void> Function() onExportCsv;
  final Future<void> Function() onExportPdf;

  /// El TXT se deshabilita cuando falta algo obligatorio para el envío
  /// (típicamente el RNC del negocio), pero el CSV/PDF siguen sirviendo.
  final bool txtEnabled;

  final bool enabled;

  /// Se muestra en un SnackBar si el usuario toca el TXT deshabilitado.
  final String? txtDisabledReason;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.ios_share_rounded),
      tooltip: 'Exportar',
      enabled: enabled,
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        if (value == 'txt' && !txtEnabled) {
          messenger.showSnackBar(SnackBar(
            content: Text(txtDisabledReason ??
                'Falta información obligatoria para generar el archivo.'),
          ));
          return;
        }
        final navigator = Navigator.of(context, rootNavigator: true);
        // Aviso mientras se arma el archivo (y candado contra el doble toque).
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
        try {
          switch (value) {
            case 'txt':
              await onExportTxt();
            case 'csv':
              await onExportCsv();
            case 'pdf':
              await onExportPdf();
          }
        } catch (_) {
          messenger.showSnackBar(const SnackBar(
            content: Text('No se pudo generar el archivo para exportar.'),
          ));
        } finally {
          navigator.pop();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'txt',
          enabled: txtEnabled,
          child: const Row(children: [
            Icon(Icons.description_rounded, size: 18),
            SizedBox(width: 10),
            Text('Archivo para la DGII (.txt)'),
          ]),
        ),
        const PopupMenuItem(
          value: 'csv',
          child: Row(children: [
            Icon(Icons.table_chart_rounded, size: 18),
            SizedBox(width: 10),
            Text('Exportar CSV'),
          ]),
        ),
        const PopupMenuItem(
          value: 'pdf',
          child: Row(children: [
            Icon(Icons.picture_as_pdf_rounded, size: 18),
            SizedBox(width: 10),
            Text('Exportar PDF'),
          ]),
        ),
      ],
    );
  }
}
