class ResultadoEnsaioModel {
  final String id;
  final String projetoId;
  final String salaId;
  final String ensaioTipo;
  final bool? conforme;
  final String observacoes;
  final String tecnicoEmail;
  final DateTime dataHora;
  final Map<String, dynamic> dados;

  const ResultadoEnsaioModel({
    required this.id,
    required this.projetoId,
    required this.salaId,
    required this.ensaioTipo,
    required this.conforme,
    required this.observacoes,
    required this.tecnicoEmail,
    required this.dataHora,
    required this.dados,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'projetoId': projetoId,
        'salaId': salaId,
        'ensaioTipo': ensaioTipo,
        'conforme': conforme,
        'observacoes': observacoes,
        'tecnicoEmail': tecnicoEmail,
        'dataHora': dataHora.toIso8601String(),
        'dados': dados,
      };

  factory ResultadoEnsaioModel.fromMap(Map<String, dynamic> data) {
    final conformeBruto = data['conforme'];
    return ResultadoEnsaioModel(
      id: data['id']?.toString() ?? '',
      projetoId: data['projetoId']?.toString() ?? '',
      salaId: data['salaId']?.toString() ?? '',
      ensaioTipo: data['ensaioTipo']?.toString() ?? '',
      conforme: conformeBruto is bool
          ? conformeBruto
          : conformeBruto is num
              ? conformeBruto == 1
              : conformeBruto == null
                  ? null
                  : conformeBruto.toString().toLowerCase() == 'true',
      observacoes: data['observacoes']?.toString() ?? '',
      tecnicoEmail: data['tecnicoEmail']?.toString() ?? '',
      dataHora: DateTime.tryParse(data['dataHora']?.toString() ?? '') ?? DateTime.now(),
      dados: data['dados'] is Map ? Map<String, dynamic>.from(data['dados']) : const {},
    );
  }
}
