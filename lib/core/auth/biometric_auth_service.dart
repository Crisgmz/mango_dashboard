import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

/// Result of a biometric authentication attempt.
enum BiometricResult {
  success,
  failed,
  notAvailable,
  notEnrolled,
  lockedOut,
  cancelled,
  error,
}

/// Wraps `local_auth` to expose simple availability checks and a single
/// `authenticate` method tailored to the Mango Dashboard login flow.
class BiometricAuthService {
  BiometricAuthService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device has biometric hardware AND the OS reports it ready.
  /// Returns false on web/unsupported platforms.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Returns the best label for the chip/button (e.g. "Face ID", "Huella").
  Future<String> primaryBiometricLabel() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      if (available.contains(BiometricType.face)) return 'Face ID';
      if (available.contains(BiometricType.fingerprint)) return 'Huella';
      if (available.contains(BiometricType.iris)) return 'Iris';
      if (available.contains(BiometricType.strong) || available.contains(BiometricType.weak)) {
        return 'Biometría';
      }
      return 'Biometría';
    } on PlatformException {
      return 'Biometría';
    }
  }

  /// Prompts the user with a system biometric dialog. The [reason] is shown
  /// on Android; iOS uses [iosReason] for the localized fallback text.
  Future<BiometricResult> authenticate({
    String reason = 'Confirma tu identidad para continuar',
    String iosReason = 'Confirma tu identidad para iniciar sesión',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
        authMessages: <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Iniciar sesión',
            biometricHint: reason,
            cancelButton: 'Cancelar',
          ),
          IOSAuthMessages(
            lockOut: 'Biometría bloqueada. Desbloquea con tu código de pantalla.',
            cancelButton: 'Cancelar',
            localizedFallbackTitle: 'Usar contraseña',
          ),
        ],
      );
      return ok ? BiometricResult.success : BiometricResult.failed;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'NotAvailable':
          return BiometricResult.notAvailable;
        case 'NotEnrolled':
          return BiometricResult.notEnrolled;
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          return BiometricResult.lockedOut;
        case 'auth_in_progress':
        case 'user_cancel':
          return BiometricResult.cancelled;
        default:
          return BiometricResult.error;
      }
    }
  }
}
