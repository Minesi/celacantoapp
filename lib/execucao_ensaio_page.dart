import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ensaio_evidencia_policy.dart';
import 'ensaio_model.dart';
import 'execucao_database.dart';
import 'execucao_projeto_service.dart';
import 'evidencia_foto_page.dart';
import 'instrumento_model.dart';
import 'resultado_ensaio_model.dart';
import 'sala_model.dart';
import 'storage_upload_client.dart';
import 'supervisor_override_dialog.dart';
import 'validacao_ensaio_service.dart';

typedef CapturadorFotoEvidencia = Future<String?> Function(BuildContext context);

const _estadosContagem = ['repouso', 'operacao'];

class ResultadoExecucaoEnsaio {
  final bool completo;
  final LiberacaoSupervisor? liberacao;
  final DateTime dataFim;

  const ResultadoExecucaoEnsaio({required this.completo, required this.dataFim, this.liberacao});
}

class ExecucaoEnsaioPage extends StatefulWidget {
  final String projetoId;
  final String execucaoId;
  final String tecnicoEmail;
  final DateTime dataInicio;
  final SalaModel sala;
  final EnsaioModel ensaio;
  final String dominio;
  final List<String> rotulos;
  final List<String?> filtroIds;
  final ExecucaoDatabase dbHelper;
  final ExecucaoProjetoService projetoService;
  final Map<String, List<InstrumentoModel>> ferramentasJaEscaneadas;
  final CapturadorFotoEvidencia? capturadorFoto;

  const ExecucaoEnsaioPage({
    super.key,
    required this.projetoId,
    required this.execucaoId,
    required this.tecnicoEmail,
    required this.dataInicio,
    required this.sala,
    required this.ensaio,
    required this.dominio,
    required this.rotulos,
    required this.filtroIds,
    required this.dbHelper,
    required this.projetoService,
    required this.ferramentasJaEscaneadas,
    this.capturadorFoto,
  });

  @override
  State<ExecucaoEnsaioPage> createState() => _ExecucaoEnsaioPageState();
}

class _ExecucaoEnsaioPageState extends State<ExecucaoEnsaioPage> {
  late Map<String, List<InstrumentoModel>> _instrumentosPorTipo;
  late Map<String, List<TextEditingController>> _contagemPrincipaisPorEstado;
  late Map<String, List<TextEditingController>> _contagemSecundariosPorEstado;
  late List<TextEditingController> _controllersPrincipais;
  late List<TextEditingController> _controllersSecundarios;
  late TextEditingController _observacoesController;
  late TextEditingController _frequenciaController;
  late TextEditingController _concentracaoController;
  late TextEditingController _vazaoCriterioController;
  late TextEditingController _lxController;
  bool? _conforme;
  String _estadoContagem = 'repouso';
  String? _fotoEvidenciaUrl;
  bool _salvando = false;

  bool get _ehContagemParticulas => widget.ensaio.tipo == TipoEnsaio.contagemParticulas;
  bool get _exigeFotoEvidencia => ensaioExigeFotoEvidencia(widget.ensaio.tipo);
  bool get _ehRecuperacaoOuEnergia =>
      widget.ensaio.tipo == TipoEnsaio.recuperacaoParticulas || widget.ensaio.tipo == TipoEnsaio.quedaEnergia;
  bool get _permiteValorNegativo => widget.ensaio.tipo == TipoEnsaio.pressao;
  bool get _resultadoTextual => widget.ensaio.tipo == TipoEnsaio.visualizacaoFluxo;

  @override
  void initState() {
    super.initState();
    _instrumentosPorTipo = {
      for (final entry in widget.ferramentasJaEscaneadas.entries) entry.key: List<InstrumentoModel>.from(entry.value),
    };
    _contagemPrincipaisPorEstado = _ehContagemParticulas
        ? {
            for (final estado in _estadosContagem)
              estado: List.generate(widget.rotulos.length, (_) => TextEditingController()),
          }
        : {};
    _contagemSecundariosPorEstado = _ehContagemParticulas
        ? {
            for (final estado in _estadosContagem)
              estado: List.generate(widget.rotulos.length, (_) => TextEditingController()),
          }
        : {};
    _controllersPrincipais = _ehContagemParticulas
        ? _contagemPrincipaisPorEstado[_estadoContagem]!
        : List.generate(widget.rotulos.length, (_) => TextEditingController());
    _controllersSecundarios = _ehContagemParticulas
        ? _contagemSecundariosPorEstado[_estadoContagem]!
        : [];
    _observacoesController = TextEditingController();
    _frequenciaController = TextEditingController();
    _concentracaoController = TextEditingController();
    _vazaoCriterioController = TextEditingController();
    _lxController = TextEditingController();
    _carregarPontosExistentes();
    _carregarResultadoExistente();
  }

