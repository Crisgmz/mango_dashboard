import 'package:flutter/foundation.dart';

@immutable
class SavedAccount {
  const SavedAccount({
    required this.email,
    required this.displayName,
    this.businessName,
    this.refreshToken,
  });

  final String email;
  final String displayName;
  final String? businessName;
  final String? refreshToken;

  SavedAccount copyWith({
    String? displayName,
    String? businessName,
    String? refreshToken,
  }) {
    return SavedAccount(
      email: email,
      displayName: displayName ?? this.displayName,
      businessName: businessName ?? this.businessName,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        businessName: json['businessName'] as String?,
        refreshToken: json['refreshToken'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        'displayName': displayName,
        if (businessName != null) 'businessName': businessName,
        if (refreshToken != null) 'refreshToken': refreshToken,
      };
}
