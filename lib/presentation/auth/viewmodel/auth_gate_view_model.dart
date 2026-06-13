import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/di/providers.dart';
import '../../../core/auth/biometric_auth_service.dart';
import '../../../core/notifications/fcm_service.dart';
import '../../../domain/auth/admin_access_profile.dart';
import '../../../domain/auth/saved_account.dart';

class AuthGateState {
  const AuthGateState({
    required this.isLoading,
    required this.isAuthenticated,
    required this.profile,
    required this.error,
    this.isLocked = false,
    this.biometricEnabled = false,
  });

  const AuthGateState.initial()
    : isLoading = true,
      isAuthenticated = false,
      profile = null,
      error = null,
      isLocked = false,
      biometricEnabled = false;

  final bool isLoading;
  final bool isAuthenticated;
  final AdminAccessProfile? profile;
  final String? error;

  /// True cuando la sesión está activa pero la app exige una verificación
  /// biométrica para mostrar contenido (auto-lock al abrir / volver del fondo).
  final bool isLocked;

  /// Cached: whether the current account has biometric unlock enabled. Resolved
  /// once at bootstrap so the lifecycle auto-lock check is synchronous (no
  /// SharedPreferences read on every app pause/resume).
  final bool biometricEnabled;

  AuthGateState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    AdminAccessProfile? profile,
    String? error,
    bool? isLocked,
    bool? biometricEnabled,
    bool clearError = false,
  }) {
    return AuthGateState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      profile: profile ?? this.profile,
      error: clearError ? null : (error ?? this.error),
      isLocked: isLocked ?? this.isLocked,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    );
  }
}

class AuthGateViewModel extends StateNotifier<AuthGateState> {
  AuthGateViewModel(this._ref) : super(const AuthGateState.initial()) {
    _subscription = _ref.read(adminAccessServiceProvider).authStates().listen(
      (_) => bootstrap(),
      // Supabase's auth client also notifies exceptions through this stream
      // (e.g. recoverSession failures with corrupt cached sessions). Sin un
      // onError aquí, esos errores se convierten en uncaught exceptions y
      // tumban runtime. Re-corremos bootstrap para que la UI recupere un
      // estado coherente (probablemente termine en login).
      onError: (_) => bootstrap(),
    );
  }

  final Ref _ref;
  StreamSubscription<AuthState>? _subscription;
  int _retryCount = 0;
  bool _bootstrapping = false;
  static const _maxRetries = 3;

