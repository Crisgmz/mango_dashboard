import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../theme/theme_data_factory.dart';
import '../viewmodel/auth_gate_view_model.dart';

/// Pantalla mostrada cuando hay sesión activa pero la cuenta tiene
/// biometría exigida (auto-lock al abrir o volver del fondo).
class LockedView extends ConsumerStatefulWidget {
  const LockedView({super.key, required this.userName});

  final String userName;

  @override
  ConsumerState<LockedView> createState() => _LockedViewState();
}

class _LockedViewState extends ConsumerState<LockedView> {
  bool _busy = false;
  String? _error;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    // Dispara el prompt automáticamente al primer build — el usuario no
    // tiene que tocar nada para que aparezca Face ID.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_autoTried) {
        _autoTried = true;
        _tryUnlock();
      }
    });
  }

  Future<void> _tryUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(authGateViewModelProvider.notifier).unlock();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _signOut() async {
    await ref.read(authGateViewModelProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final label = ref.watch(biometricLabelProvider).asData?.value ?? 'Biometría';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(dpi.space(28)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: dpi.scale(84),
                    height: dpi.scale(84),
                    decoration: BoxDecoration(
                      color: MangoThemeFactory.mango.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: dpi.icon(40),
                      color: MangoThemeFactory.mango,
                    ),
                  ),
                  SizedBox(height: dpi.space(20)),
                  Text(
                    'Hola, ${widget.userName}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: dpi.space(6)),
                  Text(
                    'Confirma tu identidad con $label para continuar.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: MangoThemeFactory.mutedText(context),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    SizedBox(height: dpi.space(18)),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(dpi.space(12)),
                      decoration: BoxDecoration(
                        color: MangoThemeFactory.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(dpi.radius(10)),
                        border: Border.all(
                          color: MangoThemeFactory.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _humanizeError(_error!),
                        style: TextStyle(
                          color: MangoThemeFactory.danger,
                          fontSize: dpi.font(12),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  SizedBox(height: dpi.space(28)),
                  SizedBox(
                    width: double.infinity,
                    height: dpi.scale(48),
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _tryUnlock,
                      style: FilledButton.styleFrom(
                        backgroundColor: MangoThemeFactory.mango,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(dpi.radius(12)),
                        ),
                      ),
                      icon: _busy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            )
                          : Icon(
                              label.toLowerCase().contains('face')
                                  ? Icons.face_rounded
                                  : Icons.fingerprint_rounded,
                            ),
                      label: Text(
                        _busy ? 'Verificando…' : 'Desbloquear con $label',
                        style: TextStyle(
                          fontSize: dpi.font(15),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: dpi.space(12)),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        color: MangoThemeFactory.mutedText(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _humanizeError(String code) {
    switch (code) {
      case 'BIO_LOCKED':
        return 'Biometría bloqueada por el sistema. Desbloquéala con tu código en Ajustes y vuelve a intentar.';
      case 'BIO_MISSING':
        return 'No hay biometría enrolada. Cierra sesión e ingresa con tu contraseña.';
      case 'BIO_FAILED':
        return 'No pudimos verificar tu identidad. Inténtalo de nuevo.';
      default:
        return 'No se pudo desbloquear. Inténtalo de nuevo.';
    }
  }
}
