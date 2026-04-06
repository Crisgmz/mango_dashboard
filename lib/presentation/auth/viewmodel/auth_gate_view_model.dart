import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/di/providers.dart';
import '../../../domain/auth/admin_access_profile.dart';
import '../../../domain/auth/saved_account.dart';

class AuthGateState {
  const AuthGateState({
    required this.isLoading,
    required this.isAuthenticated,
    required this.profile,
    required this.error,
  });

  const AuthGateState.initial()
    : isLoading = true,
      isAuthenticated = false,
      profile = null,
      error = null;

  final bool isLoading;
  final bool isAuthenticated;
  final AdminAccessProfile? profile;
  final String? error;

  AuthGateState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    AdminAccessProfile? profile,
    String? error,
    bool clearError = false,
  }) {
    return AuthGateState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      profile: profile ?? this.profile,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthGateViewModel extends StateNotifier<AuthGateState> {
  AuthGateViewModel(this._ref) : super(const AuthGateState.initial()) {
    _subscription = _ref.read(adminAccessServiceProvider).authStates().listen((_) {
      bootstrap();
    });
  }

  final Ref _ref;
  StreamSubscription<AuthState>? _subscription;
  int _retryCount = 0;
  static const _maxRetries = 3;

  Future<void> bootstrap() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final service = _ref.read(adminAccessServiceProvider);

    try {
      final user = service.currentUser;
      if (user == null) {
        state = const AuthGateState.initial().copyWith(isLoading: false);
        return;
      }

      final profile = await service.resolveCurrentAccess();
      if (profile != null) {
        // Guardar cuenta automáticamente al resolver acceso
        await _saveCurrentAccount(profile);
      }
      _retryCount = 0;
      state = AuthGateState(
        isLoading: false,
        isAuthenticated: true,
        profile: profile,
        error: profile == null ? 'No se pudo resolver el negocio o rol del usuario.' : null,
      );
    } catch (e) {
      final errorStr = e.toString();

      // Para errores transitorios (500, token HMAC), reintentar una vez antes de cerrar sesión
      if (errorStr.contains('500') || errorStr.contains('refresh_token_hmac_key')) {
        _retryCount++;
        if (_retryCount <= _maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          return bootstrap();
        }
        // Agotados los reintentos, cerrar sesión
        _retryCount = 0;
        final service = _ref.read(adminAccessServiceProvider);
        await service.signOut();
        state = AuthGateState(
          isLoading: false,
          isAuthenticated: false,
          profile: null,
          error: 'Su sesión ha expirado o requiere re-autenticación. Por favor inicie sesión de nuevo.',
        );
        return;
      }

      state = AuthGateState(
        isLoading: false,
        isAuthenticated: false,
        profile: null,
        error: errorStr,
      );
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _ref.read(adminAccessServiceProvider).signIn(email: email, password: password);
      await bootstrap();
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'No se pudo iniciar sesión: $e');
    }
  }

  /// Intenta cambiar a una cuenta usando el refresh token guardado.
  /// Si el token es válido, cambia sin pedir contraseña.
  /// Retorna: null = éxito, string = error (sesión expirada, necesita contraseña).
  Future<String?> switchAccountByToken(String refreshToken) async {
    final service = _ref.read(adminAccessServiceProvider);
    // Guardar token actual por si falla la restauración
    final currentToken = service.currentRefreshToken;
    try {
      final restored = await service.restoreSession(refreshToken);
      if (!restored) {
        // Restaurar sesión anterior si falló
        if (currentToken != null) await service.restoreSession(currentToken);
        return 'SESSION_EXPIRED';
      }
      await bootstrap();
      return null;
    } catch (e) {
      if (currentToken != null) await service.restoreSession(currentToken);
      return 'SESSION_EXPIRED';
    }
  }

  /// Intenta cambiar a una cuenta con contraseña. Si falla la contraseña,
  /// la sesión actual NO se pierde (Supabase solo reemplaza sesión en éxito).
  Future<String?> switchAccountWithPassword({required String email, required String password}) async {
    try {
      await _ref.read(adminAccessServiceProvider).signIn(email: email, password: password);
      await bootstrap();
      return null; // éxito
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'No se pudo iniciar sesión: $e';
    }
  }

  Future<void> switchBusiness(String businessId) async {
    final profile = state.profile;
    if (profile == null) return;
    final next = await _ref.read(adminAccessServiceProvider).switchBusiness(
      current: profile,
      businessId: businessId,
    );
    if (next == null) return;
    state = state.copyWith(profile: next);
  }

  Future<void> signOut() async {
    await _ref.read(adminAccessServiceProvider).signOut();
    state = const AuthGateState.initial().copyWith(isLoading: false);
  }

  Future<void> _saveCurrentAccount(AdminAccessProfile profile) async {
    final savedService = _ref.read(savedAccountsServiceProvider);
    final service = _ref.read(adminAccessServiceProvider);
    final businessName = profile.branchName?.trim().isNotEmpty == true
        ? profile.branchName
        : profile.businessName;
    await savedService.saveAccount(SavedAccount(
      email: profile.email ?? '',
      displayName: profile.userName,
      businessName: businessName,
      refreshToken: service.currentRefreshToken,
    ));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final authGateViewModelProvider = StateNotifierProvider<AuthGateViewModel, AuthGateState>(
  (ref) => AuthGateViewModel(ref),
);
