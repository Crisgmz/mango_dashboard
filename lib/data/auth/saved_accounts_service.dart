import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/auth/saved_account.dart';

const _savedAccountsKey = 'saved_accounts';

class SavedAccountsService {
  Future<List<SavedAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_savedAccountsKey);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAccount(SavedAccount account) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.email == account.email);
    accounts.insert(0, account);
    await _persist(accounts);
  }

  Future<void> removeAccount(String email) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.email == email);
    await _persist(accounts);
  }

  Future<void> _persist(List<SavedAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_savedAccountsKey, encoded);
  }
}
