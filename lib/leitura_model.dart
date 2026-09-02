// lib/leitura_model.dart

class LeituraModel {
  final String equipamento; // Ex: 'Balometro', 'Manômetro'
  final String codigoFerramenta; // Ex: 'MAN-011'
  final int numeroLeitura; // Índice (1-based) desta leitura dentro da mesma ferramenta (até 10)
  String valorCapturado; // O texto/número que o OCR extraiu do display
  DateTime dataHoraCaptura;

  LeituraModel({
    required this.equipamento,
    required this.codigoFerramenta,
    required this.numeroLeitura,
    required this.valorCapturado,
    required this.dataHoraCaptura,
  });

  Map<String, dynamic> toMap() {
    return {
      'equipamento': equipamento,
      'codigoFerramenta': codigoFerramenta,
      'numeroLeitura': numeroLeitura,
      'valorCapturado': valorCapturado,
      'dataHoraCaptura': dataHoraCaptura.toIso8601String(),
    };
  }
}