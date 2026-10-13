// lib/handling_unit_model.dart
import 'filtro_model.dart';

class HandlingUnitModel {
  final String id;
  final String nome;
  final String numero;
  final List<FiltroModel> filtros;
  final bool temFiltroTerminal;
  final int qtdFiltrosTerminais;

  HandlingUnitModel({
    required this.id,
    required this.nome,
    this.numero = '',
    this.filtros = const [],
    this.temFiltroTerminal = false,
    this.qtdFiltrosTerminais = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'numero': numero,
      'filtros': filtros.map((f) => f.toMap()).toList(),
      'temFiltroTerminal': temFiltroTerminal,
      'qtdFiltrosTerminais': qtdFiltrosTerminais,
    };
  }

  factory HandlingUnitModel.fromMap(Map<String, dynamic> data) {
    return HandlingUnitModel(
      id: data['id']?.toString() ?? '',
      nome: data['nome']?.toString() ?? '',
      numero: data['numero']?.toString() ?? '',
      filtros: ((data['filtros'] ?? const []) as List)
          .map((f) => FiltroModel.fromMap(Map<String, dynamic>.from(f)))
          .toList(),
      temFiltroTerminal: data['temFiltroTerminal'] == true,
      qtdFiltrosTerminais: data['qtdFiltrosTerminais'] is int
          ? data['qtdFiltrosTerminais']
          : int.tryParse(data['qtdFiltrosTerminais']?.toString() ?? '') ?? 0,
    );
  }
}
