// lib/campo_relatorio_page.dart
// Fluxo de campo do técnico: executa os ensaios de um projeto já elaborado (sistema/salas/
// handling units/ensaios pré-preenchidos), registrando os resultados ponto a ponto.
import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'database_helper.dart';
import 'empresa_service.dart';
import 'ensaio_model.dart';
import 'evidencia_foto_page.dart';
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

class CampoRelatorioPage extends StatefulWidget {
  final String emailLogado;

  const CampoRelatorioPage({super.key, required this.emailLogado});

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
  List<Map<String, dynamic>> _projetos = [];
  Map<String, String> _nomeEmpresaPorCnpj = {};
  FiltroProjetos _filtro = const FiltroProjetos();

  Map<String, dynamic>? _projetoSelecionado;
  List<SalaModel> _salas = [];
  List<HandlingUnitModel> _handlingUnits = [];
  List<TipoEnsaio> _ensaiosDoProjeto = [];
  Map<String, List<InstrumentoModel>> _ferramentasEscaneadas = {};
  Map<String, int> _progressoPorChave = {}; // 'salaId|ensaioTipo' -> qtd de pontos já registrados

  // Regra de negócio: técnico não inicia outro ensaio enquanto um estiver incompleto sem liberação.
  String? _ensaioPendenteChave;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
  }

  String get _dominio => _authService.extrairDominio(widget.emailLogado);

  Future<void> _carregarProjetos() async {
    setState(() => _carregando = true);
    try {
      final empresas = await _empresaService.listarPorDominio(_dominio);
      final projetos = await _projetoService.listarPorDominio(_dominio);

      if (!mounted) return;
      setState(() {
        _nomeEmpresaPorCnpj = {
          for (final e in empresas) (e['cnpj']?.toString() ?? ''): (e['nomeFantasia']?.toString() ?? ''),
        };
        _projetos = projetos;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar projetos: $e'), backgroundColor: Colors.red),
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
          .map((i) => InstrumentoModel.fromFirestore(Map<String, dynamic>.from(i), ''))
          .toList();
    });
    return resultado;
  }

  Future<void> _abrirProjeto(Map<String, dynamic> projeto) async {
    final projetoId = projeto['id'].toString();
    final salasBrutas = await _dbHelper.getSalasComFiltrosPorProjeto(projetoId);
    final handlingUnitsBrutas = await _dbHelper.getHandlingUnitsPorProjeto(projetoId);
    final ensaios = List<String>.from(jsonDecode(projeto['ensaiosSelecionados'] ?? '[]'))
        .map((nome) => TipoEnsaio.values.firstWhere((t) => t.name == nome, orElse: () => TipoEnsaio.pressao))
        .toList();

    final progresso = <String, int>{};
    for (final salaBruta in salasBrutas) {
      final salaId = salaBruta['id'].toString();
      for (final tipo in ensaios) {
        final pontos = await _dbHelper.getPontosLeituraPorSalaEEnsaio(salaId, tipo.name);
        progresso['$salaId|${tipo.name}'] = pontos.length;
      }
    }

    if (!mounted) return;
    setState(() {
      // Cópia mutável: linhas do sqflite são somente leitura.
      _projetoSelecionado = Map<String, dynamic>.from(projeto);
      _salas = salasBrutas.map((s) => SalaModel.fromMap(s)).toList();
      _handlingUnits = handlingUnitsBrutas.map((h) => HandlingUnitModel.fromMap(h)).toList();
      _ensaiosDoProjeto = ensaios;
      _ferramentasEscaneadas = _decodificarFerramentas(projeto['ferramentasEscaneadas']);
      _progressoPorChave = progresso;
      _ensaioPendenteChave = null;
    });
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

  int _pontosExigidos(SalaModel sala, TipoEnsaio tipo) => _normaCalculoService.pontosExigidos(sala, tipo);

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
          content: Text('Finalize (ou solicite liberação do supervisor para) o teste pendente antes de iniciar outro.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    final ensaio = EnsaioModel.catalogoPadrao().firstWhere((e) => e.tipo == tipo);
    final projetoId = _projetoSelecionado!['id'].toString();

    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _ExecucaoEnsaioPage(
          projetoId: projetoId,
          sala: sala,
          ensaio: ensaio,
          dominio: _dominio,
          rotulos: _normaCalculoService.rotulosDosPontos(sala, tipo),
          filtroIds: _normaCalculoService.filtrosDosPontos(sala, tipo).map((f) => f?.id).toList(),
          instrumentoService: _instrumentoService,
          dbHelper: _dbHelper,
          ferramentasJaEscaneadas: _ferramentasEscaneadas,
        ),
      ),
    );

    final pontosSalvos = (await _dbHelper.getPontosLeituraPorSalaEEnsaio(sala.id, tipo.name)).length;
    setState(() {
      _progressoPorChave[chave] = pontosSalvos;
      // Saiu sem concluir nem obter liberação: o ensaio fica pendente e bloqueia os demais.
      _ensaioPendenteChave = resultado == null && !_ensaioCompleto(sala, tipo) ? chave : null;
    });

    if (resultado == null) return;
    await _registrarConclusaoEnsaio(projetoId, sala, tipo, completo: resultado);
  }

  // Registra no histórico de auditoria a conclusão (completa ou incompleta/liberada) do
  // ensaio e, quando TODOS os ensaios do projeto já estiverem completos, avança o status
  // do relatório para "em_revisao".
  Future<void> _registrarConclusaoEnsaio(String projetoId, SalaModel sala, TipoEnsaio tipo, {required bool completo}) async {
    final statusAtual = StatusRelatorio.values.firstWhere(
      (s) => s.name == (_projetoSelecionado?['status']?.toString() ?? ''),
      orElse: () => StatusRelatorio.prontoParaCampo,
    );

    // Mantém o status atual inalterado; esta chamada só acrescenta a entrada no histórico.
    await _projetoService.registrarHistoricoEAtualizarStatus(
      projetoId,
      novoStatus: statusAtual,
      novaEntrada: HistoryEntry(
        usuario: widget.emailLogado,
        dataHora: DateTime.now(),
        campo: 'ensaio:${sala.id}:${tipo.name}',
        valorAntigo: 'pendente',
        valorNovo: completo ? 'completo' : 'encerrado incompleto (liberação de supervisor)',
      ),
    );

    if (!completo) return;

    final catalogo = EnsaioModel.catalogoPadrao();
    final tudoCompleto = _salas.every((s) {
      final ensaiosDaSala = _ensaiosDoProjeto.where((t) => catalogo.firstWhere((e) => e.tipo == t).aplicavelGraus.contains(s.grau));
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
      if (_projetoSelecionado != null) {
        _projetoSelecionado!['status'] = StatusRelatorio.emRevisao.name;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_projetoSelecionado == null ? 'Utilização do Relatório' : 'Execução em Campo'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _projetoSelecionado == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _fecharProjeto),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _projetoSelecionado == null
              ? _buildListaProjetos()
              : _buildExecucaoProjeto(),
    );
  }

  Widget _buildListaProjetos() {
    if (_projetos.isEmpty) {
      return const Center(child: Text('Nenhum relatório elaborado ainda.', style: TextStyle(color: Colors.grey)));
    }
    final filtrados = _filtro.aplicar(_projetos);
    return Column(
      children: [
        FiltroProjetosBar(
          projetos: _projetos,
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
                final data = DateTime.tryParse(projeto['dataCriacao']?.toString() ?? '');
                final dataTexto = data == null
                    ? '-'
                    : '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} '
                        '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
                final area = (projeto['area'] ?? '').toString();
                return Card(
                  child: ListTile(
                    title: Text(_nomeEmpresaPorCnpj[projeto['cnpjEmpresa']] ?? projeto['cnpjEmpresa'].toString()),
                    subtitle: Text('${projeto['tipoProjeto'] ?? '-'} · Área: ${area.isEmpty ? '-' : area} · $dataTexto'),
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
        .where((tipo) => catalogo.firstWhere((e) => e.tipo == tipo).aplicavelGraus.contains(sala.grau))
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
        realizados += registrados > exigidosEnsaio ? exigidosEnsaio : registrados;
      }
    }
    return (realizados, exigidos);
  }

  StatusRelatorio get _statusAtual => StatusRelatorio.values.firstWhere(
        (s) => s.name == (_projetoSelecionado?['status']?.toString() ?? ''),
        orElse: () => StatusRelatorio.prontoParaCampo,
      );

  // Relatório só segue para revisão com todos os testes feitos, ou com liberação de supervisor.
  Future<void> _finalizarRelatorio() async {
    final (realizados, exigidos) = _contagemTestes;
    final faltantes = exigidos - realizados;

    if (faltantes > 0) {
      final autorizado = await solicitarLiberacaoSupervisor(
        context: context,
        titulo: 'Testes Pendentes',
        mensagem: 'Foram realizados $realizados de $exigidos testes definidos na elaboração '
            '(faltam $faltantes).\n\nInsira as credenciais de um Supervisor para finalizar mesmo assim:',
      );
      if (!autorizado) return;
    }

    final projetoId = _projetoSelecionado!['id'].toString();
    final statusAnterior = _statusAtual;
    await _projetoService.registrarHistoricoEAtualizarStatus(
      projetoId,
      novoStatus: StatusRelatorio.emRevisao,
      novaEntrada: HistoryEntry(
        usuario: widget.emailLogado,
        dataHora: DateTime.now(),
        campo: faltantes > 0 ? 'liberacao_testes_pendentes' : 'status',
        valorAntigo: statusAnterior.name,
        valorNovo: faltantes > 0 ? 'em_revisao ($faltantes teste(s) pendente(s) liberado(s))' : 'em_revisao',
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relatório finalizado e enviado para revisão.'), backgroundColor: Colors.green),
    );
    _fecharProjeto();
    await _carregarProjetos();
  }

  Widget _buildResumoProgresso() {
    final (realizados, exigidos) = _contagemTestes;
    final finalizado = _statusAtual == StatusRelatorio.emRevisao || _statusAtual == StatusRelatorio.aprovado;
    return Card(
      color: Colors.blue[50],
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Testes realizados: $realizados de $exigidos',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: exigidos == 0 ? 0 : realizados / exigidos),
            const SizedBox(height: 12),
            if (finalizado)
              const Text('Relatório já finalizado (em revisão/aprovado).', style: TextStyle(color: Colors.grey))
            else
              ElevatedButton.icon(
                onPressed: _finalizarRelatorio,
                icon: const Icon(Icons.send_outlined, color: Colors.white),
                label: Text(
                  realizados >= exigidos ? 'Finalizar Relatório' : 'Finalizar Relatório (requer supervisor)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        : sala.filtros.map((f) => '${f.quantidade}× ${f.tipo.name.toUpperCase()}').join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${sala.nome} — Grau ${sala.grau.name.toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${sala.area} m² · ${sala.volume} m³ · Filtros: $filtros', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            if (ensaiosDaSala.isEmpty)
              const Text('Nenhum ensaio aplicável a esta sala.', style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ensaiosDaSala.map((tipo) {
                  final ensaio = catalogo.firstWhere((e) => e.tipo == tipo);
                  final completo = _ensaioCompleto(sala, tipo);
                  final registrados = _progressoPorChave['${sala.id}|${tipo.name}'] ?? 0;
                  return ActionChip(
                    avatar: Icon(
                      completo ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 18,
                      color: completo ? Colors.green : Colors.grey,
                    ),
                    label: Text('${ensaio.nome} ($registrados/${_pontosExigidos(sala, tipo)})'),
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
      return const Center(child: Text('Este projeto ainda não tem salas cadastradas na elaboração.', style: TextStyle(color: Colors.grey)));
    }

    final idsMaquinas = _handlingUnits.map((h) => h.id).toSet();
    final salasSemMaquina = _salas.where((s) => !idsMaquinas.contains(s.handlingUnitId)).toList();

    Widget cabecalho(String texto) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.hvac_outlined, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildResumoProgresso(),
        for (final maquina in _handlingUnits) ...[
          cabecalho('Máquina: ${maquina.nome}'),
          ..._salas.where((s) => s.handlingUnitId == maquina.id).map(_buildCardSala),
        ],
        if (salasSemMaquina.isNotEmpty) ...[
          cabecalho('Salas sem máquina vinculada'),
          ...salasSemMaquina.map(_buildCardSala),
        ],
      ],
    );
  }
}

class _ExecucaoEnsaioPage extends StatefulWidget {
  final String projetoId;
  final SalaModel sala;
  final EnsaioModel ensaio;
  final String dominio;
  final List<String> rotulos; // Um rótulo por ponto exigido
  final List<String?> filtroIds; // Filtro (saída) de cada ponto, quando o ensaio é por filtro
  final InstrumentoService instrumentoService;
  final DatabaseHelper dbHelper;
  final Map<String, List<InstrumentoModel>> ferramentasJaEscaneadas;

  const _ExecucaoEnsaioPage({
    required this.projetoId,
    required this.sala,
    required this.ensaio,
    required this.dominio,
    required this.rotulos,
    required this.filtroIds,
    required this.instrumentoService,
    required this.dbHelper,
    required this.ferramentasJaEscaneadas,
  });

  @override
  State<_ExecucaoEnsaioPage> createState() => _ExecucaoEnsaioPageState();
}

class _ExecucaoEnsaioPageState extends State<_ExecucaoEnsaioPage> {
  late Map<String, List<InstrumentoModel>> _instrumentosPorTipo;
  late List<TextEditingController> _controllersPrincipais;
  late List<TextEditingController> _controllersSecundarios; // usado só para 0,5µm/5µm
  String? _fotoEvidenciaUrl;
  bool _salvando = false;

  bool get _ehContagemParticulas => widget.ensaio.tipo == TipoEnsaio.contagemParticulas;
  bool get _ehRecuperacaoOuEnergia =>
      widget.ensaio.tipo == TipoEnsaio.recuperacaoParticulas || widget.ensaio.tipo == TipoEnsaio.quedaEnergia;
  bool get _permiteValorNegativo => widget.ensaio.tipo == TipoEnsaio.pressao;

  @override
  void initState() {
    super.initState();
    _instrumentosPorTipo = {
      for (final entry in widget.ferramentasJaEscaneadas.entries) entry.key: List<InstrumentoModel>.from(entry.value),
    };
    _controllersPrincipais = List.generate(widget.rotulos.length, (_) => TextEditingController());
    _controllersSecundarios =
        _ehContagemParticulas ? List.generate(widget.rotulos.length, (_) => TextEditingController()) : [];
    _carregarPontosExistentes();
  }

  Future<void> _carregarPontosExistentes() async {
    final pontos = await widget.dbHelper.getPontosLeituraPorSalaEEnsaio(widget.sala.id, widget.ensaio.tipo.name);
    if (!mounted || pontos.isEmpty) return;
    setState(() {
      for (final ponto in pontos) {
        final indice = (ponto['numeroPonto'] as int) - 1;
        if (indice < 0 || indice >= _controllersPrincipais.length) continue;
        _controllersPrincipais[indice].text = ponto['valor05um']?.toString() ?? '';
        if (_ehContagemParticulas && indice < _controllersSecundarios.length) {
          _controllersSecundarios[indice].text = ponto['valor5um']?.toString() ?? '';
        }
        final foto = ponto['fotoEvidenciaUrl']?.toString() ?? '';
        if (foto.isNotEmpty) _fotoEvidenciaUrl = foto;
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllersPrincipais) {
      c.dispose();
    }
    for (final c in _controllersSecundarios) {
      c.dispose();
    }
    super.dispose();
  }

  String _rotuloDoIndice(int index) => widget.rotulos[index];

  Future<void> _escanearFerramenta(String tipo) async {
    final tag = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrCodeScannerPage()));
    if (tag == null || tag.isEmpty) return;
    await _validarEAdicionarInstrumento(tipo, tag);
  }

  Future<void> _digitarFerramentaManual(String tipo) async {
    final controller = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Digitar TAG para $tipo'),
        content: TextField(controller: controller, textCapitalization: TextCapitalization.characters),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Validar')),
        ],
      ),
    );
    if (confirmado == true && controller.text.trim().isNotEmpty) {
      await _validarEAdicionarInstrumento(tipo, controller.text);
    }
  }

  Future<void> _validarEAdicionarInstrumento(String tipo, String tagBruta) async {
    final tagFormatada = tagBruta.trim().toUpperCase();
    final instrumento =
        await widget.instrumentoService.buscarPorTag(tagFormatada, dominioPadrao: widget.dominio, tipoPadrao: tipo);

    if (!mounted) return;
    if (instrumento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ferramenta "$tagFormatada" não encontrada.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!InstrumentoModel.validadeEhValida(instrumento.validade)) {
      final autorizado = await solicitarLiberacaoSupervisor(
        context: context,
        titulo: 'Validade Expirada',
        mensagem: 'A ferramenta ${instrumento.tag} está com a calibração vencida (${instrumento.validade}).\n\n'
            'Insira as credenciais de um Supervisor para autorizar o uso especial:',
      );
      if (!autorizado) return;
    }

    if (!mounted) return;
    setState(() {
      _instrumentosPorTipo.putIfAbsent(tipo, () => []).add(instrumento);
    });
  }

  Future<void> _anexarFotoEvidencia() async {
    final path = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const EvidenciaFotoPage()));
    if (path == null) return;

    var urlFinal = 'local://$path';
    try {
      final ref = FirebaseStorage.instance.ref(
        'evidencias/${widget.projetoId}/${widget.sala.id}/${widget.ensaio.tipo.name}/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ref.putFile(File(path));
      urlFinal = await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Evidência salva apenas localmente (offline?): $e');
    }

    if (!mounted) return;
    setState(() => _fotoEvidenciaUrl = urlFinal);
  }

  bool get _todosCamposPreenchidos {
    final principaisOk = _controllersPrincipais.every((c) => c.text.trim().isNotEmpty);
    final secundariosOk = !_ehContagemParticulas || _controllersSecundarios.every((c) => c.text.trim().isNotEmpty);
    final fotoOk = !_ehContagemParticulas || (_fotoEvidenciaUrl != null && _fotoEvidenciaUrl!.isNotEmpty);
    final ferramentasOk =
        widget.ensaio.ferramentasNecessarias.every((tipo) => (_instrumentosPorTipo[tipo]?.isNotEmpty ?? false));
    return principaisOk && secundariosOk && fotoOk && ferramentasOk;
  }

  Future<void> _persistirPontos() async {
    await widget.dbHelper.deletePontosLeituraPorSalaEEnsaio(widget.sala.id, widget.ensaio.tipo.name);
    for (var i = 0; i < _controllersPrincipais.length; i++) {
      await widget.dbHelper.insertPontoLeitura({
        // ID determinístico: o merge com o Firestore não pode gerar duplicatas do mesmo ponto.
        'id': 'PONTO-${widget.sala.id}-${widget.ensaio.tipo.name}-$i',
        'projetoId': widget.projetoId,
        'salaId': widget.sala.id,
        'ensaioTipo': widget.ensaio.tipo.name,
        'numeroPonto': i + 1,
        'filtroId': i < widget.filtroIds.length ? (widget.filtroIds[i] ?? '') : '',
        'valor05um': _controllersPrincipais[i].text.trim(),
        'valor5um': _ehContagemParticulas ? _controllersSecundarios[i].text.trim() : '',
        'fotoEvidenciaUrl': _fotoEvidenciaUrl ?? '',
        'dataHoraCaptura': DateTime.now().toIso8601String(),
      });
    }
    await ProjetoService().atualizarFerramentasEscaneadas(widget.projetoId, _instrumentosPorTipo);
    await ProjetoService().sincronizarPontosLeitura(widget.projetoId);
  }

  Future<void> _concluirEnsaio() async {
    if (!_todosCamposPreenchidos || _salvando) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os pontos, escaneie as ferramentas e (se exigido) anexe a foto de evidência.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    await _persistirPontos();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _encerrarIncompleto() async {
    final autorizado = await solicitarLiberacaoSupervisor(
      context: context,
      titulo: 'Teste Incompleto',
      mensagem: 'Nem todos os pontos de "${widget.ensaio.nome}" em "${widget.sala.nome}" foram preenchidos.\n\n'
          'Insira as credenciais de um Supervisor para encerrar mesmo assim:',
    );
    if (!autorizado) return;

    setState(() => _salvando = true);
    await _persistirPontos();

    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.sala.nome} — ${widget.ensaio.nome}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_ehRecuperacaoOuEnergia)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)),
                child: const Text('⏱ O tempo de recuperação não pode ultrapassar 15 minutos.',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 16),
            const Text('Ferramentas Necessárias', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ...widget.ensaio.ferramentasNecessarias.map((tipo) {
              final instrumentos = _instrumentosPorTipo[tipo] ?? const [];
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(tipo, style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () => _escanearFerramenta(tipo)),
                        IconButton(icon: const Icon(Icons.keyboard), onPressed: () => _digitarFerramentaManual(tipo)),
                      ],
                    ),
                    if (instrumentos.isEmpty)
                      const Text('Nenhum instrumento vinculado ainda.', style: TextStyle(color: Colors.grey))
                    else
                      Wrap(spacing: 8, children: instrumentos.map((i) => Chip(label: Text(i.tag))).toList()),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            Text(_ehContagemParticulas ? 'Leituras (0,5 µm / 5 µm)' : 'Resultados',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ...List.generate(_controllersPrincipais.length, (i) {
              if (_ehContagemParticulas) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controllersPrincipais[i],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: '${_rotuloDoIndice(i)} — 0,5µm'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controllersSecundarios[i],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: '5µm'),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _controllersPrincipais[i],
                  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: _permiteValorNegativo),
                  decoration: InputDecoration(
                    labelText: _rotuloDoIndice(i),
                    helperText: _permiteValorNegativo ? 'Use valor negativo se o fluxo estiver invertido' : null,
                  ),
                ),
              );
            }),
            if (_ehContagemParticulas) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _anexarFotoEvidencia,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(_fotoEvidenciaUrl == null ? 'Anexar Foto da Fita' : 'Foto Anexada ✓'),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _salvando ? null : _concluirEnsaio,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Concluir Ensaio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _salvando ? null : _encerrarIncompleto,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Encerrar Incompleto (requer supervisor)'),
            ),
          ],
        ),
      ),
    );
  }
}
