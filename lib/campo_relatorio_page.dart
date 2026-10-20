// lib/campo_relatorio_page.dart
// Fluxo de campo do técnico: executa os ensaios de um projeto já elaborado (sistema/salas/
// handling units/ensaios pré-preenchidos), registrando os resultados ponto a ponto.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'database_helper.dart';
import 'empresa_service.dart';
import 'ensaio_model.dart';
import 'execucao_ensaio_page.dart';
import 'filtro_projetos_bar.dart';
import 'handling_unit_model.dart';
import 'history_entry_model.dart';
import 'instrumento_model.dart';
import 'instrumento_service.dart';
import 'norma_calculo_service.dart';
import 'projeto_model.dart';
import 'projeto_service.dart';
import 'qr_code_scanner_page.dart';
import 'sala_model.dart';
import 'supervisor_override_dialog.dart';

bool _ehMaquinaDeFumaca(String tipo) =>
    tipo.trim().toLowerCase() == 'máquina de fumaça';

class CampoRelatorioPage extends StatefulWidget {
  final String emailLogado;
  final Future<String?> Function(BuildContext context)? capturadorFoto;

  const CampoRelatorioPage({
    super.key,
    required this.emailLogado,
    this.capturadorFoto,
  });

  @override
  State<CampoRelatorioPage> createState() => _CampoRelatorioPageState();
}

class _CampoRelatorioPageState extends State<CampoRelatorioPage> {
  final AuthService _authService = AuthService();
  final EmpresaService _empresaService = EmpresaService();
  final ProjetoService _projetoService = ProjetoService();
  final InstrumentoService _instrumentoService = InstrumentoService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NormaCalculoService _normaCalculoService = NormaCalculoService();

  bool _carregando = true;
  bool _sincronizando = false;
  (int, int) _progressoSincronizacao = (0, 0);
  List<Map<String, dynamic>> _projetos = [];
  Map<String, String> _nomeEmpresaPorCnpj = {};
  FiltroProjetos _filtro = const FiltroProjetos();

  Map<String, dynamic>? _projetoSelecionado;
  List<SalaModel> _salas = [];
  List<HandlingUnitModel> _handlingUnits = [];
  List<TipoEnsaio> _ensaiosDoProjeto = [];
  Map<String, List<InstrumentoModel>> _ferramentasEscaneadas = {};
  Map<String, int> _progressoPorChave =
      {}; // 'salaId|ensaioTipo' -> qtd de pontos já registrados

