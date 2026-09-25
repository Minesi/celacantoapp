// lib/preview_relatorio_widget.dart
// Mockup visual do relatório (não é o .docx real): usado no painel lateral da elaboração e na
// revisão de resultados antes da aprovação.
import 'package:flutter/material.dart';
import 'ensaio_model.dart';
import 'handling_unit_model.dart';
import 'norma_calculo_service.dart';
import 'sala_model.dart';

class PreviewRelatorioWidget extends StatelessWidget {
  final String nomeEmpresa;
  final String cnpjEmpresa;
  final String tipoProjeto;
  final String sistemaNome;
  final String area;
  final DateTime? dataHora;
  final List<HandlingUnitModel> handlingUnits;
  final List<SalaModel> salas;
  final List<TipoEnsaio> ensaios;
  final Map<String, String> resumosPorEnsaio; // TipoEnsaio.name -> resumo

  /// Pontos registrados em campo, indexados por 'salaId|TipoEnsaio.name'. Nulo = modo estrutura.
  final Map<String, List<Map<String, dynamic>>>? pontosPorChave;

  const PreviewRelatorioWidget({
    super.key,
    required this.nomeEmpresa,
    required this.cnpjEmpresa,
    required this.tipoProjeto,
    required this.sistemaNome,
    required this.area,
    this.dataHora,
    required this.handlingUnits,
    required this.salas,
    required this.ensaios,
    this.resumosPorEnsaio = const {},
    this.pontosPorChave,
  });

  static String _ou(String valor) => valor.trim().isEmpty ? '-' : valor;

  String _formatarData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RELATÓRIO DE ${_ou(tipoProjeto).toUpperCase()}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(),
          _linha('Empresa', _ou(nomeEmpresa)),
          _linha('CNPJ', _ou(cnpjEmpresa)),
          _linha('Sistema', _ou(sistemaNome)),
          _linha('Área', _ou(area)),
          _linha('Data', dataHora == null ? '-' : _formatarData(dataHora!)),
          const SizedBox(height: 16),
          _titulo('1. Máquinas e salas atendidas'),
          if (handlingUnits.isEmpty) _vazio('Nenhuma máquina cadastrada.'),
          ...handlingUnits.map(_buildMaquina),
          ..._buildSalasSemMaquina(),
          const SizedBox(height: 16),
          _titulo('2. Ensaios'),
          if (ensaios.isEmpty) _vazio('Nenhum ensaio selecionado.'),
          ...ensaios.map(_buildEnsaio),
        ],
      ),
    );
  }

  Widget _linha(String rotulo, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$rotulo: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: valor),
        ])),
      );

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
      );

  Widget _vazio(String texto) => Text(texto, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));

  Widget _celula(String texto, {bool cabecalho = false}) => Padding(
        padding: const EdgeInsets.all(4),
        child: Text(texto,
            style: TextStyle(fontSize: 12, fontWeight: cabecalho ? FontWeight.bold : FontWeight.normal)),
      );

  Widget _tabela(List<String> cabecalho, List<List<String>> linhas) {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade400),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: cabecalho.map((c) => _celula(c, cabecalho: true)).toList(),
        ),
        ...linhas.map((l) => TableRow(children: l.map(_celula).toList())),
      ],
    );
  }

  String _descreverFiltros(SalaModel s) => s.filtros.isEmpty
      ? '-'
      : s.filtros.map((f) => '${f.quantidade}× ${f.tipo.name.toUpperCase()}').join(', ');

  Widget _tabelaSalas(List<SalaModel> lista) {
    if (lista.isEmpty) return _vazio('Nenhuma sala atendida.');
    return _tabela(
      const ['Sala', 'Grau', 'Área (m²)', 'Volume (m³)', 'Filtros'],
      lista.map((s) => [s.nome, s.grau.name.toUpperCase(), '${s.area}', '${s.volume}', _descreverFiltros(s)]).toList(),
    );
  }

  Widget _buildMaquina(HandlingUnitModel h) {
    final salasDaMaquina = salas.where((s) => s.handlingUnitId == h.id).toList();
    final filtrosInternos = h.filtros.isEmpty
        ? ''
        : ' — filtros internos: ${h.filtros.map((f) => '${f.quantidade}× ${f.tipo.name.toUpperCase()}').join(', ')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${h.nome}$filtrosInternos', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          _tabelaSalas(salasDaMaquina),
        ],
      ),
    );
  }

  List<Widget> _buildSalasSemMaquina() {
    final idsMaquinas = handlingUnits.map((h) => h.id).toSet();
    final orfas = salas.where((s) => !idsMaquinas.contains(s.handlingUnitId)).toList();
    if (orfas.isEmpty) return const [];
    return [
      const Text('Salas sem máquina vinculada', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
      const SizedBox(height: 4),
      _tabelaSalas(orfas),
    ];
  }

  Widget _buildEnsaio(TipoEnsaio tipo) {
    final ensaio = EnsaioModel.catalogoPadrao().firstWhere((e) => e.tipo == tipo);
    final norma = NormaCalculoService();
    final resumo = resumosPorEnsaio[tipo.name] ?? '';
    final salasAplicaveis = salas.where((s) => ensaio.aplicavelGraus.contains(s.grau)).toList();
    final ehContagem = tipo == TipoEnsaio.contagemParticulas;

    final linhas = <List<String>>[];
    for (final sala in salasAplicaveis) {
      final rotulos = norma.rotulosDosPontos(sala, tipo);
      final pontos = pontosPorChave?['${sala.id}|${tipo.name}'] ?? const [];
      for (var i = 0; i < rotulos.length; i++) {
        final ponto = pontos.where((p) => p['numeroPonto'] == i + 1).firstOrNull;
        final valor = ponto?['valor05um']?.toString() ?? '';
        final valor5 = ponto?['valor5um']?.toString() ?? '';
        linhas.add([
          sala.nome,
          rotulos[i],
          valor.isEmpty ? '—' : valor,
          if (ehContagem) valor5.isEmpty ? '—' : valor5,
        ]);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ensaio.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          resumo.trim().isEmpty ? _vazio('Resumo do teste ainda não definido.') : Text(resumo),
          const SizedBox(height: 6),
          if (linhas.isEmpty)
            _vazio('Nenhuma sala aplicável a este ensaio.')
          else
            _tabela(
              ['Sala', 'Ponto', ehContagem ? '0,5 µm' : 'Resultado', if (ehContagem) '5 µm'],
              linhas,
            ),
        ],
      ),
    );
  }
}