  Future<void> _carregarPontosExistentes() async {
    final pontos = await widget.dbHelper.getPontosLeituraPorSalaEEnsaio(widget.sala.id, widget.ensaio.tipo.name);
    if (!mounted || pontos.isEmpty) return;
    setState(() {
      for (final ponto in pontos) {
        final indice = (int.tryParse(ponto['numeroPonto']?.toString() ?? '') ?? 0) - 1;
        if (indice < 0 || indice >= _controllersPrincipais.length) continue;
        final estado = _ehContagemParticulas ? _normalizarEstado(ponto['estado']) : _estadoContagem;
        final principais = _ehContagemParticulas ? _contagemPrincipaisPorEstado[estado]! : _controllersPrincipais;
        final secundarios = _ehContagemParticulas ? _contagemSecundariosPorEstado[estado]! : _controllersSecundarios;
        if (indice >= principais.length) continue;
        principais[indice].text = ponto['valor05um']?.toString() ?? '';
        if (_ehContagemParticulas && indice < secundarios.length) {
          secundarios[indice].text = ponto['valor5um']?.toString() ?? '';
        }
        final foto = ponto['fotoEvidenciaUrl']?.toString() ?? '';
        if (foto.isNotEmpty) _fotoEvidenciaUrl = foto;
      }
    });
  }

  Future<void> _carregarResultadoExistente() async {
    final resultado = await widget.dbHelper.getResultadoEnsaio(widget.sala.id, widget.ensaio.tipo.name);
    if (!mounted || resultado == null) return;
    final dados = resultado['dados'] is Map ? Map<String, dynamic>.from(resultado['dados']) : const <String, dynamic>{};
    setState(() {
      if (resultado['conforme'] is bool) _conforme = resultado['conforme'] as bool;
      _observacoesController.text = resultado['observacoes']?.toString() ?? '';
      _frequenciaController.text = dados['frequencia']?.toString() ?? '';
      _concentracaoController.text = dados['concentracao']?.toString() ?? '';
      _vazaoCriterioController.text = dados['vazaoCriterio']?.toString() ?? '';
      _lxController.text = dados['lx']?.toString() ?? '';
      if (_ehContagemParticulas) {
        _estadoContagem = _normalizarEstado(dados['estado']);
        _controllersPrincipais = _contagemPrincipaisPorEstado[_estadoContagem]!;
        _controllersSecundarios = _contagemSecundariosPorEstado[_estadoContagem]!;
      }
    });
  }

  @override
  void dispose() {
    if (_ehContagemParticulas) {
      for (final controllers in _contagemPrincipaisPorEstado.values) {
        for (final controller in controllers) {
          controller.dispose();
        }
      }
      for (final controllers in _contagemSecundariosPorEstado.values) {
        for (final controller in controllers) {
          controller.dispose();
        }
      }
    } else {
      for (final controller in _controllersPrincipais) {
        controller.dispose();
      }
    }
    _observacoesController.dispose();
    _frequenciaController.dispose();
    _concentracaoController.dispose();
    _vazaoCriterioController.dispose();
    _lxController.dispose();
    super.dispose();
  }

  String _rotuloDoIndice(int index) => widget.rotulos[index];

  String _normalizarEstado(dynamic estado) => _estadosContagem.contains(estado?.toString()) ? estado.toString() : 'repouso';

  void _selecionarEstadoContagem(String? estado) {
    if (!_ehContagemParticulas || estado == null || !_estadosContagem.contains(estado)) return;
    setState(() {
      _estadoContagem = estado;
      _controllersPrincipais = _contagemPrincipaisPorEstado[estado]!;
      _controllersSecundarios = _contagemSecundariosPorEstado[estado]!;
    });
  }

