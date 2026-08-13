import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../theme/theme_data_factory.dart';

/// Resultado de un escaneo procesado por la pantalla de recepción.
class ScanFeedback {
  const ScanFeedback({required this.matched, required this.message});

  final bool matched;

  /// Ej. "Arroz 25lb · 21 de 24" o "Código no está en esta orden".
  final String message;
}

/// Escáner continuo con cámara para la recepción (PRD 6.1 F4): cada lectura
/// válida suma 1 a la línea correspondiente. El matching lo hace el caller
/// vía [onCode]; esta pantalla solo captura, evita lecturas duplicadas
/// seguidas y muestra el feedback flotante.
class ReceptionScannerPage extends StatefulWidget {
  const ReceptionScannerPage({super.key, this.onCode, this.captureOnce = false})
      : assert(captureOnce || onCode != null,
            'onCode es requerido salvo en modo captureOnce');

  /// Recibe el código leído; devuelve el feedback a mostrar (o null para
  /// ignorar la lectura en silencio). Ignorado en modo [captureOnce].
  final ScanFeedback? Function(String code)? onCode;

  /// Modo captura: la primera lectura cierra la pantalla devolviendo el
  /// código crudo (`Navigator.pop(code)`) — para llenar campos de formulario.
  final bool captureOnce;

  @override
  State<ReceptionScannerPage> createState() => _ReceptionScannerPageState();
}

class _ReceptionScannerPageState extends State<ReceptionScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );

  ScanFeedback? _lastFeedback;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _scanCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue?.trim()
        : null;
    if (raw == null || raw.isEmpty) return;

    // Modo captura: primera lectura → cerrar devolviendo el código.
    if (widget.captureOnce) {
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(raw);
      return;
    }

    // Anti-rebote: la cámara lee el mismo código muchas veces por segundo.
    final now = DateTime.now();
    if (raw == _lastCode &&
        now.difference(_lastAt) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastCode = raw;
    _lastAt = now;

    final feedback = widget.onCode!(raw);
    if (feedback == null) return;
    if (feedback.matched) {
      HapticFeedback.mediumImpact();
      _scanCount++;
    } else {
      HapticFeedback.vibrate();
    }
    setState(() => _lastFeedback = feedback);
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final fb = _lastFeedback;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_scanCount == 0
            ? 'Escanear productos'
            : '$_scanCount escaneo(s)'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Cambiar cámara',
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Marco guía
          Center(
            child: Container(
              width: dpi.scale(260),
              height: dpi.scale(160),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(dpi.radius(16)),
              ),
            ),
          ),
          // Feedback de la última lectura
          if (fb != null)
            Positioned(
              left: dpi.space(16),
              right: dpi.space(16),
              bottom: dpi.space(96),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: dpi.space(14), vertical: dpi.space(12)),
                decoration: BoxDecoration(
                  color: (fb.matched
                          ? MangoThemeFactory.success
                          : MangoThemeFactory.danger)
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(dpi.radius(14)),
                ),
                child: Row(
                  children: [
                    Icon(
                      fb.matched
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: Colors.white,
                      size: dpi.icon(20),
                    ),
                    SizedBox(width: dpi.space(10)),
                    Expanded(
                      child: Text(
                        fb.message,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dpi.font(13.5),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // CTA de cierre
          Positioned(
            left: dpi.space(16),
            right: dpi.space(16),
            bottom: dpi.space(24),
            child: SafeArea(
              top: false,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: MangoThemeFactory.mango,
                  padding: EdgeInsets.symmetric(vertical: dpi.space(14)),
                ),
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('Terminar escaneo'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
