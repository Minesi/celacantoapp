abstract interface class ExecucaoDatabase {
  Future<List<Map<String, dynamic>>> getPontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo);

  Future<Map<String, dynamic>?> getResultadoEnsaio(String salaId, String ensaioTipo);

  Future<int> deletePontosLeituraPorSalaEEnsaio(String salaId, String ensaioTipo);

  Future<int> insertPontoLeitura(Map<String, dynamic> ponto);
}