  Future<void> _anexarFotoEvidencia() async {
    final capturador = widget.capturadorFoto ?? abrirCapturaFotoEvidencia;
    final path = await capturador(context);
    if (path == null) return;

    var urlFinal = 'local://$path';
    try {
      final caminhoNormalizado = path.toLowerCase();
      final extensao = caminhoNormalizado.endsWith('.png')
          ? '.png'
          : caminhoNormalizado.endsWith('.webp')
              ? '.webp'
              : caminhoNormalizado.endsWith('.gif')
                  ? '.gif'
                  : '.jpg';
      final caminhoStorage =
          'evidencias/${widget.projetoId}/${widget.sala.id}/${widget.ensaio.tipo.name}/'
          '${DateTime.now().millisecondsSinceEpoch}$extensao';
      urlFinal = await enviarImagemStorage(
        caminhoArquivo: path,
        caminhoStorage: caminhoStorage,
      );
    } catch (e) {
      debugPrint('Evidência salva apenas localmente (offline?): $e');
    }

    if (!mounted) return;
    setState(() => _fotoEvidenciaUrl = urlFinal);
  }

  bool get _todosCamposPreenchidos {
    final listasPrincipais = _ehContagemParticulas ? _contagemPrincipaisPorEstado.values : [_controllersPrincipais];
    final listasSecundarias = _ehContagemParticulas ? _contagemSecundariosPorEstado.values : [_controllersSecundarios];
    final principaisOk = listasPrincipais.every((lista) => lista.every((controller) => controller.text.trim().isNotEmpty));
    final secundariosOk = !_ehContagemParticulas ||
        listasSecundarias.every((lista) => lista.every((controller) => controller.text.trim().isNotEmpty));
    final fotoOk = !_exigeFotoEvidencia || (_fotoEvidenciaUrl != null && _fotoEvidenciaUrl!.isNotEmpty);
    final ferramentasOk =
        widget.ensaio.ferramentasNecessarias.every((tipo) => (_instrumentosPorTipo[tipo]?.isNotEmpty ?? false));
    final validacao = _validarTodosPontos();
    return principaisOk && secundariosOk && fotoOk && ferramentasOk && validacao.valido &&
        (validacao.conforme != null || _conforme != null);
  }

  ResultadoValidacaoEnsaio _validarPontos() {
    return const ValidacaoEnsaioService().validarPontos(
      tipo: widget.ensaio.tipo,
      valoresPrincipais: _controllersPrincipais.map((controller) => controller.text),
      valoresSecundarios: _controllersSecundarios.map((controller) => controller.text),
      configuracao: widget.sala.configEnsaios[widget.ensaio.tipo.name] ?? const <String, dynamic>{},
    );
  }

  ResultadoValidacaoEnsaio _validarTodosPontos() {
    if (!_ehContagemParticulas) return _validarPontos();
    final erros = <String>[];
    var conforme = true;
    var temCriterio = false;
    for (final estado in _estadosContagem) {
      final resultado = const ValidacaoEnsaioService().validarPontos(
        tipo: widget.ensaio.tipo,
        valoresPrincipais: _contagemPrincipaisPorEstado[estado]!.map((controller) => controller.text),
        valoresSecundarios: _contagemSecundariosPorEstado[estado]!.map((controller) => controller.text),
        configuracao: widget.sala.configEnsaios[widget.ensaio.tipo.name] ?? const <String, dynamic>{},
      );
      erros.addAll(resultado.erros.map((erro) => '$estado: $erro'));
      if (resultado.conforme != null) temCriterio = true;
      if (resultado.conforme == false) conforme = false;
    }
    return ResultadoValidacaoEnsaio(erros: erros, conforme: temCriterio ? conforme : null);
  }

