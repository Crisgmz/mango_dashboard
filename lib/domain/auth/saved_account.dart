import 'package:flutter/foundation.dart';

@immutable
class SavedAccount {
  const SavedAccount({
    required this.email,
    required this.displayName,
    this.businessName,
    this.refreshToken,
    this.password,
    this.biometricEnabled = false,
    this.serializedSession,
    this.accessTokenExpiresAt,
  });

  final String email;
  final String displayName;
  final String? businessName;
  final String? refreshToken;
  final String? password;
  final bool biometricEnabled;

  /// Full Supabase session JSON — enables instant restore (no network) via
  /// `auth.recoverSession()` while the access token is still valid.
  final String? serializedSession;

  /// Unix epoch seconds at which the access token in [serializedSession]
  /// expires. Used to decide whether instant restore is viable or whether to
  /// fall back to a network refresh.
  final int? accessTokenExpiresAt;

  /// True when the cached access token has at least 30 seconds of life left,
  /// so an instant (no-network) session swap is safe.
  bool get hasFreshAccessToken {
    final expiresAt = accessTokenExpiresAt;
    if (expiresAt == null) return false;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return (expiresAt - now) > 30;
  }

  SavedAccount copyWith({
    String? displayName,
    String? businessName,
    String? refreshToken,
    String? password,
    bool? biometricEnabled,
    String? serializedSession,
    int? accessTokenExpiresAt,
  }) {
    return SavedAccount(
      email: email,
      displayName: displayName ?? this.displayName,
      businessName: businessName ?? this.businessName,
      refreshToken: refreshToken ?? this.refreshToken,
      password: password ?? this.password,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      serializedSession: serializedSession ?? this.serializedSession,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
    );
  }

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        businessName: json['businessName'] as String?,
        refreshToken: json['refreshToken'] as String?,
        password: json['password'] as String?,
        biometricEnabled: json['biometricEnabled'] as bool? ?? false,
        serializedSession: json['serializedSession'] as String?,
        accessTokenExpiresAt: json['accessTokenExpiresAt'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        'displayName': displayName,
        if (businessName != null) 'businessName': businessName,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (password != null) 'password': password,
        if (biometricEnabled) 'biometricEnabled': true,
        if (serializedSession != null) 'serializedSession': serializedSession,
        if (accessTokenExpiresAt != null) 'accessTokenExpiresAt': accessTokenExpiresAt,
      };
}
