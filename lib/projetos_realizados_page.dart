// lib/projetos_realizados_page.dart
// Consulta (somente leitura, exceto aprovação) dos projetos/relatórios já elaborados/executados.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'database_helper.dart';
import 'empresa_service.dart';
import 'ensaio_model.dart';
import 'filtro_projetos_bar.dart';
import 'handling_unit_model.dart';
import 'history_entry_model.dart';
import 'instrumento_model.dart';
import 'leitura_model.dart';
import 'preview_relatorio_widget.dart';
import 'projeto_model.dart';
import 'projeto_service.dart';
import 'relatorio_service.dart';
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
    );
  }

  // Supervisor confere os resultados de campo antes de aprovar e gerar o .docx.
  Future<void> _revisarEAprovar(Map<String, dynamic> projetoBruto) async {
    final projeto = await _reconstruirProjetoModel(projetoBruto);
    final dominio = _authService.extrairDominio(widget.emailLogado);
    final catalogo = await _testeCatalogoService.listarPorDominio(dominio);
    final sistemas = await _dbHelper.getSistemas();
    final pontos = await _dbHelper.getPontosLeituraPorProjeto(projeto.id);

    final pontosPorChave = <String, List<Map<String, dynamic>>>{};
    for (final p in pontos) {
      pontosPorChave.putIfAbsent('${p['salaId']}|${p['ensaioTipo']}', () => []).add(p);
    }
    final sistemaNome = sistemas
            .where((s) => s['id']?.toString() == projeto.sistemaId)
            .map((s) => s['nome']?.toString() ?? '')
            .firstOrNull ??
        projeto.sistemaId;

    if (!mounted) return;
    final aprovar = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Revisão dos Resultados'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PreviewRelatorioWidget(
              nomeEmpresa: _nomeEmpresaPorCnpj[projeto.cnpjEmpresa] ?? projeto.cnpjEmpresa,
              cnpjEmpresa: projeto.cnpjEmpresa,
              tipoProjeto: projeto.tipoProjeto,
              sistemaNome: sistemaNome,
              area: projeto.area,
              dataHora: DateTime.tryParse(projetoBruto['dataCriacao']?.toString() ?? ''),
              handlingUnits: projeto.handlingUnits,
              salas: projeto.salas,
              ensaios: projeto.ensaiosSelecionados
                  .map((n) => TipoEnsaio.values.where((t) => t.name == n).firstOrNull)
                  .whereType<TipoEnsaio>()
                  .toList(),
              resumosPorEnsaio: catalogo.map((k, v) => MapEntry(k, v.resumo)),
              pontosPorChave: pontosPorChave,
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.task_alt, color: Colors.white),
                label: const Text('Aprovar e gerar relatório', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ),
        ),
      ),
    );

    if (aprovar == true) await _aprovarEGerarRelatorio(projetoBruto);
  }

  Future<void> _aprovarEGerarRelatorio(Map<String, dynamic> projetoBruto) async {
    if (_aprovando) return;
    setState(() => _aprovando = true);

    try {
      final projeto = await _reconstruirProjetoModel(projetoBruto);
      final nomeEmpresa = _nomeEmpresaPorCnpj[projeto.cnpjEmpresa] ?? projeto.cnpjEmpresa;
      final templateAsset = _relatorioService.assetPathParaProjeto(projeto.tipoProjeto);

      final resultado = await _relatorioService.gerarRelatorioProjeto(
        projeto: projeto,
        nomeEmpresa: nomeEmpresa,
        assetTemplatePath: templateAsset,
      );

      if (!mounted) return;

      if (resultado.localizacao == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resultado.avisos.join(' ')), backgroundColor: Colors.red),
        );
        return;
      }

      await _projetoService.registrarHistoricoEAtualizarStatus(
        projeto.id,
        novoStatus: StatusRelatorio.aprovado,
        novaEntrada: HistoryEntry(
          usuario: widget.emailLogado,
          dataHora: DateTime.now(),
          campo: 'status',
          valorAntigo: 'em_revisao',
          valorNovo: 'aprovado',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relatório aprovado e gerado com sucesso!'), backgroundColor: Colors.green),
      );
      await _relatorioService.abrirRelatorio(resultado.localizacao!);
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
                    '${s.filtros.isEmpty ? 'sem filtros' : s.filtros.map((f) => '${f.quantidade}× ${f.tipo.name.toUpperCase()}').join(', ')}')),
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
                                : const Icon(Icons.chevron_right),
                            onTap: () => _abrirDetalhes(projeto),
                          ),
                        );
                      },
                    );
  }
}