  Map<String, dynamic> _dadosResultadoCalculado() {
    final dados = <String, dynamic>{
      'criterio': widget.sala.configEnsaios[widget.ensaio.tipo.name]?['criterio'] ?? '',
      'frequencia': _frequenciaController.text.trim(),
      'concentracao': _concentracaoController.text.trim(),
      'vazaoCriterio': _vazaoCriterioController.text.trim(),
      'lx': _lxController.text.trim(),
      'estado': _estadoContagem,
    };
    final valores = _controllersPrincipais
        .map((controller) => double.tryParse(controller.text.trim().replaceAll(',', '.')))
        .whereType<double>()
        .toList();
    if (widget.ensaio.tipo == TipoEnsaio.velocidadeFluxo && valores.isNotEmpty) {
      final media = valores.reduce((a, b) => a + b) / valores.length;
      final somaQuadrados = valores.fold<double>(0, (soma, valor) {
        final diferenca = valor - media;
        return soma + diferenca * diferenca;
      });
      final desvioPadrao = valores.length > 1 ? math.sqrt(somaQuadrados / (valores.length - 1)) : 0;
      dados['media'] = media;
      dados['desvioPadrao'] = desvioPadrao;
      dados['desvioPadraoRelativo'] = media == 0 ? null : desvioPadrao / media * 100;
    }
    return dados;
  }

  String _filtroIndice(int indice) {
    if (indice >= widget.filtroIds.length) return '';
    final filtroId = widget.filtroIds[indice];
    if (filtroId == null || filtroId.isEmpty) return '';
    return (widget.filtroIds.sublist(0, indice + 1).where((id) => id == filtroId).length).toString();
  }

  Future<void> _persistirPontos() async {
    await widget.dbHelper.deletePontosLeituraPorSalaEEnsaio(widget.sala.id, widget.ensaio.tipo.name);
    final estados = _ehContagemParticulas ? _estadosContagem : [_estadoContagem];
    for (final estado in estados) {
      final principais = _ehContagemParticulas ? _contagemPrincipaisPorEstado[estado]! : _controllersPrincipais;
      final secundarios = _ehContagemParticulas ? _contagemSecundariosPorEstado[estado]! : _controllersSecundarios;
      for (var i = 0; i < principais.length; i++) {
        final sufixoEstado = _ehContagemParticulas ? '-$estado' : '';
        await widget.dbHelper.insertPontoLeitura({
          'id': 'PONTO-${widget.sala.id}-${widget.ensaio.tipo.name}-$i$sufixoEstado',
          'projetoId': widget.projetoId,
          'salaId': widget.sala.id,
          'ensaioTipo': widget.ensaio.tipo.name,
          'numeroPonto': i + 1,
          'filtroId': i < widget.filtroIds.length ? (widget.filtroIds[i] ?? '') : '',
          'filtroIndice': _filtroIndice(i),
          'estado': estado,
          'valor05um': principais[i].text.trim(),
          'valor5um': _ehContagemParticulas ? secundarios[i].text.trim() : '',
          'fotoEvidenciaUrl': _fotoEvidenciaUrl ?? '',
          'dataHoraCaptura': DateTime.now().toIso8601String(),
        });
      }
    }
    await widget.projetoService.salvarResultadoEnsaio(
      ResultadoEnsaioModel(
        id: 'RESULTADO-${widget.sala.id}-${widget.ensaio.tipo.name}',
        projetoId: widget.projetoId,
        salaId: widget.sala.id,
        ensaioTipo: widget.ensaio.tipo.name,
        conforme: _conforme,
        observacoes: _observacoesController.text.trim(),
        tecnicoEmail: widget.tecnicoEmail,
        dataHora: DateTime.now(),
        dados: _dadosResultadoCalculado(),
      ),
    );
    await widget.projetoService.atualizarFerramentasEscaneadas(widget.projetoId, _instrumentosPorTipo);
    await widget.projetoService.sincronizarPontosLeitura(widget.projetoId);
  }

