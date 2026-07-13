// lib/instrumento_model.dart

class InstrumentoModel {
  final String id;                // ID do documento no Firestore
  final String tipo;              // Ex: 'Manômetro' (Sua variável)
  final String tag;               // Ex: 'MAN-011' (Sua variável)
  final String numeroSerie;       // Ex: '140812' (Sua variável)
  final String numeroCertificado; // Ex: '2601-049' (Sua variável)
  final String validade;          // Ex: '01/2027' (Sua variável)
  final bool estaValido;          // Controlado via lógica de banco (Sua variável)
  final String dominioEmpresa;    // Filtro de isolamento organizacional

  static bool validadeEhValida(String validadeStr) {
    try {
      final partes = validadeStr.trim().split('/');
      if (partes.length != 2) return false;

      final mes = int.parse(partes[0]);
      final ano = int.parse(partes[1]);
      if (mes < 1 || mes > 12) return false;

      final dataLimite = DateTime(ano, mes + 1, 0, 23, 59, 59);
      final agora = DateTime.now();
      return agora.isBefore(dataLimite) || agora.isAtSameMomentAs(dataLimite);
    } catch (_) {
      return false;
    }
  }

  InstrumentoModel({
    this.id = '',
    required this.tipo,
    required this.tag,
    required this.numeroSerie,
    required this.numeroCertificado,
    required this.validade,
    required this.estaValido,
    required this.dominioEmpresa,
  });

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo,
      'tag': tag.toUpperCase().trim(),
      'numeroSerie': numeroSerie,
      'numeroCertificado': numeroCertificado,
      'validade': validade,
      'estaValido': estaValido ? 1 : 0, // Mantendo compatibilidade com seu padrão SQLite de inteiros se necessário
      'dominio_empresa': dominioEmpresa,
    };
  }

  factory InstrumentoModel.fromFirestore(Map<String, dynamic> data, String id) {
    // Garante conversão segura seja booleano ou numérico (visto no seu database_helper)
    bool valido = false;
    if (data['estaValido'] is bool) {
      valido = data['estaValido'];
    } else if (data['estaValido'] is num) {
      valido = data['estaValido'] == 1;
    }

    return InstrumentoModel(
      id: id,
      tipo: data['tipo'] ?? '',
      tag: data['tag'] ?? '',
      numeroSerie: data['numeroSerie'] ?? '',
      numeroCertificado: data['numeroCertificado'] ?? '',
      validade: data['validade'] ?? '',
      estaValido: valido,
      dominioEmpresa: data['dominio_empresa'] ?? '',
    );
  }
}