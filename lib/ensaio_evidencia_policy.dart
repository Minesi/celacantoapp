import 'ensaio_model.dart';

bool ensaioExigeFotoEvidencia(TipoEnsaio tipo) => const {
      TipoEnsaio.contagemParticulas,
      TipoEnsaio.visualizacaoFluxo,
      TipoEnsaio.paralelismoFluxo,
    }.contains(tipo);
