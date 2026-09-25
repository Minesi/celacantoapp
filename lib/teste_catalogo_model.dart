// lib/teste_catalogo_model.dart
// Associa um tipo de teste (TipoEnsaio.name) ao seu resumo e à configuração da tabela de resultados.
class TesteCatalogoModel {
  final String tipoEnsaio;
  final String dominioEmpresa;
  final String resumo;
  final String tabelaConfig; // JSON da estrutura da tabela; vazio até ser definido
  final DateTime? atualizadoEm;

  TesteCatalogoModel({
    required this.tipoEnsaio,
    required this.dominioEmpresa,
    this.resumo = '',
    this.tabelaConfig = '',
    this.atualizadoEm,
  });

  String get id => '${dominioEmpresa}_$tipoEnsaio';

  TesteCatalogoModel copyWith({String? resumo, String? tabelaConfig, DateTime? atualizadoEm}) {
    return TesteCatalogoModel(
      tipoEnsaio: tipoEnsaio,
      dominioEmpresa: dominioEmpresa,
      resumo: resumo ?? this.resumo,
      tabelaConfig: tabelaConfig ?? this.tabelaConfig,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipoEnsaio': tipoEnsaio,
      'dominio_empresa': dominioEmpresa,
      'resumo': resumo,
      'tabelaConfig': tabelaConfig,
      'atualizadoEm': atualizadoEm?.toIso8601String() ?? '',
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tipoEnsaio': tipoEnsaio,
      'dominio': dominioEmpresa,
      'resumo': resumo,
      'tabelaConfig': tabelaConfig,
      'atualizadoEm': atualizadoEm?.toIso8601String() ?? '',
    };
  }

  factory TesteCatalogoModel.fromMap(Map<String, dynamic> data) {
    return TesteCatalogoModel(
      tipoEnsaio: data['tipoEnsaio']?.toString() ?? '',
      dominioEmpresa: (data['dominio_empresa'] ?? data['dominio'])?.toString() ?? '',
      resumo: data['resumo']?.toString() ?? '',
      tabelaConfig: data['tabelaConfig']?.toString() ?? '',
      atualizadoEm: DateTime.tryParse(data['atualizadoEm']?.toString() ?? ''),
    );
  }
}
