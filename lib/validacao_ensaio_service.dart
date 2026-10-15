import 'ensaio_model.dart';

class ResultadoValidacaoEnsaio {
  final List<String> erros;
  final bool? conforme;

  const ResultadoValidacaoEnsaio({this.erros = const [], this.conforme});

  bool get valido => erros.isEmpty;
}

class ValidacaoEnsaioService {
  const ValidacaoEnsaioService();

  ResultadoValidacaoEnsaio validarPontos({
    required TipoEnsaio tipo,
    required Iterable<String> valoresPrincipais,
    Iterable<String> valoresSecundarios = const [],
    Map<String, dynamic> configuracao = const {},
  }) {
    final principais = valoresPrincipais.toList();
    final secundarios = valoresSecundarios.toList();
    final erros = <String>[];
    final ehTexto = tipo == TipoEnsaio.visualizacaoFluxo;
    final limiteMinimo = _numero(configuracao['criterioMin']);
    final limiteMaximo = _numero(configuracao['criterioMax']);
    final limiteMaximo5um = _numero(configuracao['criterioMax5um']);
    var conforme = (limiteMinimo != null || limiteMaximo != null || limiteMaximo5um != null) ? true : null;

    for (var indice = 0; indice < principais.length; indice++) {
      final valorPrincipal = principais[indice].trim();
      if (valorPrincipal.isEmpty) {
        erros.add('Ponto ${indice + 1}: informe o resultado.');
        continue;
      }
      if (ehTexto) continue;

      final numeroPrincipal = _numero(valorPrincipal);
      if (numeroPrincipal == null) {
        erros.add('Ponto ${indice + 1}: informe um número válido.');
        continue;
      }
      if (limiteMinimo != null && numeroPrincipal < limiteMinimo) conforme = false;
      if (limiteMaximo != null && numeroPrincipal > limiteMaximo) conforme = false;

      if (tipo == TipoEnsaio.contagemParticulas) {
        final valorSecundario = indice < secundarios.length ? secundarios[indice].trim() : '';
        if (valorSecundario.isEmpty) {
          erros.add('Ponto ${indice + 1}: informe também a leitura de 5 µm.');
          continue;
        }
        final numeroSecundario = _numero(valorSecundario);
        if (numeroSecundario == null) {
          erros.add('Ponto ${indice + 1}: informe um número válido para 5 µm.');
          continue;
        }
        if (limiteMaximo5um != null && numeroSecundario > limiteMaximo5um) conforme = false;
      }
    }

    return ResultadoValidacaoEnsaio(erros: erros, conforme: conforme);
  }

  double? _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;
    return double.tryParse(texto.replaceAll(',', '.'));
  }
}
