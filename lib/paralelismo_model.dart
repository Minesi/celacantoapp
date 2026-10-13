// lib/paralelismo_model.dart
// Registro de campo do teste de paralelismo do fluxo de ar (resultado + foto opcional).
class RegistroParalelismo {
  final String resultado;
  final String fotoUrl;
  final String registradoPor;
  final DateTime? dataHora;

  const RegistroParalelismo({
    this.resultado = '',
    this.fotoUrl = '',
    this.registradoPor = '',
    this.dataHora,
  });

  bool get vazio => resultado.trim().isEmpty && fotoUrl.isEmpty;

  Map<String, dynamic> toMap() => {
        'resultado': resultado,
        'fotoUrl': fotoUrl,
        'registradoPor': registradoPor,
        'dataHora': dataHora?.toIso8601String() ?? '',
      };

  factory RegistroParalelismo.fromMap(Map<String, dynamic> data) => RegistroParalelismo(
        resultado: data['resultado']?.toString() ?? '',
        fotoUrl: data['fotoUrl']?.toString() ?? '',
        registradoPor: data['registradoPor']?.toString() ?? '',
        dataHora: DateTime.tryParse(data['dataHora']?.toString() ?? ''),
      );
}
