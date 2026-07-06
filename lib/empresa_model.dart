// lib/empresa_model.dart

class EmpresaModel {
  final String dominio;       // O ID do documento (ex: 'celacanto.com')
  final String razaoSocial;   // Mantendo sua variável original
  final String nomeFantasia;  // Mantendo sua variável original
  final String cnpj;          // Mantendo sua variável original
  final List<dynamic> projetosModelo; // Novo contêiner para escopos modelo
  final List<dynamic> projetosFinais; // Novo contêiner para relatórios finais

  EmpresaModel({
    required this.dominio,
    required this.razaoSocial,
    required this.nomeFantasia,
    required this.cnpj,
    this.projetosModelo = const [],
    this.projetosFinais = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'razaoSocial': razaoSocial,
      'nomeFantasia': nomeFantasia,
      'cnpj': cnpj,
      'projetos_modelo': projetosModelo,
      'projetos_finais': projetosFinais,
    };
  }

  factory EmpresaModel.fromFirestore(Map<String, dynamic> data, String id) {
    return EmpresaModel(
      dominio: id,
      razaoSocial: data['razaoSocial'] ?? 'Sem Razão Social',
      nomeFantasia: data['nomeFantasia'] ?? '',
      cnpj: data['cnpj'] ?? '',
      projetosModelo: data['projetos_modelo'] ?? [],
      projetosFinais: data['projetos_finais'] ?? [],
    );
  }
}