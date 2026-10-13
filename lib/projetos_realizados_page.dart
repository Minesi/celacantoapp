// lib/projetos_realizados_page.dart
// Consulta (somente leitura, exceto aprovação) dos projetos/relatórios já elaborados/executados.
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'database_helper.dart';
import 'empresa_service.dart';
import 'filtro_projetos_bar.dart';
import 'handling_unit_model.dart';
import 'history_entry_model.dart';
import 'instrumento_model.dart';
import 'leitura_model.dart';
import 'paralelismo_model.dart';
import 'projeto_model.dart';
import 'projeto_service.dart';
import 'relatorio/relatorio_documento.dart';
import 'relatorio_service.dart';
import 'revisao_resultados_page.dart';
import 'sala_model.dart';
import 'teste_catalogo_service.dart';

class ProjetosRealizadosPage extends StatefulWidget {
  final String emailLogado;
  final PerfilUsuario perfil;

  const ProjetosRealizadosPage({super.key, required this.emailLogado, required this.perfil});

  @override
  State<ProjetosRealizadosPage> createState() => _ProjetosRealizadosPageState();
}

class _ProjetosRealizadosPageState extends State<ProjetosRealizadosPage> {
  final AuthService _authService = AuthService();
  final EmpresaService _empresaService = EmpresaService();
  final ProjetoService _projetoService = ProjetoService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final RelatorioService _relatorioService = RelatorioService();
  final TesteCatalogoService _testeCatalogoService = TesteCatalogoService();

  bool _carregando = true;
  bool _aprovando = false;
  List<Map<String, dynamic>> _projetos = [];
  Map<String, String> _nomeEmpresaPorCnpj = {};
  FiltroProjetos _filtro = const FiltroProjetos();

