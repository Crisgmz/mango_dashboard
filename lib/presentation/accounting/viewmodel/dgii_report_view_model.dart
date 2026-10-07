import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../data/accounting/dgii_report_service.dart';
import '../../../domain/accounting/dgii_reports.dart';
import '../../auth/viewmodel/auth_gate_view_model.dart';

/// Cuál de los tres formatos está pidiendo la pantalla.
enum DgiiFormat {
  f606('606', 'Compras de bienes y servicios'),
  f607('607', 'Ventas de bienes y servicios'),
  f608('608', 'Comprobantes anulados');

  const DgiiFormat(this.code, this.subtitle);

  /// `606` — el nombre con el que la DGII lo pide.
  final String code;

  /// Lo que declara ese formato.
  final String subtitle;

  /// `Formato 606`.
  String get title => 'Formato $code';
}

@immutable
class DgiiReportState {
  const DgiiReportState({
    required this.period,
    this.loading = true,
    this.rows606 = const [],
    this.rows607 = const [],
    this.rows608 = const [],
    this.classification = const DgiiClassification(),
    this.rnc,
    this.legalName,
    this.error,
    this.unavailable,
  });

  final DgiiPeriod period;
  final bool loading;

  final List<Dgii606Row> rows606;
  final List<Dgii607Row> rows607;
  final List<Dgii608Row> rows608;

  /// Clasificación elegida por el usuario para el 606 y el 608.
  final DgiiClassification classification;

  /// RNC del contribuyente — va en la cabecera del archivo. Sin él no se puede
  /// exportar: el prevalidador lo exige.
  final String? rnc;
  final String? legalName;

  /// Falló la carga (red, permisos).
  final String? error;

  /// La fuente de datos de este formato no está instalada en el backend.
  final String? unavailable;

  bool get hasRnc => (rnc ?? '').isNotEmpty;

  DgiiReportState copyWith({
    DgiiPeriod? period,
    bool? loading,
    List<Dgii606Row>? rows606,
    List<Dgii607Row>? rows607,
    List<Dgii608Row>? rows608,
    DgiiClassification? classification,
    Object? rnc = _unset,
    Object? legalName = _unset,
    Object? error = _unset,
    Object? unavailable = _unset,
  }) {
    return DgiiReportState(
      period: period ?? this.period,
      loading: loading ?? this.loading,
      rows606: rows606 ?? this.rows606,
      rows607: rows607 ?? this.rows607,
      rows608: rows608 ?? this.rows608,
      classification: classification ?? this.classification,
      rnc: identical(rnc, _unset) ? this.rnc : rnc as String?,
      legalName:
          identical(legalName, _unset) ? this.legalName : legalName as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      unavailable: identical(unavailable, _unset)
          ? this.unavailable
          : unavailable as String?,
    );
  }

  static const _unset = Object();
}

class DgiiReportViewModel extends StateNotifier<DgiiReportState> {
  DgiiReportViewModel(this._ref, this.format)
      : super(DgiiReportState(period: _defaultPeriod())) {
    load();
  }

  final Ref _ref;
  final DgiiFormat format;

  /// Arranca en el mes cerrado más reciente: el 606/607/608 se envía sobre el
  /// mes anterior (vence el 20 del siguiente), así que es lo que el usuario
  /// quiere ver al entrar.
  static DgiiPeriod _defaultPeriod() =>
      DgiiPeriod.of(DateTime.now()).previous;

  Future<void> load() async {
    final businessId = _ref.read(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) {
      state = state.copyWith(
          loading: false, error: 'No hay un negocio activo.');
      return;
    }
    state = state.copyWith(loading: true, error: null, unavailable: null);

    final service = _ref.read(dgiiReportServiceProvider);
    try {
      // La clasificación y el contribuyente no dependen del formato; se piden
      // junto con las filas para no encadenar tres esperas.
      final taxpayerFuture = service.businessTaxpayer(businessId);
      final classificationFuture =
          _ref.read(dgiiClassificationStoreProvider).load(businessId);

      var rows606 = const <Dgii606Row>[];
      var rows607 = const <Dgii607Row>[];
      var rows608 = const <Dgii608Row>[];
      switch (format) {
        case DgiiFormat.f606:
          rows606 = await service.load606(
              businessId: businessId, period: state.period);
        case DgiiFormat.f607:
          rows607 = await service.load607(
              businessId: businessId, period: state.period);
        case DgiiFormat.f608:
          rows608 = await service.load608(
              businessId: businessId, period: state.period);
      }

      final taxpayer = await taxpayerFuture;
      final classification = await classificationFuture;
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        rows606: rows606,
        rows607: rows607,
        rows608: rows608,
        classification: classification,
        rnc: taxpayer.rnc,
        legalName: taxpayer.legalName,
      );
    } on DgiiSourceUnavailable catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, unavailable: e.message);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: 'No se pudo cargar el ${format.code}. Revisa tu conexión e '
            'intenta de nuevo.',
      );
    }
  }

  void setPeriod(DgiiPeriod period) {
    if (period == state.period) return;
    state = state.copyWith(period: period);
    load();
  }

  /// Clasifica el tipo de bien/servicio de un proveedor (606). Aplica a todas
  /// sus recepciones, no solo a la fila tocada: es una propiedad del proveedor.
  Future<void> setExpenseType(Dgii606Row row, String code) async {
    final updated = state.classification.withExpenseType(row, code);
    state = state.copyWith(classification: updated);
    await _persist(updated);
  }

  /// Fija el tipo de anulación de un comprobante (608).
  Future<void> setVoidReason(Dgii608Row row, String code) async {
    final updated = state.classification.withVoidReason(row, code);
    state = state.copyWith(classification: updated);
    await _persist(updated);
  }

  Future<void> _persist(DgiiClassification value) async {
    final businessId = _ref.read(authGateViewModelProvider).profile?.businessId;
    if (businessId == null) return;
    await _ref.read(dgiiClassificationStoreProvider).save(businessId, value);
  }
}

/// Un notifier por formato: las tres pantallas son independientes y cada una
/// recuerda su propio mes mientras esté abierta.
final dgiiReportViewModelProvider = StateNotifierProvider.autoDispose
    .family<DgiiReportViewModel, DgiiReportState, DgiiFormat>((ref, format) {
  return DgiiReportViewModel(ref, format);
});
