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
  bool _bootstrapping = false;
  static const _maxRetries = 3;

  Future<void> bootstrap() async {
    // Skip concurrent bootstraps. Supabase's auth subscription fires
    // bootstrap whenever the session changes (signIn / tokenRefreshed /
    // signOut), and several call sites also await it explicitly.
    // Re-entering causes a write race on SharedPreferences and can
    // overwrite a successful state with a stale one.
    if (_bootstrapping) return;
    _bootstrapping = true;
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
        // Guardar cuenta automáticamente al resolver acceso. Falla aquí
        // (ej. SharedPreferences corrupto) NO debe romper el login.
        try {
          await _saveCurrentAccount(profile);
        } catch (_) {
          // Persisting saved-account metadata is best-effort.
        }
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
          // Release the guard before recursing — the inner bootstrap will
          // re-acquire it. Without this, the recursive call would no-op.
          _bootstrapping = false;
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
        error: _friendlyNetworkError(e),
      );
    } finally {
      _bootstrapping = false;
    }
  }

  /// Maps Supabase [AuthException] codes/messages to localized user text.
  static String _friendlyAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials') ||
        msg.contains('invalid grant')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Tu correo aún no ha sido verificado.';
    }
    if (msg.contains('user not found')) {
      return 'No existe una cuenta con ese correo.';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
    }
    if (msg.contains('network') || msg.contains('fetch') || msg.contains('socket')) {
      return 'Sin conexión. Verifica tu internet e intenta de nuevo.';
    }
    // Fall back to a clean generic message — never surface internals.
    return 'No se pudo iniciar sesión. Intenta de nuevo.';
  }

  /// Maps generic / network exceptions to localized user text without
  /// surfacing URLs, errno values, or stack-trace details.
  static String _friendlyNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection closed')) {
      return 'Sin conexión a internet. Verifica tu red e intenta de nuevo.';
    }
    if (msg.contains('timeoutexception') || msg.contains('timed out')) {
      return 'El servidor tardó demasiado en responder. Intenta de nuevo.';
    }
    if (msg.contains('handshakeexception') || msg.contains('certificate')) {
      return 'Error de conexión segura. Verifica tu red.';
    }
    if (msg.contains('500') || msg.contains('502') || msg.contains('503') || msg.contains('504')) {
      return 'El servidor no está disponible en este momento. Intenta más tarde.';
    }
    return 'No se pudo iniciar sesión. Intenta de nuevo.';
  }

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _ref.read(adminAccessServiceProvider).signIn(email: email, password: password);
      await bootstrap();
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyAuthError(e));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyNetworkError(e));
    }
  }

  /// Switches to a saved account, trying paths in order of speed:
  /// 1) Instant restore from cached serialized session (no network) when the
  ///    access token still has > 30s of life.
  /// 2) Network refresh via stored refresh token.
  /// 3) Re-auth with stored password.
  /// Returns null on success, or 'SESSION_EXPIRED' when all paths failed.
  Future<String?> switchAccountByToken(SavedAccount account) async {
    final service = _ref.read(adminAccessServiceProvider);

    // 1. Instant path — cached access token is still fresh.
    if (account.serializedSession != null && account.hasFreshAccessToken) {
      final ok = await service.recoverSerializedSession(account.serializedSession!);
      if (ok) {
        await bootstrap();
        if (state.profile != null) {
          await _saveCurrentAccount(state.profile!, password: account.password);
        }
        return null;
      }
    }

    // 2. Network refresh via refresh token.
    if (account.refreshToken != null) {
      final restored = await service.restoreSession(account.refreshToken!);
      if (restored) {
        await bootstrap();
        if (state.profile != null) {
          await _saveCurrentAccount(state.profile!, password: account.password);
        }
        return null;
      }
    }

    // 3. Re-auth with stored password.
    if (account.password != null) {
      try {
        await service.signIn(email: account.email, password: account.password!);
        await bootstrap();
        return null;
      } catch (_) {
        // All paths failed — fall through.
      }
    }

    return 'SESSION_EXPIRED';
  }

  /// Intenta cambiar a una cuenta con contraseña. Si falla la contraseña,
  /// la sesión actual NO se pierde (Supabase solo reemplaza sesión en éxito).
  Future<String?> switchAccountWithPassword({required String email, required String password}) async {
    try {
      await _ref.read(adminAccessServiceProvider).signIn(email: email, password: password);
      final profile = await _ref.read(adminAccessServiceProvider).resolveCurrentAccess();
      if (profile != null) {
        await _saveCurrentAccount(profile, password: password);
      }
      await bootstrap();
      return null; // éxito
    } on AuthException catch (e) {
      return _friendlyAuthError(e);
    } catch (e) {
      return _friendlyNetworkError(e);
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
    
    // Preservar la cuenta guardada con su password si existe
    final oldAccounts = await _ref.read(savedAccountsServiceProvider).loadAccounts();
    final currentSaved = oldAccounts.where((a) => a.email == next.email).firstOrNull;
    
    await _saveCurrentAccount(next, password: currentSaved?.password);
    state = state.copyWith(profile: next);
  }

  Future<void> signOut() async {
    await _ref.read(adminAccessServiceProvider).signOut();
    state = const AuthGateState.initial().copyWith(isLoading: false);
  }

  Future<void> _saveCurrentAccount(AdminAccessProfile profile, {String? password}) async {
    final savedService = _ref.read(savedAccountsServiceProvider);
    final service = _ref.read(adminAccessServiceProvider);

    final existing = await savedService.loadAccounts();
    final current = existing.where((a) => a.email == profile.email).firstOrNull;

    final passwordToSave = password ?? current?.password;
    final biometricEnabled = current?.biometricEnabled ?? false;

    final businessName = profile.branchName?.trim().isNotEmpty == true
        ? profile.branchName
        : profile.businessName;
    await savedService.saveAccount(SavedAccount(
      email: profile.email ?? '',
      displayName: profile.userName,
      businessName: businessName,
      refreshToken: service.currentRefreshToken,
      password: passwordToSave,
      biometricEnabled: biometricEnabled,
      serializedSession: service.currentSerializedSession,
      accessTokenExpiresAt: service.currentAccessTokenExpiresAt,
    ));
  }

  /// Enables or disables biometric unlock for a saved account.
  /// Returns true on success.
  Future<bool> setBiometricEnabled(String email, bool enabled) async {
    final savedService = _ref.read(savedAccountsServiceProvider);
    final accounts = await savedService.loadAccounts();
    final account = accounts.where((a) => a.email == email).firstOrNull;
    if (account == null) return false;
    await savedService.updateAccount(account.copyWith(biometricEnabled: enabled));
    return true;
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
