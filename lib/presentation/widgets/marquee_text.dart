import 'package:flutter/material.dart';

/// Texto de una línea que, cuando NO cabe en el ancho disponible, se desplaza
/// horizontalmente en vaivén (efecto carrusel): pausa → avanza hasta el final
/// → pausa → regresa. Si cabe, se renderiza como un Text normal y no anima
/// nada. Sin dependencias externas.
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 40,
    this.pause = const Duration(milliseconds: 1400),
  });

  final String text;
  final TextStyle? style;

  /// Píxeles por segundo del desplazamiento.
  final double velocity;

  /// Pausa en cada extremo antes de invertir la dirección.
  final Duration pause;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _running = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loop() async {
    if (_running) return;
    _running = true;
    // Vaivén continuo mientras el widget viva y haya overflow real.
    while (mounted) {
      await Future.delayed(widget.pause);
      if (!mounted || !_controller.hasClients) break;
      final max = _controller.position.maxScrollExtent;
      if (max <= 0) break; // el layout cambió y ahora cabe
      try {
        await _controller.animateTo(
          max,
          duration: Duration(
              milliseconds: (max / widget.velocity * 1000).round().clamp(600, 20000)),
          curve: Curves.linear,
        );
        if (!mounted) break;
        await Future.delayed(widget.pause);
        if (!mounted || !_controller.hasClients) break;
        await _controller.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      } catch (_) {
        break; // controller liberado a mitad de animación
      }
    }
    _running = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Medir: si el texto cabe, no hay carrusel.
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fits = painter.width <= constraints.maxWidth;
        if (fits) {
          return Text(widget.text, style: widget.style, maxLines: 1);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loop();
        });
        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(widget.text, style: widget.style, maxLines: 1),
        );
      },
    );
  }
}
