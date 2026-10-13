import 'instrumento_model.dart';
import 'resultado_ensaio_model.dart';

abstract interface class ExecucaoProjetoService {
  Future<void> salvarResultadoEnsaio(ResultadoEnsaioModel resultado);

  Future<void> atualizarFerramentasEscaneadas(String projetoId, Map<String, List<InstrumentoModel>> ferramentas);

  Future<void> sincronizarPontosLeitura(String projetoId);
}