  /// Set transiently by [signIn] so the bootstrap that follows (whether
  /// triggered by us or by the Supabase auth subscription) persists the
  /// password alongside the refresh token. Without this the password is
  /// never saved on first login, breaking the biometric/auto-switch
  /// fallback chain when the refresh token eventually rotates out.
  String? _pendingPasswordForSave;

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
          await _saveCurrentAccount(profile, password: _pendingPasswordForSave);
        } catch (_) {
          // Persisting saved-account metadata is best-effort.
        }
      }
      _retryCount = 0;

      // Auto-lock: si la cuenta tiene biometría activada y venimos de un
      // signIn fresco no la bloqueamos (el usuario ya se autenticó con
      // contraseña/biometría en ese flujo). En cualquier otro caso —arranque
      // con sesión persistida o resume del fondo— exigimos verificación.
      final biometricEnabled =
          profile != null && await _isBiometricEnabledFor(profile.email);
      final shouldLock = biometricEnabled && _pendingPasswordForSave == null;

      state = AuthGateState(
        isLoading: false,
        isAuthenticated: true,
        profile: profile,
        error: profile == null ? 'No se pudo resolver el negocio o rol del usuario.' : null,
        isLocked: shouldLock,
        biometricEnabled: biometricEnabled,
      );

      // Register this device for push so cash-close / void / cash-mismatch
      // alerts arrive even with the app closed. Fire-and-forget.
      if (profile != null) {
        unawaited(FcmService.registerToken(businessId: profile.businessId));
      }
    } catch (e) {
      final errorStr = e.toString();
      final errorLower = errorStr.toLowerCase();
      final isNetworkError = errorLower.contains('socketexception') ||
          errorLower.contains('failed host lookup') ||
          errorLower.contains('network is unreachable') ||
          errorLower.contains('connection refused') ||
          errorLower.contains('connection closed') ||
          errorLower.contains('timeoutexception') ||
          errorLower.contains('timed out');

      // If we were already authenticated and the failure is a network blip,
      // keep the session as-is. Kicking the user back to the login screen
      // every time wifi hiccups is terrible UX — they can re-pull to refresh.
      if (isNetworkError && state.isAuthenticated && state.profile != null) {
        state = state.copyWith(isLoading: false, clearError: true);
        return;
      }

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
    // Set before service.signIn so the auth-state subscription's bootstrap
    // (which may race with our explicit one below) also sees the password
    // and persists it on the saved account.
    _pendingPasswordForSave = password;
    try {
      await _ref.read(adminAccessServiceProvider).signIn(email: email, password: password);
      await bootstrap();
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyAuthError(e));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyNetworkError(e));
    } finally {
      _pendingPasswordForSave = null;
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
      // La sesión serializada falló — probablemente quedó stale o corrupta
      // tras un upgrade de schema. Limpiamos esos campos del SavedAccount
      // para no volver a entrar en el mismo camino fallido en el próximo tap.
      await _clearStaleSerializedSession(account);
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
    // Igual que en [signIn]: marcamos la contraseña como "recién verificada"
    // para que el bootstrap subsiguiente (disparado por la suscripción de
    // Supabase o por nuestro await abajo) NO dispare auto-lock — el usuario
    // acaba de autenticarse manualmente, pedir biometría inmediatamente
    // sería redundante.
    _pendingPasswordForSave = password;
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
    } finally {
      _pendingPasswordForSave = null;
    }
  }

  /// Cambia de negocio. Si la cuenta tiene biometría activada, exige una
  /// verificación previa antes de cambiar — el dashboard de cada sucursal
  /// puede mostrar datos de otra (caja, ventas, RNCs), así que reusamos el
  /// mismo gate biométrico que protege el auto-lock.
  ///
  /// Devuelve null en éxito, o un código de error:
  ///  - 'BIO_FAILED'   → biometría falló / cancelada
  ///  - 'BIO_LOCKED'   → biometría bloqueada por el sistema
  ///  - 'NO_CHANGE'    → switch falló (ya estabas ahí o no permitido)
  Future<String?> switchBusiness(String businessId) async {
    final profile = state.profile;
    if (profile == null) return 'NO_CHANGE';

    if (await _isBiometricEnabledFor(profile.email)) {
      final gate = await _runBiometricGate(
        reason: 'Confirma tu identidad para cambiar de negocio',
      );
      if (gate != null) return gate;
    }

    final next = await _ref.read(adminAccessServiceProvider).switchBusiness(
      current: profile,
      businessId: businessId,
    );
    if (next == null) return 'NO_CHANGE';

    // Preservar la cuenta guardada con su password si existe
    final oldAccounts = await _ref.read(savedAccountsServiceProvider).loadAccounts();
    final currentSaved = oldAccounts.where((a) => a.email == next.email).firstOrNull;

    await _saveCurrentAccount(next, password: currentSaved?.password);
    state = state.copyWith(profile: next);
    // Re-point this device's push token at the newly selected business.
    unawaited(FcmService.registerToken(businessId: next.businessId));
    return null;
  }

  /// Bloquea la app exigiendo biometría para volver a verla. Llamado al
  /// volver del fondo cuando la cuenta tiene biometría activada.
  void lock() {
    if (!state.isAuthenticated || state.isLocked) return;
    state = state.copyWith(isLocked: true);
  }

  /// Intenta desbloquear con biometría. Devuelve null en éxito o un código
  /// para que la UI muestre un mensaje:
  ///  - 'BIO_FAILED'  → falló o cancelada (botón "Reintentar")
  ///  - 'BIO_LOCKED'  → biometría bloqueada por el sistema
  ///  - 'BIO_MISSING' → ya no hay biometría enrolada (caer a logout)
  Future<String?> unlock() async {
    final gate = await _runBiometricGate(
      reason: 'Confirma tu identidad para acceder al dashboard',
    );
    if (gate != null) return gate;
    state = state.copyWith(isLocked: false);
    return null;
  }

  Future<String?> _runBiometricGate({required String reason}) async {
    final biometric = _ref.read(biometricAuthServiceProvider);
    final available = await biometric.isAvailable();
    if (!available) return 'BIO_MISSING';
    final result = await biometric.authenticate(reason: reason);
    switch (result) {
      case BiometricResult.success:
        return null;
      case BiometricResult.lockedOut:
        return 'BIO_LOCKED';
      case BiometricResult.notEnrolled:
      case BiometricResult.notAvailable:
        return 'BIO_MISSING';
      case BiometricResult.cancelled:
      case BiometricResult.failed:
      case BiometricResult.error:
        return 'BIO_FAILED';
    }
  }

  /// Borra el `serializedSession` y `accessTokenExpiresAt` de un SavedAccount
  /// que falló al restaurarse. Best-effort — un fallo aquí no rompe el login.
  Future<void> _clearStaleSerializedSession(SavedAccount account) async {
    try {
      final savedService = _ref.read(savedAccountsServiceProvider);
      await savedService.updateAccount(SavedAccount(
        email: account.email,
        displayName: account.displayName,
        businessName: account.businessName,
        refreshToken: account.refreshToken,
        password: account.password,
        biometricEnabled: account.biometricEnabled,
        // serializedSession y accessTokenExpiresAt quedan null a propósito.
      ));
    } catch (_) {
      // Si SharedPreferences falla, ni modo — el siguiente intento volverá a
      // pasar por aquí y se reintentará. No queremos que esto bloquee el flujo.
    }
  }

  Future<bool> _isBiometricEnabledFor(String? email) async {
    if (email == null || email.isEmpty) return false;
    try {
      final accounts =
          await _ref.read(savedAccountsServiceProvider).loadAccounts();
      final account = accounts.where((a) => a.email == email).firstOrNull;
      return account?.biometricEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    // Drop this device's push token first so a logged-out phone stops getting
    // the business's alerts (best-effort, before the session is gone).
    await FcmService.unregisterToken();
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
