// lib/sala_model.dart
import 'filtro_model.dart';

// Graus A/B/C exigem etapas extras (recuperação de partículas e queda de energia); D não exige.
enum GrauSala { a, b, c, d }

class SalaModel {
  final String id;
  final String nome;
  final double area; // m²
  final double volume; // m³
  final GrauSala grau;
  final String handlingUnitId; // Máquina (UTA) que atende a sala
  final List<FiltroModel> filtros; // Saídas/difusores da sala

  SalaModel({
    required this.id,
    required this.nome,
    required this.area,
    required this.volume,
    required this.grau,
    this.handlingUnitId = '',
    this.filtros = const [],
  });

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
      'filtros': filtros.map((f) => f.toMap()).toList(),
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
      filtros: ((data['filtros'] ?? const []) as List)
          .map((f) => FiltroModel.fromMap(Map<String, dynamic>.from(f)))
          .toList(),
    );
  }
}
