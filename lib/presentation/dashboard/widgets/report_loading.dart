import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/formatters/mango_formatters.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../data/dashboard/report_load.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/report_load_controller.dart';

/// Cuerpo de un reporte con carga progresiva:
///  * primera carga: barra de avance + esqueleto de cards blandas;
///  * cambio de periodo: lo anterior se queda atenuado mientras llega lo nuevo;
///  * refresco en segundo plano: solo la barra fina arriba;
///  * error: mensaje con Reintentar (o un aviso arriba si hay datos válidos).
///
/// [builder] solo corre cuando hay datos; los estados vacíos siguen siendo
/// cosa de cada reporte. Necesita alto acotado (dentro de un Expanded o como
/// body del Scaffold).
class ReportBody<T> extends StatelessWidget {
  const ReportBody({
    super.key,
    required this.controller,
    required this.builder,
    this.skeleton,
    this.errorMessage = 'No se pudo cargar el reporte.',
  });

  final ReportLoadController<T> controller;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? skeleton;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final failed = controller.error != null;
        // Si falla el periodo nuevo, lo viejo no se deja en pantalla como si
        // fuera la respuesta.
        final showData = controller.hasData && !(failed && controller.isStale);

        final String phase;
        final Widget content;
        if (showData) {
          phase = 'data';
          content = AnimatedOpacity(
            opacity: controller.isStale ? 0.4 : 1,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: controller.isStale,
              child: builder(context, controller.data as T),
            ),
          );
        } else if (failed) {
          phase = 'error';
          content = ReportErrorState(
            message: errorMessage,
            onRetry: controller.retry,
          );
        } else {
          phase = 'skeleton';
          content = skeleton ?? const ReportSkeleton();
        }

        return Column(
          children: [
            ReportLoadingStrip(controller: controller),
            if (showData && failed)
              _RefreshFailedBanner(onRetry: controller.retry),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(key: ValueKey(phase), child: content),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Atenúa lo que está fuera de [ReportBody] (el encabezado con totales)
/// mientras sus cifras no corresponden al periodo elegido.
class ReportStaleFade extends StatelessWidget {
  const ReportStaleFade({
    super.key,
    required this.controller,
    required this.child,
  });

  final ReportLoadController<Object?> controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => AnimatedOpacity(
        opacity: controller.isStale || controller.isFirstLoad ? 0.45 : 1,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
      child: child,
    );
  }
}

/// Barra fina de avance. El total no se conoce, así que avanza con cada
/// página o lote terminado (rápido al principio, cada vez más lento) y se
/// completa al llegar el resultado. Se pliega sola al terminar.
class ReportLoadingStrip extends StatefulWidget {
  const ReportLoadingStrip({super.key, required this.controller});

  final ReportLoadController<Object?> controller;

  @override
  State<ReportLoadingStrip> createState() => _ReportLoadingStripState();
}

class _ReportLoadingStripState extends State<ReportLoadingStrip> {
  static const _holdAfterDone = Duration(milliseconds: 450);

  bool _visible = false;
  bool _completing = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _visible = widget.controller.isLoading;
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant ReportLoadingStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final loading = widget.controller.isLoading;
    if (loading) {
      _hideTimer?.cancel();
      if (!_visible || _completing) {
        setState(() {
          _visible = true;
          _completing = false;
        });
      }
      return;
    }
    if (_visible && !_completing) {
      // Se deja ver la barra llena un instante antes de plegarla.
      setState(() => _completing = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(_holdAfterDone, () {
        if (!mounted) return;
        setState(() {
          _visible = false;
          _completing = false;
        });
      });
    }
  }

  /// 8% de entrada y hacia el 95% a medida que terminan peticiones.
  double _fraction(ReportLoadProgress p) =>
      0.08 + 0.87 * (1 - math.exp(-p.requests / 5));

  String _caption() {
    final c = widget.controller;
    if (_completing) return 'Listo';
    if (c.isFirstLoad) return 'Cargando reporte…';
    if (c.isStale) return 'Cargando el periodo elegido…';
    return 'Actualizando en segundo plano…';
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final muted = MangoThemeFactory.mutedText(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !_visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.fromLTRB(
                  dpi.space(16), 0, dpi.space(16), dpi.space(10)),
              child: ValueListenableBuilder<ReportLoadProgress>(
                valueListenable: widget.controller.progress,
                builder: (context, progress, _) {
                  final target = _completing ? 1.0 : _fraction(progress);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: target),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => ClipRRect(
                          borderRadius:
                              BorderRadius.circular(dpi.radius(99)),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: dpi.scale(4),
                            color: MangoThemeFactory.mango,
                            backgroundColor:
                                MangoThemeFactory.altSurface(context),
                          ),
                        ),
                      ),
                      SizedBox(height: dpi.space(6)),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _caption(),
                              style: TextStyle(
                                fontSize: dpi.font(11.5),
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                          ),
                          if (progress.rows > 0)
                            Text(
                              '${MangoFormatters.number(progress.rows)} '
                              '${progress.rows == 1 ? 'registro' : 'registros'}',
                              style: TextStyle(
                                fontSize: dpi.font(11.5),
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

/// Esqueleto con la forma de un reporte: una card de resumen y filas de card
/// blanda, latiendo suave mientras llega el primer resultado.
class ReportSkeleton extends StatefulWidget {
  const ReportSkeleton({super.key, this.rows = 6, this.showSummary = true});

  final int rows;
  final bool showSummary;

  @override
  State<ReportSkeleton> createState() => _ReportSkeletonState();
}

class _ReportSkeletonState extends State<ReportSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final card = MangoThemeFactory.cardColor(context);
    final border = MangoThemeFactory.borderColor(context);
    final bar = MangoThemeFactory.altSurface(context);

    Widget line(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: bar,
            borderRadius: BorderRadius.circular(dpi.radius(6)),
          ),
        );

    Widget softCard({required Widget child}) => Container(
          margin: EdgeInsets.only(bottom: dpi.space(8)),
          padding: EdgeInsets.all(dpi.space(14)),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(dpi.radius(14)),
            border: Border.all(color: border),
          ),
          child: child,
        );

    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.95).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16), 0),
        children: [
          if (widget.showSummary)
            softCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(dpi.scale(90), dpi.scale(10)),
                  SizedBox(height: dpi.space(10)),
                  line(dpi.scale(150), dpi.scale(22)),
                  SizedBox(height: dpi.space(12)),
                  line(double.infinity, dpi.scale(8)),
                ],
              ),
            ),
          for (var i = 0; i < widget.rows; i++)
            softCard(
              child: Row(
                children: [
                  Container(
                    width: dpi.scale(36),
                    height: dpi.scale(36),
                    decoration: BoxDecoration(
                      color: bar,
                      borderRadius: BorderRadius.circular(dpi.radius(10)),
                    ),
                  ),
                  SizedBox(width: dpi.space(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Anchos distintos para que no parezca una tabla vacía.
                        line(dpi.scale(i.isEven ? 140 : 110), dpi.scale(11)),
                        SizedBox(height: dpi.space(7)),
                        line(dpi.scale(i.isEven ? 80 : 100), dpi.scale(9)),
                      ],
                    ),
                  ),
                  SizedBox(width: dpi.space(12)),
                  line(dpi.scale(64), dpi.scale(12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Error sin datos que mostrar.
class ReportErrorState extends StatelessWidget {
  const ReportErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dpi.space(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: dpi.icon(36),
              color: MangoThemeFactory.mutedText(context),
            ),
            SizedBox(height: dpi.space(10)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: dpi.space(4)),
            Text(
              'Revisa la conexión y vuelve a intentarlo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: dpi.space(14)),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: dpi.icon(18)),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// El refresco falló pero lo que hay en pantalla sigue siendo válido.
class _RefreshFailedBanner extends StatelessWidget {
  const _RefreshFailedBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(dpi.space(16), 0, dpi.space(16), dpi.space(8)),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: dpi.space(12), vertical: dpi.space(4)),
        decoration: BoxDecoration(
          color: MangoThemeFactory.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(dpi.radius(12)),
          border: Border.all(
              color: MangoThemeFactory.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: dpi.icon(16), color: MangoThemeFactory.warning),
            SizedBox(width: dpi.space(8)),
            Expanded(
              child: Text(
                'No se pudo actualizar. Lo que ves es la última carga.',
                style: TextStyle(fontSize: dpi.font(12)),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
