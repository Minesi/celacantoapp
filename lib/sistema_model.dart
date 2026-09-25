// lib/sistema_model.dart
// Sistema (ex.: "HDA04") é cadastrado uma vez e reutilizado entre relatórios do mesmo cliente,
// no mesmo padrão híbrido SQLite + Firestore de empresa_model.dart.
import 'dart:convert';

class SistemaModel {
  final String id; // ID do documento no Firestore
  final String nome;
  final List<String> areasAtendidas;
  final String dominioEmpresa;

  SistemaModel({
    required this.id,
    required this.nome,
    this.areasAtendidas = const [],
    required this.dominioEmpresa,
  });

  /// Representação para o cache local em SQLite (lista serializada como JSON).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'areasAtendidas': jsonEncode(areasAtendidas),
      'dominio_empresa': dominioEmpresa,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nome': nome,
      'areasAtendidas': areasAtendidas,
      'dominio': dominioEmpresa,
    };
  }

  factory SistemaModel.fromFirestore(Map<String, dynamic> data, String id) {
    return SistemaModel(
      id: id,
      nome: data['nome'] ?? '',
      areasAtendidas: List<String>.from(data['areasAtendidas'] ?? const []),
      dominioEmpresa: data['dominio'] ?? data['dominio_empresa'] ?? '',
    );
  }

  factory SistemaModel.fromMap(Map<String, dynamic> data) {
    final areasBrutas = data['areasAtendidas'];
    List<String> areas = const [];
    if (areasBrutas is String && areasBrutas.isNotEmpty) {
      areas = List<String>.from(jsonDecode(areasBrutas));
    } else if (areasBrutas is List) {
      areas = List<String>.from(areasBrutas);
    }

    return SistemaModel(
      id: data['id']?.toString() ?? '',
      nome: data['nome']?.toString() ?? '',
      areasAtendidas: areas,
      dominioEmpresa: data['dominio_empresa']?.toString() ?? '',
    );
  }
}