  Future<void> _concluirEnsaio() async {
    if (_salvando) return;
    final validacao = _validarTodosPontos();
    if (!validacao.valido) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validacao.erros.first), backgroundColor: Colors.amber),
      );
      return;
    }
    if (validacao.conforme != null) _conforme = validacao.conforme;
    if (!_todosCamposPreenchidos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos, escaneie as ferramentas, selecione a conformidade e anexe a foto exigida.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    await _persistirPontos();

    if (!mounted) return;
    Navigator.of(context).pop(ResultadoExecucaoEnsaio(completo: true, dataFim: DateTime.now()));
  }

  Future<void> _encerrarIncompleto() async {
    final liberacao = await solicitarLiberacaoSupervisor(
      context: context,
      titulo: 'Teste Incompleto',
      mensagem: 'Nem todos os pontos de "${widget.ensaio.nome}" em "${widget.sala.nome}" foram preenchidos.\n\n'
          'Informe o código do autenticador do Supervisor para encerrar mesmo assim:',
      projetoId: widget.projetoId,
      salaId: widget.sala.id,
      ensaioTipo: widget.ensaio.tipo.name,
      ferramentaTipo: widget.ensaio.ferramentasNecessarias.join(', '),
      ferramentaTag: widget.ensaio.ferramentasNecessarias
          .expand((tipo) => widget.ferramentasJaEscaneadas[tipo] ?? const <InstrumentoModel>[])
          .map((instrumento) => instrumento.tag)
          .join(', '),
      justificativa: 'Encerramento incompleto do ensaio ${widget.ensaio.tipo.name} na sala ${widget.sala.nome}.',
    );
    if (liberacao == null) return;

    setState(() => _salvando = true);
    await _persistirPontos();

    if (!mounted) return;
    Navigator.of(context).pop(
      ResultadoExecucaoEnsaio(completo: false, dataFim: DateTime.now(), liberacao: liberacao),
    );
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
                        Icon(
                          instrumentos.isEmpty ? Icons.error_outline : Icons.verified_outlined,
                          color: instrumentos.isEmpty ? Colors.red : Colors.green,
                        ),
                      ],
                    ),
                    if (instrumentos.isEmpty)
                      const Text('Nenhum instrumento vinculado ainda.', style: TextStyle(color: Colors.grey))
                    else
                      Wrap(spacing: 8, children: instrumentos.map((instrumento) => Chip(label: Text(instrumento.tag))).toList()),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            DropdownButtonFormField<bool?>(
              initialValue: _conforme,
              decoration: const InputDecoration(labelText: 'Conformidade'),
              items: const [
                DropdownMenuItem<bool?>(value: null, child: Text('Selecione')),
                DropdownMenuItem<bool?>(value: true, child: Text('Conforme')),
                DropdownMenuItem<bool?>(value: false, child: Text('Não conforme')),
              ],
              onChanged: (valor) => setState(() => _conforme = valor),
            ),
            const SizedBox(height: 12),
            if (widget.ensaio.tipo == TipoEnsaio.velocidadeFluxo)
              TextField(
                controller: _frequenciaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Frequência (Hz)'),
              ),
            if (widget.ensaio.tipo == TipoEnsaio.contagemParticulas) ...[
              TextField(
                controller: _concentracaoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Concentração'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _estadoContagem,
                decoration: const InputDecoration(labelText: 'Estado da contagem'),
                items: const [
                  DropdownMenuItem(value: 'repouso', child: Text('Repouso')),
                  DropdownMenuItem(value: 'operacao', child: Text('Operação')),
                ],
                onChanged: _selecionarEstadoContagem,
              ),
            ],
            if (widget.ensaio.tipo == TipoEnsaio.vazaoInsuflacao || widget.ensaio.tipo == TipoEnsaio.perdaCargaFiltros)
              TextField(
                controller: _vazaoCriterioController,
                decoration: const InputDecoration(labelText: 'Vazão / critério'),
              ),
            if (widget.ensaio.tipo == TipoEnsaio.luminosidade)
              TextField(
                controller: _lxController,
                decoration: const InputDecoration(labelText: 'L/X'),
              ),
            if ((widget.sala.configEnsaios[widget.ensaio.tipo.name]?['criterio']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Critério configurado: ${widget.sala.configEnsaios[widget.ensaio.tipo.name]?['criterio']}'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacoesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
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
                  keyboardType: _resultadoTextual
                      ? TextInputType.text
                      : TextInputType.numberWithOptions(decimal: true, signed: _permiteValorNegativo),
                  decoration: InputDecoration(
                    labelText: _rotuloDoIndice(i),
                    helperText: _permiteValorNegativo
                        ? 'Use valor negativo se o fluxo estiver invertido'
                        : _resultadoTextual
                            ? 'Ex.: Conforme / Não conforme'
                            : null,
                  ),
                ),
              );
            }),
            if (_exigeFotoEvidencia) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _anexarFotoEvidencia,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(_fotoEvidenciaUrl == null ? 'Anexar Foto de Evidência' : 'Foto Anexada ✓'),
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
