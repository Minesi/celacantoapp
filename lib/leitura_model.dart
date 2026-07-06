// lib/leitura_model.dart

class LeituraModel {
  final String equipamento; // Ex: 'Balometro', 'Manômetro'
  final String codigoFerramenta; // Ex: 'MAN-011'
  String valorCapturado; // O texto/número que o OCR extraiu do display
  DateTime dataHoraCaptura;

  LeituraModel({
    required this.equipamento,
    required this.codigoFerramenta,
    required this.valorCapturado,
    required this.dataHoraCaptura,
  });

  Map<String, dynamic> toMap() {
    return {
      'equipamento': equipamento,
      'codigoFerramenta': codigoFerramenta,
      'valorCapturado': valorCapturado,
      'dataHoraCaptura': dataHoraCaptura.toIso8601String(),
    };
  }
}