  // Regra de negócio: técnico não inicia outro ensaio enquanto um estiver incompleto sem liberação.
  String? _ensaioPendenteChave;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
  }

  String get _dominio => _authService.extrairDominio(widget.emailLogado);

  Widget _barraSincronizacao() {
    final (atual, total) = _progressoSincronizacao;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: total == 0 ? null : atual / total),
          const SizedBox(height: 4),
          Text(
            total == 0 ? 'Sincronizando projetos...' : 'Sincronizando $atual de $total projetos',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Future<void> _carregarProjetos() async {
    setState(() => _carregando = true);
    try {
      final locais = await _projetoService.listarLocais();
      if (!mounted) return;
      setState(() {
        _projetos = locais;
        _carregando = false;
        _sincronizando = true;
      });

      final empresas = await _empresaService.listarPorDominio(_dominio);
      final projetos = await _projetoService.sincronizarDominio(
        _dominio,
        onProgresso: (atual, total) {
          if (mounted) setState(() => _progressoSincronizacao = (atual, total));
        },
      );

      if (!mounted) return;
      setState(() {
        _nomeEmpresaPorCnpj = {
          for (final e in empresas)
            (e['cnpj']?.toString() ?? ''):
                (e['nomeFantasia']?.toString() ?? ''),
        };
        _projetos = projetos;
        _sincronizando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _sincronizando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar projetos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Map<String, List<InstrumentoModel>> _decodificarFerramentas(dynamic bruto) {
    final resultado = <String, List<InstrumentoModel>>{};
    Map<String, dynamic> mapa;
    if (bruto is String) {
      mapa = bruto.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(bruto));
    } else if (bruto is Map) {
      mapa = Map<String, dynamic>.from(bruto);
    } else {
      mapa = {};
    }

    mapa.forEach((tipo, instrumentos) {
      resultado[tipo] = (instrumentos as List)
          .map(
            (i) => InstrumentoModel.fromFirestore(
              Map<String, dynamic>.from(i),
              '',
            ),
          )
          .toList();
    });
    return resultado;
  }

  Future<void> _abrirProjeto(Map<String, dynamic> projeto) async {
    final projetoId = projeto['id'].toString();
    final salasBrutas = await _dbHelper.getSalasComFiltrosPorProjeto(projetoId);
    final handlingUnitsBrutas = await _dbHelper.getHandlingUnitsPorProjeto(
      projetoId,
    );
    final ensaios =
        List<String>.from(jsonDecode(projeto['ensaiosSelecionados'] ?? '[]'))
            .map(
              (nome) => TipoEnsaio.values.firstWhere(
                (t) => t.name == nome,
                orElse: () => TipoEnsaio.pressao,
              ),
            )
            .toList();

    final progresso = <String, int>{};
    for (final salaBruta in salasBrutas) {
      final salaId = salaBruta['id'].toString();
      for (final tipo in ensaios) {
        final pontos = await _dbHelper.getPontosLeituraPorSalaEEnsaio(
          salaId,
          tipo.name,
        );
        progresso['$salaId|${tipo.name}'] = pontos.length;
      }
    }

    if (!mounted) return;
    setState(() {
      // Cópia mutável: linhas do sqflite são somente leitura.
      _projetoSelecionado = Map<String, dynamic>.from(projeto);
      _salas = salasBrutas.map((s) => SalaModel.fromMap(s)).toList();
      _handlingUnits = handlingUnitsBrutas
          .map((h) => HandlingUnitModel.fromMap(h))
          .toList();
      _ensaiosDoProjeto = ensaios;
      _ferramentasEscaneadas = _decodificarFerramentas(
        projeto['ferramentasEscaneadas'],
      );
      _progressoPorChave = progresso;
      _ensaioPendenteChave = null;
    });

    if (mounted && !_ferramentasRelatorioCompletas) {
      await _abrirEtapaFerramentas();
    }
  }

  void _fecharProjeto() {
    setState(() {
      _projetoSelecionado = null;
      _salas = [];
      _handlingUnits = [];
      _ensaiosDoProjeto = [];
      _ferramentasEscaneadas = {};
      _progressoPorChave = {};
      _ensaioPendenteChave = null;
    });
  }

  int _pontosExigidos(SalaModel sala, TipoEnsaio tipo) {
    final base = _normaCalculoService.pontosExigidosParaExecucao(sala, tipo);
    final ruidoEmDoisEstados = tipo == TipoEnsaio.nivelRuido &&
        _projetoSelecionado?['tipoProjeto']?.toString() == EnsaioModel.tipoPesagem;
    return ruidoEmDoisEstados ? base * 2 : base;
  }

  bool _ensaioCompleto(SalaModel sala, TipoEnsaio tipo) {
    final chave = '${sala.id}|${tipo.name}';
    final registrados = _progressoPorChave[chave] ?? 0;
    return registrados >= _pontosExigidos(sala, tipo);
  }

  Future<void> _abrirEnsaio(SalaModel sala, TipoEnsaio tipo) async {
    final chave = '${sala.id}|${tipo.name}';
    if (_ensaioPendenteChave != null && _ensaioPendenteChave != chave) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finalize (ou solicite liberação do supervisor para) o teste pendente antes de iniciar outro.',
          ),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    final ensaio = EnsaioModel.catalogoPadrao().firstWhere(
      (e) => e.tipo == tipo,
    );
    final projetoId = _projetoSelecionado!['id'].toString();
    final execucaoId = 'EXEC-${DateTime.now().microsecondsSinceEpoch}';
    final dataInicio = DateTime.now();
    final ferramentas = _ferramentasAuditaveis(ensaio);
    await _projetoService.adicionarHistorico(
      projetoId,
      HistoryEntry(
        usuario: widget.emailLogado,
        dataHora: dataInicio,
        campo: 'execucao_inicio',
        valorAntigo: 'nao_iniciada',
        valorNovo: 'em_execucao',
        detalhes: {
          'projetoId': projetoId,
          'execucaoId': execucaoId,
          'salaId': sala.id,
          'salaNome': sala.nome,
          'ensaioTipo': tipo.name,
          'tecnicoEmail': widget.emailLogado,
          'dataInicio': dataInicio.toIso8601String(),
          'ferramentas': ferramentas,
        },
      ),
    );
    if (!mounted) return;

    final resultado = await Navigator.push<ResultadoExecucaoEnsaio>(
      context,
      MaterialPageRoute(
        builder: (_) => ExecucaoEnsaioPage(
          projetoId: projetoId,
          execucaoId: execucaoId,
          tecnicoEmail: widget.emailLogado,
          dataInicio: dataInicio,
          sala: sala,
          ensaio: ensaio,
          dominio: _dominio,
          tipoProjeto: _projetoSelecionado!['tipoProjeto']?.toString() ?? '',
          dimensoesPorPonto: _normaCalculoService.filtrosDosPontos(sala, tipo).map((f) => f?.dimensoes ?? '').toList(),
          rotulos: _normaCalculoService.rotulosDosPontos(sala, tipo),
          filtroIds: _normaCalculoService
              .filtrosDosPontos(sala, tipo)
              .map((f) => f?.id)
              .toList(),
          dbHelper: _dbHelper,
          projetoService: _projetoService,
          ferramentasJaEscaneadas: _ferramentasEscaneadas,
          capturadorFoto: widget.capturadorFoto,
        ),
      ),
    );

    final pontosSalvos = (await _dbHelper.getPontosLeituraPorSalaEEnsaio(
      sala.id,
      tipo.name,
    )).length;
    setState(() {
      _progressoPorChave[chave] = pontosSalvos;
      // Saiu sem concluir nem obter liberação: o ensaio fica pendente e bloqueia os demais.
      _ensaioPendenteChave = resultado == null && !_ensaioCompleto(sala, tipo)
          ? chave
          : null;
    });

    if (resultado == null) {
      await _projetoService.adicionarHistorico(
        projetoId,
        HistoryEntry(
          usuario: widget.emailLogado,
          dataHora: DateTime.now(),
          campo: 'execucao_fim',
          valorAntigo: 'em_execucao',
          valorNovo: 'abandonada',
          detalhes: {
            'projetoId': projetoId,
            'execucaoId': execucaoId,
            'salaId': sala.id,
            'salaNome': sala.nome,
            'ensaioTipo': tipo.name,
            'tecnicoEmail': widget.emailLogado,
            'dataInicio': dataInicio.toIso8601String(),
            'dataFim': DateTime.now().toIso8601String(),
            'ferramentas': ferramentas,
          },
        ),
      );
      return;
    }
    await _registrarConclusaoEnsaio(
      projetoId,
      sala,
      tipo,
      completo: resultado.completo,
      execucaoId: execucaoId,
      dataInicio: dataInicio,
      dataFim: resultado.dataFim,
      liberacao: resultado.liberacao,
    );
  }

  Map<String, List<String>> _ferramentasAuditaveis(EnsaioModel ensaio) => {
    for (final tipo in ensaio.ferramentasNecessarias)
      tipo: (_ferramentasEscaneadas[tipo] ?? const <InstrumentoModel>[])
          .map((instrumento) => instrumento.tag)
          .toList(),
  };

  // Registra no histórico de auditoria a conclusão (completa ou incompleta/liberada) do
  // ensaio e, quando TODOS os ensaios do projeto já estiverem completos, avança o status
  // do relatório para "em_revisao".
  Future<void> _registrarConclusaoEnsaio(
    String projetoId,
    SalaModel sala,
    TipoEnsaio tipo, {
    required bool completo,
    required String execucaoId,
    required DateTime dataInicio,
    required DateTime dataFim,
    LiberacaoSupervisor? liberacao,
  }) async {
    final statusAtual = StatusRelatorio.values.firstWhere(
      (s) => s.name == (_projetoSelecionado?['status']?.toString() ?? ''),
      orElse: () => StatusRelatorio.prontoParaCampo,
    );
    final detalhesExecucao = {
      'projetoId': projetoId,
      'execucaoId': execucaoId,
      'salaId': sala.id,
      'salaNome': sala.nome,
      'ensaioTipo': tipo.name,
      'tecnicoEmail': widget.emailLogado,
      'dataInicio': dataInicio.toIso8601String(),
      'dataFim': dataFim.toIso8601String(),
      'ferramentas': _ferramentasAuditaveis(
        EnsaioModel.catalogoPadrao().firstWhere((e) => e.tipo == tipo),
      ),
      if (liberacao != null) 'liberacao': liberacao.toMap(),
    };

    // Mantém o status atual inalterado; esta chamada só acrescenta a entrada no histórico.
    await _projetoService.registrarHistoricoEAtualizarStatus(
      projetoId,
      novoStatus: statusAtual,
      novaEntrada: HistoryEntry(
        usuario: widget.emailLogado,
        dataHora: DateTime.now(),
        campo: 'ensaio:${sala.id}:${tipo.name}',
        valorAntigo: 'pendente',
        valorNovo: completo
            ? 'completo'
            : 'encerrado incompleto (liberação de supervisor)',
        detalhes: detalhesExecucao,
      ),
    );
    await _projetoService.adicionarHistorico(
      projetoId,
      HistoryEntry(
        usuario: widget.emailLogado,
        dataHora: dataFim,
        campo: 'execucao_fim',
        valorAntigo: 'em_execucao',
        valorNovo: completo ? 'concluida' : 'encerrada_incompleta',
        detalhes: detalhesExecucao,
      ),
    );

    if (!completo) return;

    final catalogo = EnsaioModel.catalogoPadrao();
    final tudoCompleto = _salas.every((s) {
      final ensaiosDaSala = _ensaiosDoProjeto.where(
        (t) => catalogo
            .firstWhere((e) => e.tipo == t)
            .aplicavelGraus
            .contains(s.grau),
      );
      return ensaiosDaSala.every((t) => _ensaioCompleto(s, t));
    });

    if (tudoCompleto && statusAtual != StatusRelatorio.emRevisao) {
      await _projetoService.registrarHistoricoEAtualizarStatus(
        projetoId,
        novoStatus: StatusRelatorio.emRevisao,
        novaEntrada: HistoryEntry(
          usuario: widget.emailLogado,
          dataHora: DateTime.now(),
          campo: 'status',
          valorAntigo: statusAtual.name,
          valorNovo: 'em_revisao',
        ),
      );
      if (mounted && _projetoSelecionado != null) {
        setState(
          () => _projetoSelecionado!['status'] = StatusRelatorio.emRevisao.name,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _projetoSelecionado == null
              ? 'Utilização do Relatório'
              : 'Execução em Campo',
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _projetoSelecionado == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _fecharProjeto,
              ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _projetoSelecionado == null
          ? Column(
              children: [
                if (_sincronizando) _barraSincronizacao(),
                Expanded(child: _buildListaProjetos()),
              ],
            )
          : _buildExecucaoProjeto(),
    );
  }

  Widget _buildListaProjetos() {
    final projetosCampo = _projetos
        .where(
          (projeto) =>
              projeto['status']?.toString() ==
              StatusRelatorio.prontoParaCampo.name,
        )
        .toList();
    if (projetosCampo.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum relatório pronto para campo.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    final filtrados = _filtro.aplicar(projetosCampo);
    return Column(
      children: [
        FiltroProjetosBar(
          projetos: projetosCampo,
          nomeEmpresaPorCnpj: _nomeEmpresaPorCnpj,
          filtro: _filtro,
          onChanged: (f) => setState(() => _filtro = f),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _carregarProjetos,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtrados.length,
              itemBuilder: (context, index) {
                final projeto = filtrados[index];
                final data = DateTime.tryParse(
                  projeto['dataCriacao']?.toString() ?? '',
                );
                final dataTexto = data == null
                    ? '-'
                    : '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} '
                          '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
                final area = (projeto['area'] ?? '').toString();
                return Card(
                  child: ListTile(
                    title: Text(
                      _nomeEmpresaPorCnpj[projeto['cnpjEmpresa']] ??
                          projeto['cnpjEmpresa'].toString(),
                    ),
                    subtitle: Text(
                      '${projeto['tipoProjeto'] ?? '-'} · Área: ${area.isEmpty ? '-' : area} · $dataTexto',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _abrirProjeto(projeto),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<TipoEnsaio> _ensaiosAplicaveis(SalaModel sala) {
    final catalogo = EnsaioModel.catalogoPadrao();
    return _ensaiosDoProjeto
        .where(
          (tipo) => catalogo
              .firstWhere((e) => e.tipo == tipo)
              .aplicavelGraus
              .contains(sala.grau),
        )
        .toList();
  }

  /// (realizados, exigidos) somando todos os pontos de todos os ensaios de todas as salas.
  (int, int) get _contagemTestes {
    var realizados = 0;
    var exigidos = 0;
    for (final sala in _salas) {
      for (final tipo in _ensaiosAplicaveis(sala)) {
        final exigidosEnsaio = _pontosExigidos(sala, tipo);
        final registrados = _progressoPorChave['${sala.id}|${tipo.name}'] ?? 0;
        exigidos += exigidosEnsaio;
        realizados += registrados > exigidosEnsaio
            ? exigidosEnsaio
            : registrados;
      }
    }
    return (realizados, exigidos);
  }

  StatusRelatorio get _statusAtual => StatusRelatorio.values.firstWhere(
    (s) => s.name == (_projetoSelecionado?['status']?.toString() ?? ''),
    orElse: () => StatusRelatorio.prontoParaCampo,
  );

  List<String> get _ferramentasNecessariasRelatorio {
    final catalogo = EnsaioModel.catalogoPadrao();
    final tipos = <String>{};
    for (final tipoEnsaio in _ensaiosDoProjeto) {
      final ensaio = catalogo.firstWhere((ensaio) => ensaio.tipo == tipoEnsaio);
      tipos.addAll(ensaio.ferramentasNecessarias);
    }
    return tipos.toList();
  }

  bool get _ferramentasRelatorioCompletas => _ferramentasNecessariasRelatorio
      .every((tipo) => _ferramentasEscaneadas[tipo]?.isNotEmpty ?? false);

  Future<void> _abrirEtapaFerramentas() async {
    final resultado = await Navigator.push<Map<String, List<InstrumentoModel>>>(
      context,
      MaterialPageRoute(
        builder: (_) => _FerramentasRelatorioPage(
          projetoId: _projetoSelecionado!['id'].toString(),
          tecnicoEmail: widget.emailLogado,
          dominio: _dominio,
          tiposNecessarios: _ferramentasNecessariasRelatorio,
          instrumentoService: _instrumentoService,
          ferramentasIniciais: _ferramentasEscaneadas,
        ),
      ),
    );
    if (resultado == null || !mounted) return;
    final ferramentas = <String, List<InstrumentoModel>>{
      for (final entrada in resultado.entries)
        entrada.key: List<InstrumentoModel>.from(entrada.value),
    };
    setState(() => _ferramentasEscaneadas = ferramentas);
    await _projetoService.atualizarFerramentasEscaneadas(
      _projetoSelecionado!['id'].toString(),
      ferramentas,
    );
  }

  Widget _buildResumoFerramentas() {
    final tipos = _ferramentasNecessariasRelatorio;
    return Card(
      color: _ferramentasRelatorioCompletas
          ? Colors.green[50]
          : Colors.amber[50],
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ferramentas do relatório',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (tipos.isEmpty)
              const Text(
                'Os ensaios selecionados não exigem ferramentas cadastradas.',
              )
            else
              ...tipos.map((tipo) {
                final instrumentos = _ferramentasEscaneadas[tipo] ?? const [];
                return Text(
                  '$tipo: ${instrumentos.isEmpty ? 'pendente' : instrumentos.map((instrumento) => instrumento.tag).join(', ')}',
                  style: TextStyle(
                    color: instrumentos.isEmpty
                        ? Colors.red[700]
                        : Colors.green[800],
                  ),
                );
              }),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _abrirEtapaFerramentas,
              icon: const Icon(Icons.build_outlined, color: Colors.white),
              label: Text(
                _ferramentasRelatorioCompletas
                    ? 'Editar ferramentas'
                    : 'Conferir ferramentas',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  // Relatório só segue para revisão com todos os testes feitos, ou com liberação de supervisor.
  Future<void> _finalizarRelatorio() async {
    final (realizados, exigidos) = _contagemTestes;
    final faltantes = exigidos - realizados;
    final projetoId = _projetoSelecionado!['id'].toString();
    LiberacaoSupervisor? liberacao;

    if (faltantes > 0) {
      liberacao = await solicitarLiberacaoSupervisor(
        context: context,
        titulo: 'Testes Pendentes',
        mensagem:
            'Foram realizados $realizados de $exigidos testes definidos na elaboração '
            '(faltam $faltantes).\n\nInforme o código do autenticador do Supervisor para finalizar mesmo assim:',
        projetoId: projetoId,
        justificativa:
            'Finalização do relatório com $faltantes teste(s) pendente(s).',
      );
      if (liberacao == null) return;
    }

    final statusAnterior = _statusAtual;
    await _projetoService.registrarHistoricoEAtualizarStatus(
      projetoId,
      novoStatus: StatusRelatorio.emRevisao,
      novaEntrada: HistoryEntry(
        usuario: widget.emailLogado,
        dataHora: DateTime.now(),
        campo: faltantes > 0 ? 'liberacao_testes_pendentes' : 'status',
        valorAntigo: statusAnterior.name,
        valorNovo: faltantes > 0
            ? 'em_revisao ($faltantes teste(s) pendente(s) liberado(s))'
            : 'em_revisao',
        detalhes: {
          'projetoId': projetoId,
          'testesRealizados': realizados,
          'testesExigidos': exigidos,
          if (liberacao != null) 'liberacao': liberacao.toMap(),
        },
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Relatório finalizado e enviado para revisão.'),
        backgroundColor: Colors.green,
      ),
    );
    _fecharProjeto();
    await _carregarProjetos();
  }

  Widget _buildResumoProgresso() {
    final (realizados, exigidos) = _contagemTestes;
    final finalizado =
        _statusAtual == StatusRelatorio.emRevisao ||
        _statusAtual == StatusRelatorio.aprovado;
    return Card(
      color: Colors.blue[50],
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Testes realizados: $realizados de $exigidos',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: exigidos == 0 ? 0 : realizados / exigidos,
            ),
            const SizedBox(height: 12),
            if (finalizado)
              const Text(
                'Relatório já finalizado (em revisão/aprovado).',
                style: TextStyle(color: Colors.grey),
              )
            else
              ElevatedButton.icon(
                onPressed: _finalizarRelatorio,
                icon: const Icon(Icons.send_outlined, color: Colors.white),
                label: Text(
                  realizados >= exigidos
                      ? 'Finalizar Relatório'
                      : 'Finalizar Relatório (requer supervisor)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSala(SalaModel sala) {
    final catalogo = EnsaioModel.catalogoPadrao();
    final ensaiosDaSala = _ensaiosAplicaveis(sala);
    final filtros = sala.filtros.isEmpty
        ? 'sem filtros'
        : sala.filtros.map((f) => f.descricao).join(', ');
    final maquinasAdicionais = sala.handlingUnitIdsAdicionais
        .map((id) => _handlingUnits.where((h) => h.id == id).firstOrNull?.nome)
        .whereType<String>()
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sala.nome} — Grau ${sala.grau.name.toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '${sala.area} m² · ${sala.volume} m³ · Filtros: $filtros',
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (maquinasAdicionais.isNotEmpty)
              Text(
                'Também atendida por: ${maquinasAdicionais.join(', ')}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            const SizedBox(height: 12),
            if (ensaiosDaSala.isEmpty)
              const Text(
                'Nenhum ensaio aplicável a esta sala.',
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ensaiosDaSala.map((tipo) {
                  final ensaio = catalogo.firstWhere((e) => e.tipo == tipo);
                  final completo = _ensaioCompleto(sala, tipo);
                  final registrados =
                      _progressoPorChave['${sala.id}|${tipo.name}'] ?? 0;
                  return ActionChip(
                    avatar: Icon(
                      completo
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: completo ? Colors.green : Colors.grey,
                    ),
                    label: Text(
                      '${ensaio.nome} ($registrados/${_pontosExigidos(sala, tipo)})',
                    ),
                    onPressed: () => _abrirEnsaio(sala, tipo),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecucaoProjeto() {
    if (_salas.isEmpty) {
      return const Center(
        child: Text(
          'Este projeto ainda não tem salas cadastradas na elaboração.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final idsMaquinas = _handlingUnits.map((h) => h.id).toSet();
    // Cada sala é executada uma única vez, sob a máquina principal.
    final salasSemMaquina = _salas
        .where((s) => !idsMaquinas.contains(s.handlingUnitId))
        .toList();

    Widget cabecalho(String texto) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.hvac_outlined, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
    );

    if (!_ferramentasRelatorioCompletas) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildResumoFerramentas(),
          const Text(
            'Conclua a conferência das ferramentas para liberar as salas e os ensaios.',
            style: TextStyle(color: Colors.red),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildResumoFerramentas(),
        _buildResumoProgresso(),
        for (final maquina in _handlingUnits) ...[
          cabecalho('Máquina: ${maquina.nome}'),
          ..._salas
              .where((s) => s.handlingUnitId == maquina.id)
              .map(_buildCardSala),
        ],
        if (salasSemMaquina.isNotEmpty) ...[
          cabecalho('Salas sem máquina vinculada'),
          ...salasSemMaquina.map(_buildCardSala),
        ],
      ],
    );
  }
}

class _FerramentasRelatorioPage extends StatefulWidget {
  final String projetoId;
  final String tecnicoEmail;
  final String dominio;
  final List<String> tiposNecessarios;
  final InstrumentoService instrumentoService;
  final Map<String, List<InstrumentoModel>> ferramentasIniciais;

  const _FerramentasRelatorioPage({
    required this.projetoId,
    required this.tecnicoEmail,
    required this.dominio,
    required this.tiposNecessarios,
    required this.instrumentoService,
    required this.ferramentasIniciais,
  });

  @override
  State<_FerramentasRelatorioPage> createState() =>
      _FerramentasRelatorioPageState();
}

class _FerramentasRelatorioPageState extends State<_FerramentasRelatorioPage> {
  late Map<String, List<InstrumentoModel>> _instrumentosPorTipo;

  bool get _completo => widget.tiposNecessarios.every(
    (tipo) => _instrumentosPorTipo[tipo]?.isNotEmpty ?? false,
  );

  @override
  void initState() {
    super.initState();
    _instrumentosPorTipo = {
      for (final tipo in widget.tiposNecessarios)
        tipo: List<InstrumentoModel>.from(
          widget.ferramentasIniciais[tipo] ?? const [],
        ),
    };
  }

  Future<void> _escanearFerramenta(String tipo) async {
    final tag = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeScannerPage()),
    );
    if (tag == null || tag.isEmpty) return;
    await _validarEAdicionarInstrumento(tipo, tag);
  }

  Future<void> _digitarFerramentaManual(String tipo) async {
    final controller = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Digitar TAG para $tipo'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Validar'),
          ),
        ],
      ),
    );
    if (confirmado == true && controller.text.trim().isNotEmpty) {
      await _validarEAdicionarInstrumento(tipo, controller.text);
    }
  }

  Future<void> _validarEAdicionarInstrumento(
    String tipo,
    String tagBruta,
  ) async {
    final tagFormatada = tagBruta.trim().toUpperCase();
    if (_ehMaquinaDeFumaca(tipo)) {
      if (_instrumentosPorTipo.values
          .expand((instrumentos) => instrumentos)
          .any((item) => item.tag.trim().toUpperCase() == tagFormatada)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A TAG $tagFormatada já está vinculada a este relatório.',
            ),
            backgroundColor: Colors.amber,
          ),
        );
        return;
      }
      setState(
        () => _instrumentosPorTipo
            .putIfAbsent(tipo, () => [])
            .add(
              InstrumentoModel(
                tipo: tipo,
                tag: tagFormatada,
                numeroSerie: 'N/A',
                numeroCertificado: 'N/A',
                validade: 'N/A',
                estaValido: true,
                dominioEmpresa: widget.dominio,
              ),
            ),
      );
      return;
    }
    final instrumento = await widget.instrumentoService.buscarPorTag(
      tagFormatada,
      dominioPadrao: widget.dominio,
      tipoPadrao: tipo,
    );

    if (!mounted) return;
    if (instrumento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ferramenta "$tagFormatada" não encontrada.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (instrumento.tipo.trim().toLowerCase() != tipo.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A TAG $tagFormatada pertence a "${instrumento.tipo}", não a "$tipo".',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_instrumentosPorTipo.values
        .expand((instrumentos) => instrumentos)
        .any((item) => item.tag.trim().toUpperCase() == tagFormatada)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A TAG $tagFormatada já está vinculada a este relatório.',
          ),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    if (!InstrumentoModel.validadeEhValida(instrumento.validade)) {
      final liberacao = await solicitarLiberacaoSupervisor(
        context: context,
        titulo: 'Validade Expirada',
        mensagem:
            'A ferramenta ${instrumento.tag} está com a calibração vencida (${instrumento.validade}).\n\n'
            'Informe o código do autenticador do Supervisor para autorizar o uso especial:',
        projetoId: widget.projetoId,
        ferramentaTipo: tipo,
        ferramentaTag: instrumento.tag,
        justificativa:
            'Uso da ferramenta ${instrumento.tag} com calibração vencida (${instrumento.validade}).',
      );
      if (liberacao == null || !mounted) return;
      await ProjetoService().adicionarHistorico(
        widget.projetoId,
        HistoryEntry(
          usuario: widget.tecnicoEmail,
          dataHora: liberacao.dataHora,
          campo: 'liberacao_ferramenta_vencida',
          valorAntigo: 'calibracao_vencida',
          valorNovo: 'autorizada',
          detalhes: {
            'projetoId': widget.projetoId,
            'ferramentaTipo': tipo,
            'ferramentaTag': instrumento.tag,
            'liberacao': liberacao.toMap(),
          },
        ),
      );
    }

    setState(
      () => _instrumentosPorTipo.putIfAbsent(tipo, () => []).add(instrumento),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ferramentas do relatório'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Vincule cada ferramenta uma única vez antes de iniciar as salas.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (widget.tiposNecessarios.isEmpty)
            const Text(
              'Nenhuma ferramenta é necessária para os ensaios selecionados.',
            ),
          ...widget.tiposNecessarios.map((tipo) {
            final instrumentos =
                _instrumentosPorTipo[tipo] ?? const <InstrumentoModel>[];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tipo,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ler QR code',
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () => _escanearFerramenta(tipo),
                        ),
                        IconButton(
                          tooltip: 'Digitar TAG',
                          icon: const Icon(Icons.keyboard),
                          onPressed: () => _digitarFerramentaManual(tipo),
                        ),
                      ],
                    ),
                    if (_ehMaquinaDeFumaca(tipo))
                      const Text(
                        'Máquina de Fumaça: somente TAG; cadastro, calibração e validade não se aplicam.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    if (instrumentos.isEmpty)
                      const Text(
                        'Pendente',
                        style: TextStyle(color: Colors.red),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        children: instrumentos
                            .map(
                              (instrumento) => Chip(
                                avatar: const Icon(
                                  Icons.verified,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                label: Text(instrumento.tag),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _completo
                ? () => Navigator.of(context).pop(_instrumentosPorTipo)
                : null,
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
            label: const Text(
              'Continuar para as salas',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}
