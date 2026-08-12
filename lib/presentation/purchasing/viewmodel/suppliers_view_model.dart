import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/purchasing/supplier.dart';

/// Datos del formulario de suplidor (crear/editar).
class SupplierDraft {
  const SupplierDraft({
    required this.name,
    this.rnc,
    this.taxIdType,
    this.contactName,
    this.phone,
    this.whatsapp,
    this.email,
    this.address,
    this.paymentTermsDays = 0,
    this.notes,
    this.isActive = true,
  });

  final String name;
  final String? rnc;
  final String? taxIdType;
  final String? contactName;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? address;
  final int paymentTermsDays;
  final String? notes;
  final bool isActive;
}

class SuppliersState {
  const SuppliersState({
    this.isLoading = false,
    this.suppliers = const [],
    this.error,
    this.savingIds = const {},
    this.saving = false,
  });

  final bool isLoading;
  final List<Supplier> suppliers;
  final String? error;

  /// Ids con toggle activo/inactivo en curso.
  final Set<String> savingIds;

  /// True mientras un create/update/delete está en curso.
  final bool saving;

  SuppliersState copyWith({
    bool? isLoading,
    List<Supplier>? suppliers,
    String? error,
    Set<String>? savingIds,
    bool? saving,
    bool clearError = false,
  }) {
    return SuppliersState(
      isLoading: isLoading ?? this.isLoading,
      suppliers: suppliers ?? this.suppliers,
      error: clearError ? null : (error ?? this.error),
      savingIds: savingIds ?? this.savingIds,
      saving: saving ?? this.saving,
    );
  }
}

class SuppliersViewModel extends StateNotifier<SuppliersState> {
  SuppliersViewModel(this._ref) : super(const SuppliersState());

  final Ref _ref;

  Future<void> load(String businessId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final suppliers =
          await _ref.read(purchasingDataServiceProvider).loadSuppliers(businessId);
      state = state.copyWith(
          isLoading: false, suppliers: suppliers, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendly(e));
    }
  }

  Future<void> refresh(String businessId) async {
    try {
      final suppliers =
          await _ref.read(purchasingDataServiceProvider).loadSuppliers(businessId);
      state = state.copyWith(suppliers: suppliers, clearError: true);
    } catch (_) {/* conserva los datos en pantalla */}
  }

  /// Crea un suplidor. Devuelve true si guardó OK.
  Future<bool> create(String businessId, SupplierDraft d) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(purchasingDataServiceProvider).createSupplier(
            businessId: businessId,
            name: d.name,
            rnc: d.rnc,
            taxIdType: d.taxIdType,
            contactName: d.contactName,
            phone: d.phone,
            whatsapp: d.whatsapp,
            email: d.email,
            address: d.address,
            paymentTermsDays: d.paymentTermsDays,
            notes: d.notes,
          );
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  /// Edita un suplidor existente. Devuelve true si guardó OK.
  Future<bool> update(String businessId, String id, SupplierDraft d) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(purchasingDataServiceProvider).updateSupplier(
            id: id,
            name: d.name,
            rnc: d.rnc,
            taxIdType: d.taxIdType,
            contactName: d.contactName,
            phone: d.phone,
            whatsapp: d.whatsapp,
            email: d.email,
            address: d.address,
            paymentTermsDays: d.paymentTermsDays,
            notes: d.notes,
            isActive: d.isActive,
          );
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return true;
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
      return false;
    }
  }

  /// Activa/desactiva de forma optimista; revierte si falla.
  Future<void> toggle(String businessId, String id, bool value) async {
    final before = state.suppliers;
    state = state.copyWith(
      suppliers: [
        for (final s in before) s.id == id ? s.copyWith(isActive: value) : s,
      ],
      savingIds: {...state.savingIds, id},
      clearError: true,
    );
    try {
      await _ref.read(purchasingDataServiceProvider).setSupplierActive(id, value);
      state = state.copyWith(savingIds: {...state.savingIds}..remove(id));
    } catch (e) {
      state = state.copyWith(
        suppliers: before,
        savingIds: {...state.savingIds}..remove(id),
        error: _friendly(e),
      );
    }
  }

  /// Elimina un suplidor. Devuelve mensaje de error si falla (null si OK).
  Future<String?> delete(String businessId, String id) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _ref.read(purchasingDataServiceProvider).deleteSupplier(id);
      await refresh(businessId);
      state = state.copyWith(saving: false);
      return null;
    } catch (e) {
      final msg = _friendly(e);
      state = state.copyWith(saving: false, error: msg);
      return msg;
    }
  }

  String _friendly(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection')) {
      return 'Sin conexión a internet.';
    }
    if (lower.contains('row-level security') ||
        lower.contains('permission') ||
        lower.contains('403')) {
      return 'No tienes permiso para modificar suplidores en este negocio.';
    }
    // PurchasingException u otros mensajes ya legibles.
    if (msg.isNotEmpty && msg.length < 160 && !lower.contains('exception:')) {
      return msg.replaceFirst('PurchasingException: ', '');
    }
    return 'No se pudo completar la operación. Intenta de nuevo.';
  }
}

final suppliersViewModelProvider =
    StateNotifierProvider<SuppliersViewModel, SuppliersState>(
  (ref) => SuppliersViewModel(ref),
);
