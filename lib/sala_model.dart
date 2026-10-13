// lib/sala_model.dart
import 'dart:convert';
import 'filtro_model.dart';

// Graus A/B/C exigem etapas extras (recuperação de partículas e queda de energia); D não exige.
enum GrauSala { a, b, c, d }

class SalaModel {
  final String id;
  final String nome;
  final double area; // m²
  final double volume; // m³
  final GrauSala grau;
  final String handlingUnitId; // Máquina (UTA) principal que atende a sala
  final List<String> handlingUnitIdsAdicionais; // Casos raros de sala atendida por mais de uma máquina
  final List<FiltroModel> filtros; // Saídas/difusores da sala
  final Map<String, Map<String, dynamic>> configEnsaios;

  SalaModel({
    required this.id,
    required this.nome,
    required this.area,
    required this.volume,
    required this.grau,
    this.handlingUnitId = '',
    this.handlingUnitIdsAdicionais = const [],
    this.filtros = const [],
    this.configEnsaios = const {},
  });

  List<String> get handlingUnitIds => [handlingUnitId, ...handlingUnitIdsAdicionais];

  bool atendidaPor(String handlingUnitIdMaquina) => handlingUnitIds.contains(handlingUnitIdMaquina);

  bool get exigeTesteRecuperacaoEQuedaDeEnergia => grau != GrauSala.d;

  int get totalFiltros => filtros.fold(0, (soma, f) => soma + f.quantidade);

  /// Lista cada unidade de filtro da sala (um teste por unidade), na ordem de cadastro.
  List<FiltroModel> get unidadesDeFiltro => [
        for (final f in filtros)
          for (var i = 0; i < f.quantidade; i++) f,
      ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'area': area,
      'volume': volume,
      'grau': grau.name,
      'handlingUnitId': handlingUnitId,
      'handlingUnitIdsAdicionais': handlingUnitIdsAdicionais,
      'filtros': filtros.map((f) => f.toMap()).toList(),
      'configEnsaios': configEnsaios,
    };
  }

  factory SalaModel.fromMap(Map<String, dynamic> data) {
    return SalaModel(
      id: data['id']?.toString() ?? '',
      nome: data['nome']?.toString() ?? '',
      area: data['area'] is num
          ? (data['area'] as num).toDouble()
          : double.tryParse(data['area']?.toString() ?? '') ?? 0,
      volume: data['volume'] is num
          ? (data['volume'] as num).toDouble()
          : double.tryParse(data['volume']?.toString() ?? '') ?? 0,
      grau: GrauSala.values.firstWhere(
        (g) => g.name == (data['grau']?.toString() ?? '').toLowerCase(),
        orElse: () => GrauSala.d,
      ),
      handlingUnitId: data['handlingUnitId']?.toString() ?? '',
      handlingUnitIdsAdicionais: _lerListaIds(data['handlingUnitIdsAdicionais']),
      filtros: ((data['filtros'] ?? const []) as List)
          .map((f) => FiltroModel.fromMap(Map<String, dynamic>.from(f)))
          .toList(),
        configEnsaios: _lerConfigEnsaios(data['configEnsaios']),
    );
  }

  // SQLite guarda a lista como JSON (TEXT); Firestore como array.
  static List<String> _lerListaIds(dynamic valor) {
    if (valor is List) return valor.map((e) => e.toString()).toList();
    if (valor is String && valor.isNotEmpty) {
      try {
        return (jsonDecode(valor) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return const [];
  }

  static Map<String, Map<String, dynamic>> _lerConfigEnsaios(dynamic valor) {
    dynamic bruto = valor;
    if (bruto is String && bruto.isNotEmpty) {
      try {
        bruto = jsonDecode(bruto);
      } catch (_) {
        return const {};
      }
    }
    if (bruto is! Map) return const {};
    return bruto.map<String, Map<String, dynamic>>((chave, dados) => MapEntry(
          chave.toString(),
          dados is Map ? Map<String, dynamic>.from(dados) : <String, dynamic>{},
        ));
  }
}
