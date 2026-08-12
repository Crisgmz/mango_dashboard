import 'package:flutter/foundation.dart';

/// Suplidor (tabla `suppliers`). Base del módulo de compras (PRD 6.1 F1) y
/// del bloque fiscal del 606: `taxIdType` + `rnc` identifican al proveedor
/// ante la DGII.
@immutable
class Supplier {
  const Supplier({
    required this.id,
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

  final String id;
  final String name;

  /// Número de identificación fiscal (RNC, cédula o pasaporte).
  final String? rnc;

  /// `rnc` | `cedula` | `pasaporte` — tipo del número en [rnc], para el 606.
  final String? taxIdType;

  final String? contactName;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? address;

  /// Término de pago en días (0 = contado).
  final int paymentTermsDays;

  final String? notes;
  final bool isActive;

  Supplier copyWith({bool? isActive}) {
    return Supplier(
      id: id,
      name: name,
      rnc: rnc,
      taxIdType: taxIdType,
      contactName: contactName,
      phone: phone,
      whatsapp: whatsapp,
      email: email,
      address: address,
      paymentTermsDays: paymentTermsDays,
      notes: notes,
      isActive: isActive ?? this.isActive,
    );
  }

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Suplidor',
      rnc: json['rnc']?.toString(),
      taxIdType: json['tax_id_type']?.toString(),
      contactName: json['contact_name']?.toString(),
      phone: json['phone']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      email: json['email']?.toString(),
      address: json['address']?.toString(),
      paymentTermsDays: json['payment_terms_days'] is int
          ? json['payment_terms_days'] as int
          : int.tryParse(json['payment_terms_days']?.toString() ?? '') ?? 0,
      notes: json['notes']?.toString(),
      isActive: json['is_active'] != false,
    );
  }
}