  bool get _temAcessoDeAprovacao => widget.perfil == PerfilUsuario.supervisor || widget.perfil == PerfilUsuario.admin;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
  }

  Future<void> _carregarProjetos() async {
    setState(() => _carregando = true);
    try {
      final dominio = _authService.extrairDominio(widget.emailLogado);
      final empresas = await _empresaService.listarPorDominio(dominio);
      final projetos = await _projetoService.listarPorDominio(dominio);

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

  String _formatarData(String? isoData) {
    if (isoData == null || isoData.isEmpty) return 'Data desconhecida';
    final data = DateTime.tryParse(isoData);
    if (data == null) return isoData;
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} '
        '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  String _rotuloStatus(String? status) {
    switch (status) {
      case 'prontoParaCampo':
        return 'Pronto para campo';
      case 'emRevisao':
        return 'Em revisão';
      case 'aprovado':
        return 'Aprovado';
      default:
        return 'Rascunho';
    }
  }

  Future<ProjetoModel> _reconstruirProjetoModel(Map<String, dynamic> projetoBruto) async {
    final projetoId = projetoBruto['id'].toString();
    final salasBrutas = await _dbHelper.getSalasComFiltrosPorProjeto(projetoId);
    final handlingUnitsBrutas = await _dbHelper.getHandlingUnitsPorProjeto(projetoId);

    final handlingUnits = <HandlingUnitModel>[];
    for (final huBruta in handlingUnitsBrutas) {
      final filtros = await _dbHelper.getFiltrosPorHandlingUnit(huBruta['id'].toString());
      handlingUnits.add(HandlingUnitModel.fromMap({...huBruta, 'filtros': filtros}));
    }

    final ferramentasEscaneadas = <String, List<InstrumentoModel>>{};
    final ferramentasBrutas = Map<String, dynamic>.from(jsonDecode(projetoBruto['ferramentasEscaneadas'] ?? '{}'));
    ferramentasBrutas.forEach((tipo, instrumentos) {
      ferramentasEscaneadas[tipo] = (instrumentos as List)
          .map((i) => InstrumentoModel.fromFirestore(Map<String, dynamic>.from(i), ''))
          .toList();
    });

    final leiturasOcr = (jsonDecode(projetoBruto['leiturasOcr'] ?? '[]') as List)
        .map((l) => LeituraModel.fromMap(Map<String, dynamic>.from(l)))
        .toList();

    return ProjetoModel(
      id: projetoId,
      cnpjEmpresa: projetoBruto['cnpjEmpresa']?.toString() ?? '',
      tipoProjeto: projetoBruto['tipoProjeto']?.toString() ?? '',
      ferramentasRequeridas: List<String>.from(jsonDecode(projetoBruto['ferramentasRequeridas'] ?? '[]')),
      ferramentasEscaneadas: ferramentasEscaneadas,
      leiturasOcr: leiturasOcr,
      sistemaId: projetoBruto['sistemaId']?.toString() ?? '',
      area: projetoBruto['area']?.toString() ?? '',
      salas: salasBrutas.map((s) => SalaModel.fromMap(s)).toList(),
      handlingUnits: handlingUnits,
      ensaiosSelecionados: List<String>.from(jsonDecode(projetoBruto['ensaiosSelecionados'] ?? '[]')),
      history: (jsonDecode(projetoBruto['history']?.toString() ?? '[]') as List? ?? const [])
          .map((h) => HistoryEntry.fromMap(Map<String, dynamic>.from(h)))
          .toList(),
      paralelismo: (projetoBruto['paralelismo']?.toString() ?? '').isEmpty
          ? null
          : RegistroParalelismo.fromMap(Map<String, dynamic>.from(jsonDecode(projetoBruto['paralelismo'].toString()))),
    );
  }

  static const Map<String, String> _funcaoPorPerfil = {
    'admin': 'Administrador',
    'supervisor': 'Supervisor',
    'tecnico': 'Técnico',
    'redator': 'Elaborador',
  };

  Future<AssinaturaRelatorio> _assinatura(String papel, String email, DateTime? data) async {
    final dados = email.isEmpty ? null : await _authService.buscarDadosUsuario(email);
    final nome = dados?['nome']?.toString() ?? '';
    return AssinaturaRelatorio(
      papel: papel,
      nome: nome.isEmpty ? email : nome,
      funcao: _funcaoPorPerfil[dados?['perfil']?.toString()] ?? '',
      data: data,
    );
  }

  // Elaborador e técnico vêm do histórico; revisor/aprovador é o supervisor que está emitindo.
  Future<List<AssinaturaRelatorio>> _montarAssinaturas(ProjetoModel projeto, Map<String, dynamic> projetoBruto, DateTime emissao) async {
    final elaboracao = projeto.history.where((h) => h.campo == 'status' && h.valorNovo == 'pronto_para_campo').firstOrNull;
    final execucao = projeto.history.where((h) => h.valorNovo.startsWith('em_revisao')).lastOrNull;
    return [
      await _assinatura(
        'Elaborado por',
        elaboracao?.usuario ?? projetoBruto['operadorResponsavel']?.toString() ?? '',
        elaboracao?.dataHora ?? DateTime.tryParse(projetoBruto['dataCriacao']?.toString() ?? ''),
      ),
      await _assinatura('Executado por', execucao?.usuario ?? '', execucao?.dataHora),
      await _assinatura('Revisado por', widget.emailLogado, emissao),
      await _assinatura('Aprovado por', widget.emailLogado, emissao),
    ];
  }

  Future<DocumentoRelatorio> _montarDocumento(
    Map<String, dynamic> projetoBruto, {
    ConclusaoQualificacao? conclusao,
    Map<String, List<Map<String, dynamic>>>? pontosPorChave,
  }) async {
    final projeto = await _reconstruirProjetoModel(projetoBruto);
    final dominio = _authService.extrairDominio(widget.emailLogado);
    final catalogo = await _testeCatalogoService.listarPorDominio(dominio);
    final sistemas = await _dbHelper.getSistemas();
    final pontos = pontosPorChave == null ? await _dbHelper.getPontosLeituraPorProjeto(projeto.id) : pontosPorChave.values.expand((grupo) => grupo).toList();

    final pontosAgrupados = <String, List<Map<String, dynamic>>>{};
    for (final p in pontos) {
      pontosAgrupados.putIfAbsent('${p['salaId']}|${p['ensaioTipo']}', () => []).add(p);
    }
    final sistemaNome = sistemas
            .where((s) => s['id']?.toString() == projeto.sistemaId)
            .map((s) => s['nome']?.toString() ?? '')
            .firstOrNull ??
        projeto.sistemaId;
    final emissao = DateTime.now();

    return RelatorioDocumentoBuilder(DadosRelatorio(
      projeto: projeto,
      nomeEmpresa: _nomeEmpresaPorCnpj[projeto.cnpjEmpresa] ?? projeto.cnpjEmpresa,
      sistemaNome: sistemaNome,
      dataEmissao: emissao,
      pontosPorChave: pontosAgrupados,
      resumosPorEnsaio: catalogo.map((k, v) => MapEntry(k, v.resumo)),
      assinaturas: await _montarAssinaturas(projeto, projetoBruto, emissao),
      conclusao: conclusao,
      paralelismo: projeto.paralelismo,
    )).construir();
  }

  bool _usaTemplateCliente(String tipoProjeto) {
    final tipoNormalizado = tipoProjeto.trim().toLowerCase();
    return tipoNormalizado.contains('fluxo') || tipoNormalizado.contains('pesagem');
  }

  Future<({File? arquivo, String? localizacao, List<String> avisos})> _emitirDocumentoFinal({
    required Map<String, dynamic> projetoBruto,
    required String projetoId,
  }) async {
    final tipoProjeto = projetoBruto['tipoProjeto']?.toString() ?? '';
    if (!_usaTemplateCliente(tipoProjeto)) {
      return _relatorioService.emitirRelatorio(projetoId: projetoId);
    }

    final projeto = await _reconstruirProjetoModel(projetoBruto);
    return _relatorioService.gerarRelatorioProjeto(
      projeto: projeto,
      templateId: _relatorioService.templateIdParaProjeto(tipoProjeto),
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> _carregarPontosPorChave(String projetoId) async {
    final pontos = await _dbHelper.getPontosLeituraPorProjeto(projetoId);
    final pontosPorChave = <String, List<Map<String, dynamic>>>{};
    for (final ponto in pontos) {
      pontosPorChave.putIfAbsent('${ponto['salaId']}|${ponto['ensaioTipo']}', () => []).add(Map<String, dynamic>.from(ponto));
    }
    return pontosPorChave;
  }

  Future<void> _persistirCorrecoesDeRevisao(
    String projetoId, {
    required Map<String, List<Map<String, dynamic>>> pontosOriginais,
    required Map<String, List<Map<String, dynamic>>> pontosRevisados,
  }) async {
    final alteracoes = <HistoryEntry>[];
    for (final grupo in pontosRevisados.entries) {
      final originais = pontosOriginais[grupo.key] ?? const <Map<String, dynamic>>[];
      for (final ponto in grupo.value) {
        final pontoOriginal = originais.where((item) => item['id']?.toString() == ponto['id']?.toString()).firstOrNull;
        if (pontoOriginal == null) continue;

        final valorAnteriorPrincipal = pontoOriginal['valor05um']?.toString() ?? '';
        final valorNovoPrincipal = ponto['valor05um']?.toString() ?? '';
        final valorAnteriorSecundario = pontoOriginal['valor5um']?.toString() ?? '';
        final valorNovoSecundario = ponto['valor5um']?.toString() ?? '';
        final contexto = {
          'pontoId': ponto['id']?.toString() ?? '',
          'salaId': ponto['salaId']?.toString() ?? '',
          'ensaioTipo': ponto['ensaioTipo']?.toString() ?? '',
          'numeroPonto': ponto['numeroPonto'],
          'origem': 'revisao_supervisor',
        };
        if (valorAnteriorPrincipal != valorNovoPrincipal) {
          alteracoes.add(HistoryEntry(
            usuario: widget.emailLogado,
            dataHora: DateTime.now(),
            campo: 'pontoLeitura.valor05um',
            valorAntigo: valorAnteriorPrincipal,
            valorNovo: valorNovoPrincipal,
            detalhes: {...contexto, 'unidade': '0,5um'},
          ));
        }
        if (valorAnteriorSecundario != valorNovoSecundario) {
          alteracoes.add(HistoryEntry(
            usuario: widget.emailLogado,
            dataHora: DateTime.now(),
            campo: 'pontoLeitura.valor5um',
            valorAntigo: valorAnteriorSecundario,
            valorNovo: valorNovoSecundario,
            detalhes: {...contexto, 'unidade': '5um'},
          ));
        }
      }
    }

    if (alteracoes.isEmpty) return;
    for (final alteracao in alteracoes) {
      await _projetoService.adicionarHistorico(projetoId, alteracao);
    }
    for (final grupo in pontosRevisados.entries) {
      final originais = pontosOriginais[grupo.key] ?? const <Map<String, dynamic>>[];
      for (final ponto in grupo.value) {
        final pontoOriginal = originais.where((item) => item['id']?.toString() == ponto['id']?.toString()).firstOrNull;
        if (pontoOriginal == null) continue;
        if (pontoOriginal['valor05um']?.toString() == ponto['valor05um']?.toString() &&
            pontoOriginal['valor5um']?.toString() == ponto['valor5um']?.toString()) {
          continue;
        }
        await _dbHelper.insertPontoLeitura({...ponto, 'projetoId': projetoId});
      }
    }
    await _projetoService.sincronizarPontosLeitura(projetoId, exigirSincronizacao: true);
  }

  Future<ConclusaoQualificacao?> _perguntarConclusao() async {
    bool? cumpre;
    final comentariosController = TextEditingController();
    return showDialog<ConclusaoQualificacao>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Conclusão da qualificação'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('O sistema está qualificado em seu desempenho?'),
              RadioGroup<bool>(
                groupValue: cumpre,
                onChanged: (v) => setDialogState(() => cumpre = v),
                child: const Column(
                  children: [
                    RadioListTile<bool>(value: true, title: Text('Cumpre')),
                    RadioListTile<bool>(value: false, title: Text('Não cumpre')),
                  ],
                ),
              ),
              TextField(
                controller: comentariosController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Comentários (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: cumpre == null
                  ? null
                  : () => Navigator.of(ctx).pop(
                        ConclusaoQualificacao(cumpre: cumpre!, comentarios: comentariosController.text.trim()),
                      ),
              child: const Text('Emitir relatório'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmarAprovacaoIrreversivel() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Aprovar relatório?'),
            content: const Text(
              'Depois da aprovação, os dados não poderão mais ser alterados ou apagados. Esta ação é irreversível.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Aprovar definitivamente', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // Supervisor confere o documento exatamente como será emitido antes de aprovar e gerar o .docx.
  Future<void> _revisarEAprovar(Map<String, dynamic> projetoBruto) async {
    final pontosOriginais = await _carregarPontosPorChave(projetoBruto['id'].toString());
    final documento = await _montarDocumento(projetoBruto, pontosPorChave: pontosOriginais);

    if (!mounted) return;
    final revisao = await Navigator.push<ResultadoRevisaoRelatorio>(
      context,
      MaterialPageRoute(
        builder: (_) => RevisaoResultadosPage(
          documentoInicial: documento,
          pontosIniciais: pontosOriginais,
          reconstruirDocumento: (pontos) => _montarDocumento(projetoBruto, pontosPorChave: pontos),
        ),
      ),
    );

    if (revisao == null || !mounted) return;
    if (!await _confirmarAprovacaoIrreversivel() || !mounted) return;
    final conclusao = await _perguntarConclusao();
    if (conclusao == null) return;
    final comentarios = [
      if (revisao.observacoes.isNotEmpty) 'Observações da revisão:\n${revisao.observacoes}',
      if (conclusao.comentarios.isNotEmpty) conclusao.comentarios,
    ].join('\n\n');
    await _aprovarEGerarRelatorio(
      projetoBruto,
      ConclusaoQualificacao(cumpre: conclusao.cumpre, comentarios: comentarios),
      pontosOriginais: pontosOriginais,
      pontosRevisados: revisao.pontosPorChave,
      observacoesRevisao: revisao.observacoes,
    );
  }

  Future<void> _aprovarEGerarRelatorio(
    Map<String, dynamic> projetoBruto,
    ConclusaoQualificacao conclusao, {
    Map<String, List<Map<String, dynamic>>>? pontosOriginais,
    Map<String, List<Map<String, dynamic>>>? pontosRevisados,
    String observacoesRevisao = '',
  }) async {
    if (_aprovando) return;
    setState(() => _aprovando = true);

    try {
      final projetoId = projetoBruto['id'].toString();
      if (pontosOriginais != null && pontosRevisados != null) {
        await _persistirCorrecoesDeRevisao(
          projetoId,
          pontosOriginais: pontosOriginais,
          pontosRevisados: pontosRevisados,
        );
      }
      await _projetoService.registrarHistoricoEAtualizarStatus(
        projetoId,
        novoStatus: StatusRelatorio.aprovado,
        novaEntrada: HistoryEntry(
          usuario: widget.emailLogado,
          dataHora: DateTime.now(),
          campo: 'status',
          valorAntigo: 'em_revisao',
          valorNovo: 'aprovado',
          detalhes: {
            'conclusao': {
              'cumpre': conclusao.cumpre,
              'comentarios': conclusao.comentarios,
            },
            if (observacoesRevisao.isNotEmpty) 'observacoesRevisao': observacoesRevisao,
          },
        ),
        exigirSincronizacao: true,
      );

      final resultado = await _emitirDocumentoFinal(
        projetoBruto: projetoBruto,
        projetoId: projetoId,
      );

      if (!mounted) return;

      if (resultado.localizacao == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Relatório aprovado, mas a geração falhou. ${resultado.avisos.join(' ')}'),
            backgroundColor: Colors.red,
          ),
        );
        await _carregarProjetos();
        return;
      }

      final envioEmail = await _relatorioService.enviarRelatorioPorEmail(projetoId: projetoId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            envioEmail.enviado
                ? 'Relatório aprovado, gerado e enviado por e-mail com sucesso!'
                : 'Relatório aprovado e gerado. O e-mail não foi enviado: ${envioEmail.aviso ?? 'erro não informado'}.',
          ),
          backgroundColor: envioEmail.enviado ? Colors.green : Colors.orange,
        ),
      );
      await _mostrarAcoesRelatorio(
        projetoId: projetoId,
        localizacao: resultado.localizacao!,
        arquivo: resultado.arquivo,
        emailJaEnviado: envioEmail.enviado,
      );
      await _carregarProjetos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao aprovar/gerar relatório: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _aprovando = false);
    }
  }

  ConclusaoQualificacao? _conclusaoPersistida(Map<String, dynamic> projetoBruto) {
    final historicoBruto = projetoBruto['history']?.toString() ?? '[]';
    final historico = (jsonDecode(historicoBruto) as List? ?? const [])
        .map((h) => HistoryEntry.fromMap(Map<String, dynamic>.from(h)))
        .toList()
        .reversed;
    for (final entrada in historico) {
      if (entrada.campo != 'status' || entrada.valorNovo != 'aprovado') continue;
      final conclusao = entrada.detalhes['conclusao'];
      if (conclusao is! Map || conclusao['cumpre'] is! bool) return null;
      return ConclusaoQualificacao(
        cumpre: conclusao['cumpre'] as bool,
        comentarios: conclusao['comentarios']?.toString() ?? '',
      );
    }
    return null;
  }

  Future<void> _regenerarRelatorio(Map<String, dynamic> projetoBruto) async {
    if (_aprovando || projetoBruto['status']?.toString() != StatusRelatorio.aprovado.name) return;
    final conclusao = _conclusaoPersistida(projetoBruto);
    if (conclusao == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A conclusão da aprovação não está disponível para regeneração.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _aprovando = true);
    final projetoId = projetoBruto['id'].toString();
    try {
      final resultado = await _emitirDocumentoFinal(
        projetoBruto: projetoBruto,
        projetoId: projetoId,
      );
      if (!mounted) return;
      if (resultado.localizacao == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível regenerar o relatório. ${resultado.avisos.join(' ')}'), backgroundColor: Colors.red),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relatório regenerado com sucesso!'), backgroundColor: Colors.green),
      );
      await _mostrarAcoesRelatorio(
        projetoId: projetoId,
        localizacao: resultado.localizacao!,
        arquivo: resultado.arquivo,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao regenerar relatório: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _aprovando = false);
    }
  }

  Future<void> _mostrarAcoesRelatorio({
    required String projetoId,
    required String localizacao,
    required File? arquivo,
    bool emailJaEnviado = false,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Relatório pronto'),
        content: const Text('Escolha uma ação para o arquivo gerado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final envio = await _relatorioService.enviarRelatorioPorEmail(projetoId: projetoId);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    envio.enviado
                        ? 'Relatório enviado por e-mail com sucesso.'
                        : 'Não foi possível enviar o relatório por e-mail: ${envio.aviso ?? 'erro não informado'}.',
                  ),
                  backgroundColor: envio.enviado ? Colors.green : Colors.orange,
                ),
              );
            },
            icon: Icon(emailJaEnviado ? Icons.forward_to_inbox_outlined : Icons.email_outlined),
            label: Text(emailJaEnviado ? 'Reenviar e-mail' : 'Enviar e-mail'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final abriu = await _relatorioService.abrirRelatorio(localizacao);
              if (!abriu && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Não foi possível abrir o relatório.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Abrir'),
          ),
          if (Platform.isWindows)
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final abriu = await _relatorioService.abrirImpressaoWindows(localizacao);
                if (!abriu && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir a impressão.'), backgroundColor: Colors.red),
                  );
                }
              },
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir'),
            ),
          if ((Platform.isAndroid || Platform.isIOS) && arquivo != null)
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final compartilhou = await _relatorioService.compartilharRelatorio(
                  arquivo: arquivo,
                  assunto: 'Relatório $projetoId',
                  texto: 'Relatório aprovado $projetoId.',
                );
                if (!compartilhou && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o compartilhamento.'), backgroundColor: Colors.red),
                  );
                }
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Enviar'),
            ),
        ],
      ),
    );
  }

  Future<void> _abrirDetalhes(Map<String, dynamic> projeto) async {
    final projetoId = projeto['id'].toString();
    final salas = (await _dbHelper.getSalasComFiltrosPorProjeto(projetoId)).map(SalaModel.fromMap).toList();
    final handlingUnits = await _dbHelper.getHandlingUnitsPorProjeto(projetoId);
    final ensaios = List<String>.from(jsonDecode(projeto['ensaiosSelecionados'] ?? '[]'));

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _nomeEmpresaPorCnpj[projeto['cnpjEmpresa']] ?? projeto['cnpjEmpresa'].toString(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text('Tipo: ${projeto['tipoProjeto'] ?? '-'}'),
                Text('Sistema: ${(projeto['sistemaId'] ?? '').toString().isEmpty ? '-' : projeto['sistemaId']}'),
                Text('Área: ${(projeto['area'] ?? '').toString().isEmpty ? '-' : projeto['area']}'),
                Text('Status: ${_rotuloStatus(projeto['status']?.toString())}'),
                Text('Criado em: ${_formatarData(projeto['dataCriacao']?.toString())}'),
                Text('Responsável: ${projeto['operadorResponsavel'] ?? '-'}'),
                const SizedBox(height: 16),
                Text('Ensaios (${ensaios.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (ensaios.isEmpty) const Text('Nenhum ensaio selecionado.', style: TextStyle(color: Colors.grey)),
                ...ensaios.map((e) => Text('• $e')),
                const SizedBox(height: 16),
                Text('Salas (${salas.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (salas.isEmpty) const Text('Nenhuma sala cadastrada.', style: TextStyle(color: Colors.grey)),
                ...salas.map((s) => Text(
                    '• ${s.nome} — Grau ${s.grau.name.toUpperCase()} (${s.area} m²) — '
                    '${s.filtros.isEmpty ? 'sem filtros' : s.filtros.map((f) => f.descricao).join(', ')}')),
                const SizedBox(height: 16),
                Text('Handling Units (${handlingUnits.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (handlingUnits.isEmpty) const Text('Nenhuma handling unit cadastrada.', style: TextStyle(color: Colors.grey)),
                ...handlingUnits.map((h) => Text('• ${h['nome']}')),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Projetos Realizados'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregarProjetos,
              child: _projetos.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Nenhum projeto encontrado ainda.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        FiltroProjetosBar(
                          projetos: _projetos,
                          nomeEmpresaPorCnpj: _nomeEmpresaPorCnpj,
                          filtro: _filtro,
                          onChanged: (f) => setState(() => _filtro = f),
                        ),
                        Expanded(child: _buildLista(_filtro.aplicar(_projetos))),
                      ],
                    ),
            ),
    );
  }

  Widget _buildLista(List<Map<String, dynamic>> projetos) {
    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: projetos.length,
                      itemBuilder: (context, index) {
                        final projeto = projetos[index];
                        final sincronizado = projeto['sincronizado'] == 1;
                        final status = projeto['status']?.toString();
                        final podeAprovar = _temAcessoDeAprovacao && status == 'emRevisao';
                        final podeRegenerar = _temAcessoDeAprovacao && status == StatusRelatorio.aprovado.name;
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              sincronizado ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                              color: sincronizado ? Colors.green : Colors.grey,
                            ),
                            title: Text(_nomeEmpresaPorCnpj[projeto['cnpjEmpresa']] ?? projeto['cnpjEmpresa'].toString()),
                            subtitle: Text(
                              '${projeto['tipoProjeto'] ?? '-'} · Área: ${(projeto['area'] ?? '').toString().isEmpty ? '-' : projeto['area']} · '
                              '${_formatarData(projeto['dataCriacao']?.toString())} · ${_rotuloStatus(status)}',
                            ),
                            trailing: podeAprovar
                              ? IconButton(
                                    icon: _aprovando
                                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.task_alt, color: Colors.green),
                                    tooltip: 'Revisar resultados e aprovar',
                                    onPressed: _aprovando ? null : () => _revisarEAprovar(projeto),
                                  )
                              : podeRegenerar
                                ? IconButton(
                                  icon: _aprovando
                                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.refresh, color: Colors.blue),
                                  tooltip: 'Gerar relatório novamente',
                                  onPressed: _aprovando ? null : () => _regenerarRelatorio(projeto),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: () => _abrirDetalhes(projeto),
                          ),
                        );
                      },
                    );
  }
}
