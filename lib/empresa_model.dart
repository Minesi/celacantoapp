// lib/empresa_model.dart

class EmpresaModel {
  final String dominio;       // O ID do documento no Firestore (ex: 'celacanto')
  final String razaoSocial;   // Mapeado de 'razao_social'
  final String nomeFantasia;  // Mapeado de 'nome_fantasia'
  final String cnpj;          // Mapeado de 'cnpj'
  final List<dynamic> projetosModelo; // Contêiner para escopos modelo
  final List<dynamic> projetosFinais; // Contêiner para relatórios finais

  EmpresaModel({
    required this.dominio,
    required this.razaoSocial,
    required this.nomeFantasia,
    required this.cnpj,
    this.projetosModelo = const [],
    this.projetosFinais = const [],
  });

  /// 1. Converte os dados de forma limpa para salvar no SQLite local (DatabaseHelper)
  /// Remove listas complexas para evitar o erro de SqfliteFfiException.
  Map<String, dynamic> toMap() {
    return {
      'cnpj': cnpj,
      'razaoSocial': razaoSocial,
      'nomeFantasia': nomeFantasia,
      'dominio_empresa': dominio, // Compatível com a sua coluna SQLite v5
    };
  }

  /// 2. Converte os dados mapeando exatamente para a estrutura existente na sua nuvem Firebase
  Map<String, dynamic> toFirestore() {
    return {
      'cnpj': cnpj,
      'razao_social': razaoSocial,
      'nome_fantasia': nomeFantasia,
      'dominio': dominio,
      'projetosModelo': projetosModelo,
      'projetosFinais': projetosFinais,
    };
  }

  /// 2b. Igual a toFirestore(), mas sem projetosModelo/projetosFinais — para usar com
  /// SetOptions(merge: true) em edições, sem sobrescrever as listas já existentes na nuvem.
  Map<String, dynamic> toFirestoreParcial() {
    return {
      'cnpj': cnpj,
      'razao_social': razaoSocial,
      'nome_fantasia': nomeFantasia,
      'dominio': dominio,
    };
  }

  /// 3. Reconstrói o Objeto lendo perfeitamente do Cloud Firestore
  /// Tratado para suportar tanto snake_case do Firebase quanto chaves vazias com segurança.
  factory EmpresaModel.fromFirestore(Map<String, dynamic> data, String id) {
    return EmpresaModel(
      // Lê o campo 'dominio' salvo no documento; cai para o ID apenas se ausente (docs antigos)
      dominio: data['dominio'] ?? id,
      razaoSocial: data['razao_social'] ?? data['razaoSocial'] ?? 'Sem Razão Social',
      nomeFantasia: data['nome_fantasia'] ?? data['nomeFantasia'] ?? '',
      cnpj: data['cnpj'] ?? '',
      projetosModelo: data['projetosModelo'] ?? data['projetos_modelo'] ?? const [],
      projetosFinais: data['projetosFinais'] ?? data['projetos_finais'] ?? const [],
    );
  }
}