// lib/empresa_model.dart

class EmpresaModel {
  final String razaoSocial;
  final String nomeFantasia;
  final String cnpj;

  EmpresaModel({
    required this.razaoSocial,
    required this.nomeFantasia,
    required this.cnpj,
  });

  // Converte o Objeto para um Mapa (Essencial para salvar em Bancos SQL/NoSQL futuramente)
  Map<String, dynamic> toMap() {
    return {
      'razao_social': razaoSocial,
      'nome_fantasia': nomeFantasia,
      'cnpj': cnpj,
    };
  }

  // Cria um Objeto a partir de um Mapa (Essencial para puxar do Banco de Dados)
  factory EmpresaModel.fromMap(Map<String, dynamic> map) {
    return EmpresaModel(
      razaoSocial: map['razao_social'] ?? '',
      nomeFantasia: map['nome_fantasia'] ?? '',
      cnpj: map['cnpj'] ?? '',
    );
  }
}