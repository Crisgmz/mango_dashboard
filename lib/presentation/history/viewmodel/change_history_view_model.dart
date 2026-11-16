import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/di/providers.dart';
import '../../../data/history/change_history_service.dart';
import '../../../domain/history/change_history_entry.dart';
import '../change_history_text.dart';

class ChangeHistoryState {
  const ChangeHistoryState({
    this.entries = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.notActivated = false,
    this.area = 'all',
    this.action,
    this.search = '',
  });

  final List<ChangeHistoryEntry> entries;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  /// La tabla no existe todavía en el servidor (falta la migración).
  final bool notActivated;

  /// Clave de [historyAreas].
  final String area;

  /// create | update | delete | void; null = todas.
  final String? action;
  final String search;

  bool get hasFilters =>
      area != 'all' || action != null || search.trim().isNotEmpty;

  ChangeHistoryState copyWith({
    List<ChangeHistoryEntry>? entries,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    bool? notActivated,
    String? area,
    String? action,
    bool clearAction = false,
    String? search,
  }) {
    return ChangeHistoryState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      notActivated: notActivated ?? this.notActivated,
      area: area ?? this.area,
      action: clearAction ? null : (action ?? this.action),
      search: search ?? this.search,
    );
  }
}

class ChangeHistoryViewModel extends StateNotifier<ChangeHistoryState> {
  ChangeHistoryViewModel(this._ref) : super(const ChangeHistoryState());

  final Ref _ref;
  String? _businessId;

  /// Cada carga nueva invalida las que siguen en vuelo (filtro cambiado).
  int _request = 0;

  Future<void> load(String businessId) {
    _businessId = businessId;
    return _fetch(reset: true);
  }

  /// Recarga en silencio: conserva la lista mientras llega la nueva.
  Future<void> refresh() => _fetch(reset: true, silent: true);

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    await _fetch(reset: false);
  }

  void setArea(String area) {
    if (area == state.area) return;
    state = state.copyWith(area: area);
    _fetch(reset: true);
  }

  void setAction(String? action) {
    if (action == state.action) return;
    state = state.copyWith(action: action, clearAction: action == null);
    _fetch(reset: true);
  }

  void setSearch(String search) {
    if (search.trim() == state.search.trim()) return;
    state = state.copyWith(search: search);
    _fetch(reset: true);
  }

  Future<void> _fetch({required bool reset, bool silent = false}) async {
    final businessId = _businessId;
    if (businessId == null) return;
    final request = ++_request;
    state = reset
        ? state.copyWith(
            isLoading: !silent || state.entries.isEmpty,
            isLoadingMore: false,
            clearError: true,
          )
        : state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final area = historyAreas.firstWhere(
        (a) => a.key == state.area,
        orElse: () => historyAreas.first,
      );
      final page = await _ref
          .read(changeHistoryServiceProvider)
          .loadPage(
            businessId: businessId,
            offset: reset ? 0 : state.entries.length,
            tables: area.tables,
            action: state.action,
            search: state.search,
          );
      if (!mounted || request != _request) return;
      state = state.copyWith(
        entries: reset ? page : [...state.entries, ...page],
        hasMore: page.length == ChangeHistoryService.pageSize,
        isLoading: false,
        isLoadingMore: false,
        notActivated: false,
      );
    } catch (e) {
      if (!mounted || request != _request) return;
      final missing = _isMissingTable(e);
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        notActivated: missing,
        error: missing ? null : _friendly(e),
      );
    }
  }

  bool _isMissingTable(Object e) {
    if (e is! PostgrestException) return false;
    return e.code == 'PGRST205' ||
        e.code == '42P01' ||
        (e.message.contains('change_history') &&
            RegExp(
              r'exist|schema cache',
              caseSensitive: false,
            ).hasMatch(e.message));
  }

  String _friendly(Object e) {
    final lower = e.toString().toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection')) {
      return 'Sin conexión a internet.';
    }
    if (lower.contains('row-level security') ||
        lower.contains('permission') ||
        lower.contains('42501')) {
      return 'Solo el dueño o un administrador puede ver el historial.';
    }
    return 'No se pudo cargar el historial. Intenta de nuevo.';
  }
}

final changeHistoryViewModelProvider =
    StateNotifierProvider.autoDispose<
      ChangeHistoryViewModel,
      ChangeHistoryState
    >((ref) => ChangeHistoryViewModel(ref));
