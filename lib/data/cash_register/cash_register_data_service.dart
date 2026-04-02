import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/dashboard/dashboard_models.dart';

class CashRegisterDataService {
  CashRegisterDataService(this._client);

  final SupabaseClient _client;

  Future<CashRegisterSummary> loadSummary(String businessId) async {
    final openRaw = await _client
        .from('cash_register_sessions')
        .select('''
          id,
          cash_register_id,
          opened_at,
          closed_at,
          start_amount,
          end_amount,
          difference,
          status,
          device_name,
          user_id,
          cash_registers!inner(id, business_id, name)
        ''')
        .eq('cash_registers.business_id', businessId)
        .eq('status', 'open')
        .isFilter('closed_at', null)
        .order('opened_at', ascending: false);

    final openRows = List<Map<String, dynamic>>.from(openRaw);

    final closedRaw = await _client
        .from('cash_register_sessions')
        .select('''
          id,
          cash_register_id,
          opened_at,
          closed_at,
          start_amount,
          end_amount,
          difference,
          status,
          device_name,
          user_id,
          cash_registers!inner(id, business_id, name)
        ''')
        .eq('cash_registers.business_id', businessId)
        .not('closed_at', 'is', null)
        .order('closed_at', ascending: false)
        .limit(20);

    final closedRows = List<Map<String, dynamic>>.from(closedRaw);

    final allSessionIds = [
      ...openRows.map((row) => row['id']?.toString()),
      ...closedRows.map((row) => row['id']?.toString()),
    ].whereType<String>().toList(growable: false);

    final txBySession = await _transactionsBySession(allSessionIds);
    final usersById = await _profilesByUserId([
      ...openRows.map((row) => row['user_id']?.toString()),
      ...closedRows.map((row) => row['user_id']?.toString()),
    ].whereType<String>().toList(growable: false));

    final openRegisters = openRows
        .map((row) => _toSession(row, txBySession[row['id']?.toString()] ?? _SessionTx(), usersById))
        .toList(growable: false);

    final closings = closedRows
        .map((row) => _toClosing(row, txBySession[row['id']?.toString()] ?? _SessionTx(), usersById))
        .toList(growable: false);

    final registersRaw = await _client
        .from('cash_registers')
        .select('id, is_active')
        .eq('business_id', businessId);
    final registerRows = List<Map<String, dynamic>>.from(registersRaw);
    final totalRegisters = registerRows.length;
    final activeRegisters = registerRows.where((row) => row['is_active'] == true).length;

    RegisterSession? topRegister;
    if (openRegisters.isNotEmpty) {
      topRegister = openRegisters.reduce((a, b) => a.totalSales >= b.totalSales ? a : b);
    }
    if (closings.isNotEmpty) {
      final topClosing = closings.reduce((a, b) => a.totalSales >= b.totalSales ? a : b);
      if (topRegister == null || topClosing.totalSales > topRegister.totalSales) {
        topRegister = RegisterSession(
          id: topClosing.id,
          registerName: topClosing.registerName,
          openedAt: topClosing.closedAt,
          openedByName: topClosing.closedByName,
          closedAt: topClosing.closedAt,
          deviceName: topClosing.deviceName,
          openingAmount: topClosing.openingAmount,
          totalSales: topClosing.totalSales,
          status: 'closed',
        );
      }
    }

    return CashRegisterSummary(
      openRegisters: openRegisters,
      closings: closings,
      totalRegisters: totalRegisters,
      activeRegisters: activeRegisters,
      topRegister: topRegister,
    );
  }

  Future<Map<String, String>> _profilesByUserId(List<String> userIds) async {
    if (userIds.isEmpty) return const {};

    final rows = await _client
        .from('profiles')
        .select('id, full_name')
        .inFilter('id', userIds.toSet().toList(growable: false));

    final result = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final fullName = row['full_name']?.toString().trim();
      result[id] = (fullName == null || fullName.isEmpty) ? 'Desconocido' : fullName;
    }
    return result;
  }

  Future<Map<String, _SessionTx>> _transactionsBySession(List<String> sessionIds) async {
    if (sessionIds.isEmpty) return const {};

    final rows = await _client
        .from('cash_transactions')
        .select('session_id, amount, type')
        .inFilter('session_id', sessionIds);

    final result = <String, _SessionTx>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final sessionId = row['session_id']?.toString();
      if (sessionId == null || sessionId.isEmpty) continue;
      final tx = result[sessionId] ??= _SessionTx();
      final amount = _toDouble(row['amount']);
      switch (row['type']?.toString()) {
        case 'sale':
          tx.sales += amount;
          break;
        case 'deposit':
          tx.deposits += amount;
          break;
        case 'withdrawal':
          tx.withdrawals += amount;
          break;
        case 'expense':
          tx.expenses += amount;
          break;
        default:
          break;
      }
    }
    return result;
  }

  RegisterSession _toSession(
    Map<String, dynamic> row,
    _SessionTx tx,
    Map<String, String> usersById,
  ) {
    final register = row['cash_registers'];
    final userId = row['user_id']?.toString() ?? '';
    final registerName = register is Map<String, dynamic>
        ? register['name']?.toString() ?? 'Caja'
        : 'Caja';

    return RegisterSession(
      id: row['id']?.toString() ?? '',
      registerName: registerName,
      openedAt: DateTime.tryParse(row['opened_at']?.toString() ?? '') ?? DateTime.now(),
      openedByName: usersById[userId] ?? 'Desconocido',
      closedAt: DateTime.tryParse(row['closed_at']?.toString() ?? ''),
      deviceName: row['device_name']?.toString(),
      openingAmount: _toDouble(row['start_amount']),
      totalSales: tx.sales,
      status: row['status']?.toString() ?? 'open',
    );
  }

  RegisterClosing _toClosing(
    Map<String, dynamic> row,
    _SessionTx tx,
    Map<String, String> usersById,
  ) {
    final register = row['cash_registers'];
    final userId = row['user_id']?.toString() ?? '';
    final registerName = register is Map<String, dynamic>
        ? register['name']?.toString() ?? 'Caja'
        : 'Caja';

    final openingAmount = _toDouble(row['start_amount']);
    final closingAmount = _toDouble(row['end_amount']);
    final expectedAmount = openingAmount + tx.sales + tx.deposits - tx.withdrawals - tx.expenses;

    return RegisterClosing(
      id: row['id']?.toString() ?? '',
      registerName: registerName,
      closedAt: DateTime.tryParse(row['closed_at']?.toString() ?? '') ?? DateTime.now(),
      closedByName: usersById[userId] ?? 'Desconocido',
      deviceName: row['device_name']?.toString(),
      openingAmount: openingAmount,
      closingAmount: closingAmount,
      expectedAmount: expectedAmount,
      totalSales: tx.sales,
      totalDeposits: tx.deposits,
      totalWithdrawals: tx.withdrawals,
      totalExpenses: tx.expenses,
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _SessionTx {
  double sales = 0;
  double deposits = 0;
  double withdrawals = 0;
  double expenses = 0;
}
