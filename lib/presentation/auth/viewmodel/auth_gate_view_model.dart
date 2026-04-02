import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/di/providers.dart';
import '../../../domain/auth/admin_access_profile.dart';

const _keepSessionKey = 'keep_session';

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

  Future<void> bootstrap() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final service = _ref.read(adminAccessServiceProvider);

    try {
      final user = service.currentUser;
      if (user == null) {
        state = const AuthGateState.initial().copyWith(isLoading: false);
        return;
      }

      // Si el usuario no quiso mantener sesión, cerrar al reabrir la app.
      final prefs = await SharedPreferences.getInstance();
      final keepSession = prefs.getBool(_keepSessionKey) ?? true;
      if (!keepSession) {
        await service.signOut();
        await prefs.remove(_keepSessionKey);
        state = const AuthGateState.initial().copyWith(isLoading: false);
        return;
      }

      final profile = await service.resolveCurrentAccess();
      state = AuthGateState(
        isLoading: false,
        isAuthenticated: true,
        profile: profile,
        error: profile == null ? 'No se pudo resolver el negocio o rol del usuario.' : null,
      );
    } catch (e) {
      final errorStr = e.toString();
      // Error 500 mismatch in GoTrue/DB: unblock by clearing session
      if (errorStr.contains('500') || errorStr.contains('refresh_token_hmac_key')) {
        final service = _ref.read(adminAccessServiceProvider);
        await service.signOut();
        state = AuthGateState(
          isLoading: false,
          isAuthenticated: false,
          profile: null,
          error: 'Su sesión ha expirado o requiere re-autenticación ($errorStr). Por favor inicie sesión de nuevo.',
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

  Future<void> signIn({required String email, required String password, bool keepSession = true}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keepSessionKey, keepSession);
      await _ref.read(adminAccessServiceProvider).signIn(email: email, password: password);
      await bootstrap();
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'No se pudo iniciar sesión: $e');
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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final authGateViewModelProvider = StateNotifierProvider<AuthGateViewModel, AuthGateState>(
  (ref) => AuthGateViewModel(ref),
);
