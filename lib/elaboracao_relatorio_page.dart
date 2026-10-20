// lib/elaboracao_relatorio_page.dart
// Etapa de "elaboração" (redator/admin): monta a estrutura do relatório antes de ir a campo —
// empresa, sistema, área, máquinas, salas/filtros e ensaios — para que o técnico receba
// o relatório já pré-preenchido, restando apenas registrar os resultados de campo.
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'database_helper.dart';
import 'empresa_model.dart';
import 'empresa_service.dart';
import 'ensaio_model.dart';
import 'filtro_model.dart';
import 'firestore_colecoes.dart';
import 'handling_unit_model.dart';
import 'history_entry_model.dart';
import 'preview_relatorio_widget.dart';
import 'projeto_model.dart';
import 'projeto_service.dart';
import 'regras_pesagem.dart';
import 'sala_model.dart';
import 'sistema_model.dart';
import 'sistema_service.dart';
import 'teste_catalogo_model.dart';
import 'teste_catalogo_service.dart';
import 'validadores.dart';

class ElaboracaoRelatorioPage extends StatefulWidget {
  final String emailLogado;

  const ElaboracaoRelatorioPage({super.key, required this.emailLogado});

  @override
  State<ElaboracaoRelatorioPage> createState() => _ElaboracaoRelatorioPageState();
}

class _ElaboracaoRelatorioPageState extends State<ElaboracaoRelatorioPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final EmpresaService _empresaService = EmpresaService();
  final SistemaService _sistemaService = SistemaService();
  final ProjetoService _projetoService = ProjetoService();
  final TesteCatalogoService _testeCatalogoService = TesteCatalogoService();

  static const List<String> _tiposDeProjeto = EnsaioModel.tiposDeProjeto;

  bool _carregando = true;
  bool _salvando = false;

  List<EmpresaModel> _empresas = [];
  List<SistemaModel> _sistemas = [];

  String _cnpjSelecionado = '';
  EmpresaModel? _empresaSelecionada;
  String? _tipoProjetoSelecionado;
  SistemaModel? _sistemaSelecionado;
  final _areaController = TextEditingController();
  final _validadeController = TextEditingController(text: '12');

  final List<SalaModel> _salas = [];
  final List<HandlingUnitModel> _handlingUnits = [];
  final Set<TipoEnsaio> _ensaiosSelecionados = {};

  Map<String, TesteCatalogoModel> _catalogoTestes = {};
  final Map<String, TextEditingController> _resumoControllers = {};

  // Painel de pré-visualização só em telas de desktop/web.
  static bool get _plataformaComPreviewLateral =>
      kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  final _formKeyEmpresaRapida = GlobalKey<FormState>();
  final _cnpjRapidoController = TextEditingController();
  final _razaoSocialRapidoController = TextEditingController();
  final _nomeFantasiaRapidoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
    // Mantém a pré-visualização ao vivo em sincronia enquanto o usuário digita a área.
    _areaController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _areaController.dispose();
    _validadeController.dispose();
    _cnpjRapidoController.dispose();
    _razaoSocialRapidoController.dispose();
    _nomeFantasiaRapidoController.dispose();
    for (final c in _resumoControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _dominio => _authService.extrairDominio(widget.emailLogado);

  Future<void> _carregarDadosIniciais() async {
    setState(() => _carregando = true);
    try {
      final mapasEmpresas = await _empresaService.listarPorDominio(_dominio);
      final sistemas = await _sistemaService.listarPorDominio(_dominio);
      final catalogo = await _testeCatalogoService.listarPorDominio(_dominio);

      if (!mounted) return;
      setState(() {
        _catalogoTestes = catalogo;
        for (final entrada in catalogo.entries) {
          _resumoControllers
              .putIfAbsent(entrada.key, () => TextEditingController()..addListener(() => setState(() {})))
              .text = entrada.value.resumo;
        }
        _empresas = mapasEmpresas
            .map((m) => EmpresaModel(
                  cnpj: m['cnpj']?.toString() ?? '',
                  razaoSocial: m['razaoSocial']?.toString() ?? '',
                  nomeFantasia: m['nomeFantasia']?.toString() ?? '',
                  dominio: m['dominio_empresa']?.toString() ?? '',
                ))
            .toList();
        _sistemas = sistemas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar dados: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _abrirModalNovaEmpresa() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
          child: Form(
            key: _formKeyEmpresaRapida,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Cadastrar Nova Empresa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cnpjRapidoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CNPJ da Empresa', prefixIcon: Icon(Icons.badge_outlined)),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Insira o CNPJ';
                      if (!validarCnpj(v)) return 'CNPJ inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _razaoSocialRapidoController,
                    decoration: const InputDecoration(labelText: 'Razão Social', prefixIcon: Icon(Icons.business_outlined)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Insira a Razão Social' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nomeFantasiaRapidoController,
                    decoration: const InputDecoration(labelText: 'Nome Fantasia', prefixIcon: Icon(Icons.storefront_outlined)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Insira o Nome Fantasia' : null,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _salvarNovaEmpresaRapido,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Salvar Empresa', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _salvarNovaEmpresaRapido() async {
    if (!_formKeyEmpresaRapida.currentState!.validate()) return;

    final novaEmpresa = EmpresaModel(
      cnpj: _cnpjRapidoController.text.trim(),
      razaoSocial: _razaoSocialRapidoController.text.trim(),
      nomeFantasia: _nomeFantasiaRapidoController.text.trim(),
      dominio: _dominio,
    );

    final resultadoLocal = await _dbHelper.insertEmpresa(novaEmpresa.toMap());
    if (resultadoLocal <= 0) return;

    if (!mounted) return;
    Navigator.of(context).pop();

    try {
      await _firestore.collection(FirestoreColecoes.empresas).doc(novaEmpresa.dominio).set(novaEmpresa.toFirestore());
    } catch (e) {
      debugPrint('Guardado offline no Firestore/Falha ao enviar: $e');
    }

    _cnpjRapidoController.clear();
    _razaoSocialRapidoController.clear();
    _nomeFantasiaRapidoController.clear();
    _carregarDadosIniciais();
  }

  void _abrirModalNovoSistema() {
    final nomeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Novo Sistema'),
          content: TextField(
            controller: nomeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Ex: HDA04', prefixIcon: Icon(Icons.dns_outlined)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nomeController.text.trim().isEmpty) return;
                final sistemaCriado = await _sistemaService.criarSistema(
                  SistemaModel(id: '', nome: nomeController.text.trim(), dominioEmpresa: _dominio),
                );
                if (!context.mounted) return;
                Navigator.of(context).pop();
                setState(() {
                  _sistemas = [..._sistemas, sistemaCriado];
                  _sistemaSelecionado = sistemaCriado;
                });
              },
              child: const Text('Criar'),
            ),
          ],
        );
      },
    );
  }

  void _abrirModalNovaSala() {
    if (_handlingUnits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre primeiro a máquina que atende a sala.'), backgroundColor: Colors.amber),
      );
      return;
    }
    final nomeController = TextEditingController();
    final areaController = TextEditingController();
    final volumeController = TextEditingController();
    final filtrosTemp = <FiltroModel>[];
    GrauSala grauSelecionado = GrauSala.d;
    String handlingUnitIdSelecionado = _handlingUnits.first.id;
    bool atendidaPorMaisMaquinas = false;
    final idsAdicionais = <String>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Adicionar Sala', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nomeController,
                      decoration: const InputDecoration(labelText: 'Nome da Sala', prefixIcon: Icon(Icons.meeting_room_outlined)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: areaController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Área (m²)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: volumeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Volume (m³)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<GrauSala>(
                            initialValue: grauSelecionado,
                            decoration: const InputDecoration(labelText: 'Grau'),
                            items: GrauSala.values
                                .map((g) => DropdownMenuItem(value: g, child: Text('Grau ${g.name.toUpperCase()}')))
                                .toList(),
                            onChanged: (g) => setModalState(() => grauSelecionado = g ?? GrauSala.d),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: handlingUnitIdSelecionado,
                            decoration: const InputDecoration(labelText: 'Máquina que atende'),
                            items: _handlingUnits
                                .map((h) => DropdownMenuItem(
                                      value: h.id,
                                      child: Text('${h.nome}${h.numero.isEmpty ? '' : ' #${h.numero}'}', overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (id) => setModalState(() {
                              handlingUnitIdSelecionado = id ?? handlingUnitIdSelecionado;
                              idsAdicionais.remove(handlingUnitIdSelecionado);
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (_handlingUnits.length > 1) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: atendidaPorMaisMaquinas,
                        title: const Text('Sala atendida por mais de uma máquina'),
                        onChanged: (v) => setModalState(() {
                          atendidaPorMaisMaquinas = v ?? false;
                          if (!atendidaPorMaisMaquinas) idsAdicionais.clear();
                        }),
                      ),
                      if (atendidaPorMaisMaquinas) ...[
                        for (var i = 0; i < idsAdicionais.length; i++)
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('maquina-adicional-$i-${idsAdicionais[i]}'),
                                  initialValue: idsAdicionais[i],
                                  decoration: InputDecoration(labelText: 'Máquina adicional ${i + 1}'),
                                  items: _handlingUnits
                                      .where((h) =>
                                          h.id == idsAdicionais[i] ||
                                          (h.id != handlingUnitIdSelecionado && !idsAdicionais.contains(h.id)))
                                      .map((h) => DropdownMenuItem(value: h.id, child: Text(h.nome, overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (id) => setModalState(() => idsAdicionais[i] = id ?? idsAdicionais[i]),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () => setModalState(() => idsAdicionais.removeAt(i)),
                              ),
                            ],
                          ),
                        Builder(builder: (_) {
                          final disponiveis = _handlingUnits
                              .where((h) => h.id != handlingUnitIdSelecionado && !idsAdicionais.contains(h.id))
                              .toList();
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: disponiveis.isEmpty
                                  ? null
                                  : () => setModalState(() => idsAdicionais.add(disponiveis.first.id)),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Adicionar máquina'),
                            ),
                          );
                        }),
                      ],
                    ],
                    const SizedBox(height: 16),
                    const Text('Filtros da Sala', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _EditorFiltrosSala(
                      key: ValueKey(handlingUnitIdSelecionado),
                      maquina: _handlingUnits.firstWhere((h) => h.id == handlingUnitIdSelecionado),
                      salasExistentes: _salas,
                      filtros: filtrosTemp,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (nomeController.text.trim().isEmpty) return;
                        final salaId = 'SALA-${DateTime.now().microsecondsSinceEpoch}';
                        setState(() {
                          _salas.add(SalaModel(
                            id: salaId,
                            nome: nomeController.text.trim(),
                            area: double.tryParse(areaController.text.replaceAll(',', '.')) ?? 0,
                            volume: double.tryParse(volumeController.text.replaceAll(',', '.')) ?? 0,
                            grau: grauSelecionado,
                            handlingUnitId: handlingUnitIdSelecionado,
                            handlingUnitIdsAdicionais: List<String>.from(idsAdicionais),
                            filtros: filtrosTemp.asMap().entries
                                .map((entry) {
                                  final filtro = entry.value;
                                  return FiltroModel(
                                    id: '$salaId-FILTRO-${entry.key}',
                                    tipo: filtro.tipo,
                                    quantidade: filtro.quantidade,
                                    localizacao: filtro.localizacao,
                                    marca: filtro.marca,
                                    modelo: filtro.modelo,
                                    dimensoes: filtro.dimensoes,
                                  );
                                })
                                .toList(),
                          ));
                        });
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _abrirModalNovaHandlingUnit() {
    final nomeController = TextEditingController();
    final numeroController = TextEditingController();
    final filtrosTemp = <FiltroModel>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 24, left: 24, right: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Adicionar Máquina (Handling Unit)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nomeController,
                      decoration: const InputDecoration(labelText: 'Nome/Identificação da Máquina', prefixIcon: Icon(Icons.hvac_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: numeroController,
                      decoration: const InputDecoration(labelText: 'Número da Máquina', prefixIcon: Icon(Icons.tag_outlined)),
                    ),
                    const SizedBox(height: 16),
                    const Text('Filtros internos da Máquina (informativo)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _EditorFiltros(filtros: filtrosTemp, localizacao: LocalizacaoFiltro.maquina),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (nomeController.text.trim().isEmpty) return;
                        setState(() {
                          _handlingUnits.add(HandlingUnitModel(
                            id: 'HU-${DateTime.now().microsecondsSinceEpoch}',
                            nome: nomeController.text.trim(),
                            numero: numeroController.text.trim(),
                            filtros: List<FiltroModel>.from(filtrosTemp),
                          ));
                        });
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<String> get _ferramentasRequeridasDosEnsaios {
    final catalogo = EnsaioModel.catalogoPadrao();
    final ferramentas = <String>{};
    for (final tipo in _ensaiosSelecionados) {
      final ensaio = catalogo.firstWhere((e) => e.tipo == tipo);
      ferramentas.addAll(ensaio.ferramentasNecessarias);
    }
    return ferramentas.toList();
  }

  String _chaveFiltro(FiltroModel filtro) => [
        filtro.tipo.name,
        filtro.marca.trim().toLowerCase(),
        filtro.modelo.trim().toLowerCase(),
        filtro.dimensoes.trim().toLowerCase(),
      ].join('|');

  Map<String, int> _quantidadesPorEspecificacao(Iterable<FiltroModel> filtros) {
    final quantidades = <String, int>{};
    for (final filtro in filtros) {
      final chave = _chaveFiltro(filtro);
      quantidades[chave] = (quantidades[chave] ?? 0) + filtro.quantidade;
    }
    return quantidades;
  }

  void _atualizarConfiguracaoEnsaio(SalaModel sala, TipoEnsaio tipo, String campo, dynamic valor) {
    final configuracao = <String, dynamic>{
      ...?sala.configEnsaios[tipo.name],
      campo: valor,
    };
    final indice = _salas.indexWhere((item) => item.id == sala.id);
    if (indice < 0) return;
    setState(() {
      _salas[indice] = SalaModel(
        id: sala.id,
        nome: sala.nome,
        area: sala.area,
        volume: sala.volume,
        grau: sala.grau,
        handlingUnitId: sala.handlingUnitId,
        handlingUnitIdsAdicionais: sala.handlingUnitIdsAdicionais,
        filtros: sala.filtros,
        configEnsaios: {
          ...sala.configEnsaios,
          tipo.name: configuracao,
        },
      );
    });
  }

  List<Widget> _camposPesagemDaSala(SalaModel sala) {
    if (_tipoProjetoSelecionado != EnsaioModel.tipoPesagem) return const [];
    final campos = <Widget>[];
    if (_ensaiosSelecionados.contains(TipoEnsaio.visualizacaoFluxo)) {
      final visual = sala.configEnsaios[TipoEnsaio.visualizacaoFluxo.name] ?? const <String, dynamic>{};
      campos.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: visual['tipoFumaca']?.toString() ?? 'Glicerina',
                decoration: const InputDecoration(labelText: 'Tipo de fumaça', isDense: true),
                onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, TipoEnsaio.visualizacaoFluxo, 'tipoFumaca', valor),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: visual['sentidoFluxo']?.toString() ?? 'Unidirecional',
                decoration: const InputDecoration(labelText: 'Sentido do fluxo', isDense: true),
                onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, TipoEnsaio.visualizacaoFluxo, 'sentidoFluxo', valor),
              ),
            ),
          ],
        ),
      ));
    }
    if (_ensaiosSelecionados.contains(TipoEnsaio.contagemParticulas)) {
      final contagem = sala.configEnsaios[TipoEnsaio.contagemParticulas.name] ?? const <String, dynamic>{};
      for (final estado in const ['repouso', 'operacao']) {
        final rotuloEstado = estado == 'repouso' ? 'Repouso' : 'Operação';
        final padrao = RegrasPesagem.limitesContagemGrauC(operacao: estado == 'operacao');
        for (final campo in const ['criterioMax', 'criterioMax5um']) {
          final chave = '${campo}_$estado';
          final rotuloParticula = campo == 'criterioMax' ? '0,5 µm' : '5 µm';
          campos.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextFormField(
              initialValue: contagem[chave]?.toString() ?? (sala.grau == GrauSala.c ? padrao[campo].toString() : ''),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Limite $rotuloEstado — $rotuloParticula (part./m³)', isDense: true),
              onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, TipoEnsaio.contagemParticulas, chave, valor),
            ),
          ));
        }
      }
    }
    return campos;
  }

  Widget _configuracaoEnsaiosDasSalas() {
    if (_salas.isEmpty || _ensaiosSelecionados.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Text('Configuração por sala', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._salas.expand((sala) {
          return [
            Text(sala.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ..._ensaiosSelecionados.map((tipo) {
              final configuracao = sala.configEnsaios[tipo.name] ?? const <String, dynamic>{};
              final ensaio = EnsaioModel.catalogoPadrao().firstWhere((item) => item.tipo == tipo);
              final exigePontos = {
                TipoEnsaio.velocidadeFluxo,
                TipoEnsaio.nivelRuido,
                TipoEnsaio.luminosidade,
                TipoEnsaio.paralelismoFluxo,
                TipoEnsaio.visualizacaoFluxo,
              }.contains(tipo);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(ensaio.nome, style: const TextStyle(fontSize: 13)),
                    ),
                    if (exigePontos)
                      Expanded(
                        child: TextFormField(
                          initialValue: configuracao['pontos']?.toString() ?? '',
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tipo == TipoEnsaio.velocidadeFluxo ? 'Pontos/filtro' : 'Pontos',
                            isDense: true,
                          ),
                          onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, tipo, 'pontos', valor),
                        ),
                      ),
                    if (tipo == TipoEnsaio.velocidadeFluxo)
                      Expanded(
                        child: TextFormField(
                          initialValue: configuracao['mediaEsperada']?.toString() ?? '',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Média esperada (m/s)', isDense: true),
                          onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, tipo, 'mediaEsperada', valor),
                        ),
                      ),
                    if (tipo == TipoEnsaio.velocidadeFluxo)
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: configuracao['localizacoes']?.toString() ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Localização dos pontos (separe por vírgula)',
                            isDense: true,
                          ),
                          onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, tipo, 'localizacoes', valor),
                        ),
                      ),
                    if (tipo == TipoEnsaio.contagemParticulas)
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: (configuracao['estado'] ?? 'repouso').toString(),
                          decoration: const InputDecoration(labelText: 'Estado', isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'repouso', child: Text('Repouso')),
                            DropdownMenuItem(value: 'operacao', child: Text('Operação')),
                          ],
                          onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, tipo, 'estado', valor ?? 'repouso'),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: configuracao['criterio']?.toString() ?? '',
                        decoration: const InputDecoration(labelText: 'Critério', isDense: true),
                        onChanged: (valor) => _atualizarConfiguracaoEnsaio(sala, tipo, 'criterio', valor),
                      ),
                    ),
                  ],
                ),
              );
            }),
            ..._camposPesagemDaSala(sala),
            const Divider(height: 16),
          ];
        }),
      ],
    );
  }

  String? _validarEstruturaAntesDeSalvar() {
    if (_empresaSelecionada == null) return 'Selecione a empresa cliente.';
    if (_tipoProjetoSelecionado == null) return 'Selecione o tipo de projeto.';
    if (_sistemaSelecionado == null) return 'Selecione o sistema.';
    if (_areaController.text.trim().isEmpty) return 'Informe a área atendida.';
    if ((int.tryParse(_validadeController.text.trim()) ?? 0) < 1) return 'Informe a validade dos testes em meses.';
    if (_handlingUnits.isEmpty) return 'Adicione pelo menos uma máquina.';
    if (_salas.isEmpty) return 'Adicione pelo menos uma sala.';
    if (_ensaiosSelecionados.isEmpty) return 'Selecione pelo menos um ensaio.';

    const pontosVariaveis = {
      TipoEnsaio.velocidadeFluxo,
      TipoEnsaio.nivelRuido,
      TipoEnsaio.luminosidade,
      TipoEnsaio.paralelismoFluxo,
      TipoEnsaio.visualizacaoFluxo,
    };
    for (final sala in _salas) {
      for (final tipo in _ensaiosSelecionados.where(pontosVariaveis.contains)) {
        final pontos = int.tryParse(sala.configEnsaios[tipo.name]?['pontos']?.toString() ?? '') ?? 0;
        if (pontos < 1) {
          return 'Defina a quantidade de pontos de ${EnsaioModel.catalogoPadrao().firstWhere((e) => e.tipo == tipo).nome} para a sala ${sala.nome}.';
        }
        final localizacoes = (sala.configEnsaios[tipo.name]?['localizacoes']?.toString() ?? '')
            .split(',')
            .map((texto) => texto.trim())
            .where((texto) => texto.isNotEmpty)
            .length;
        if (tipo == TipoEnsaio.velocidadeFluxo && localizacoes > 0 && localizacoes != pontos) {
          return 'A sala ${sala.nome} tem $pontos ponto(s) por filtro, mas $localizacoes localização(ões) informada(s). Ajuste para bater.';
        }
      }
    }

    for (final maquina in _handlingUnits) {
      final filtrosDaMaquina = _quantidadesPorEspecificacao(maquina.filtros);
      final filtrosDasSalas = _quantidadesPorEspecificacao(
        _salas.where((sala) => sala.handlingUnitId == maquina.id).expand((sala) => sala.filtros),
      );
      if (filtrosDaMaquina.length != filtrosDasSalas.length ||
          filtrosDaMaquina.entries.any((entry) => filtrosDasSalas[entry.key] != entry.value)) {
        return 'Distribua nas salas todos os filtros da máquina ${maquina.nome}, mantendo tipo, marca, modelo e dimensões.';
      }
    }
    return null;
  }

  void _salvarElaboracao() async {
    if (_salvando) return;
    final erroEstrutura = _validarEstruturaAntesDeSalvar();
    if (erroEstrutura != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroEstrutura), backgroundColor: Colors.amber),
      );
      return;
    }

    setState(() => _salvando = true);

    final agora = DateTime.now();
    final duplicado = await _projetoService.existeDuplicata(
      cnpjEmpresa: _empresaSelecionada!.cnpj,
      tipoProjeto: _tipoProjetoSelecionado!,
      area: _areaController.text,
      dataHora: agora,
    );
    if (duplicado) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Já existe um pré-relatório para esta empresa, tipo de teste e área neste mesmo minuto.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final id = 'PRJ-${agora.millisecondsSinceEpoch}';
    final projeto = ProjetoModel(
      id: id,
      cnpjEmpresa: _empresaSelecionada!.cnpj,
      tipoProjeto: _tipoProjetoSelecionado!,
      ferramentasRequeridas: _ferramentasRequeridasDosEnsaios,
      ferramentasEscaneadas: const {},
      sistemaId: _sistemaSelecionado?.id ?? '',
      area: _areaController.text.trim(),
      salas: List<SalaModel>.from(_salas),
      handlingUnits: List<HandlingUnitModel>.from(_handlingUnits),
      ensaiosSelecionados: _ensaiosSelecionados.map((t) => t.name).toList(),
      validadeTestesMeses: int.tryParse(_validadeController.text.trim()),
      // O relatório "nasce pronto" para o técnico assim que a elaboração é concluída.
      status: StatusRelatorio.prontoParaCampo,
      history: [
        HistoryEntry(
          usuario: widget.emailLogado,
          dataHora: DateTime.now(),
          campo: 'status',
          valorAntigo: 'rascunho',
          valorNovo: 'pronto_para_campo',
        ),
      ],
    );

    try {
      await _projetoService.salvarNovoProjeto(projeto, operadorResponsavel: widget.emailLogado, dataCriacao: agora);
      await _salvarResumosAlterados();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Relatório $id elaborado e pronto para o técnico!'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar elaboração: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _salvarResumosAlterados() async {
    for (final tipo in _ensaiosSelecionados) {
      final registro = _catalogoTestes[tipo.name];
      final texto = _resumoControllers[tipo.name]?.text.trim() ?? '';
      if (registro == null || registro.resumo == texto) continue;
      final atualizado = registro.copyWith(resumo: texto);
      await _testeCatalogoService.salvar(atualizado);
      _catalogoTestes[tipo.name] = atualizado;
    }
  }

  Widget _buildPreviewLateral() {
    return PreviewRelatorioWidget(
      nomeEmpresa: _empresaSelecionada?.nomeFantasia ?? '',
      cnpjEmpresa: _empresaSelecionada?.cnpj ?? '',
      tipoProjeto: _tipoProjetoSelecionado ?? '',
      sistemaNome: _sistemaSelecionado?.nome ?? '',
      area: _areaController.text,
      dataHora: DateTime.now(),
      handlingUnits: _handlingUnits,
      salas: _salas,
      ensaios: EnsaioModel.catalogoPadrao().map((e) => e.tipo).where(_ensaiosSelecionados.contains).toList(),
      resumosPorEnsaio: {for (final e in _resumoControllers.entries) e.key: e.value.text},
    );
  }

  void _removerMaquina(HandlingUnitModel h) async {
    final salasAtendidas = _salas.where((s) => s.handlingUnitId == h.id).toList();
    if (salasAtendidas.isNotEmpty) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remover máquina'),
          content: Text('${h.nome} é a máquina principal de ${salasAtendidas.length} sala(s). Elas também serão removidas.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remover')),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    setState(() {
      _salas.removeWhere((s) => s.handlingUnitId == h.id);
      for (var i = 0; i < _salas.length; i++) {
        final s = _salas[i];
        if (!s.handlingUnitIdsAdicionais.contains(h.id)) continue;
        _salas[i] = SalaModel(
          id: s.id,
          nome: s.nome,
          area: s.area,
          volume: s.volume,
          grau: s.grau,
          handlingUnitId: s.handlingUnitId,
          handlingUnitIdsAdicionais: s.handlingUnitIdsAdicionais.where((id) => id != h.id).toList(),
          filtros: s.filtros,
                            configEnsaios: s.configEnsaios,
        );
      }
      _handlingUnits.remove(h);
    });
  }

  @override
  Widget build(BuildContext context) {
    final formulario = _buildFormulario();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Elaboração do Relatório'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _plataformaComPreviewLateral
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: formulario),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 4,
                      child: Container(
                        color: Colors.grey[200],
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Pré-visualização do relatório',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 12),
                              _buildPreviewLateral(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : formulario,
    );
  }

  Widget _buildFormulario() {
    return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Empresa Cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: _abrirModalNovaEmpresa,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Nova Empresa'),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _cnpjSelecionado.isEmpty ? null : _cnpjSelecionado,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.business_center_outlined), hintText: 'Selecione a empresa'),
                    items: _empresas.map((e) => DropdownMenuItem(value: e.cnpj, child: Text(e.nomeFantasia))).toList(),
                    onChanged: (cnpj) {
                      if (cnpj == null) return;
                      setState(() {
                        _cnpjSelecionado = cnpj;
                        _empresaSelecionada = _empresas.firstWhere((e) => e.cnpj == cnpj);
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('Tipo de Projeto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  DropdownButtonFormField<String>(
                    initialValue: _tipoProjetoSelecionado,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined), hintText: 'Selecione o escopo do relatório'),
                    items: _tiposDeProjeto.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (t) => setState(() {
                      _tipoProjetoSelecionado = t;
                      final aplicaveis = EnsaioModel.catalogoDoTipo(t).map((e) => e.tipo).toSet();
                      _ensaiosSelecionados.retainWhere(aplicaveis.contains);
                    }),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sistema', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: _abrirModalNovoSistema,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Novo Sistema'),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _sistemaSelecionado?.id.isEmpty ?? true ? null : _sistemaSelecionado!.id,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.dns_outlined), hintText: 'Ex: HDA04'),
                    items: _sistemas.map((s) => DropdownMenuItem(value: s.id, child: Text(s.nome))).toList(),
                    onChanged: (id) => setState(() => _sistemaSelecionado = _sistemas.firstWhere((s) => s.id == id)),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _areaController,
                    decoration: const InputDecoration(labelText: 'Área atendida pelo sistema', prefixIcon: Icon(Icons.map_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _validadeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Validade dos testes (meses)', prefixIcon: Icon(Icons.event_repeat_outlined)),
                  ),
                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Máquinas (Handling Units)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: _abrirModalNovaHandlingUnit,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Adicionar'),
                      ),
                    ],
                  ),
                  if (_handlingUnits.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhuma máquina adicionada ainda.', style: TextStyle(color: Colors.grey)))
                  else
                    ..._handlingUnits.map((h) {
                      final atendidas = _salas.where((s) => s.atendidaPor(h.id)).map((s) => s.nome).toList();
                      return Card(
                        child: ListTile(
                          title: Text(h.nome),
                          subtitle: Text(
                            '${h.numero.isEmpty ? '' : 'Número: ${h.numero}\n'}'
                            '${h.filtros.isEmpty ? 'Sem filtros internos' : h.filtros.map((f) => f.descricao).join(', ')}'
                            '\nSalas atendidas: ${atendidas.isEmpty ? 'nenhuma' : atendidas.join(', ')}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _removerMaquina(h),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Salas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: _abrirModalNovaSala,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Adicionar Sala'),
                      ),
                    ],
                  ),
                  if (_salas.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhuma sala adicionada ainda.', style: TextStyle(color: Colors.grey)))
                  else
                    ..._salas.map((s) {
                      final maquinas = s.handlingUnitIds
                          .map((id) => _handlingUnits.where((h) => h.id == id).firstOrNull?.nome)
                          .whereType<String>()
                          .toList();
                      final filtros = s.filtros.isEmpty
                          ? 'sem filtros'
                          : s.filtros.map((f) => f.descricao).join(', ');
                      return Card(
                        child: ListTile(
                          title: Text('${s.nome} — Grau ${s.grau.name.toUpperCase()}'),
                          subtitle: Text(
                              '${s.area} m² · ${s.volume} m³ · $filtros\nMáquina${maquinas.length > 1 ? 's' : ''}: ${maquinas.isEmpty ? '-' : maquinas.join(', ')}'),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => setState(() => _salas.remove(s)),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 20),

                  const Text('Ensaios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (_tipoProjetoSelecionado == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Selecione o tipo de projeto para ver os ensaios.', style: TextStyle(color: Colors.grey)),
                    ),
                  ...(_tipoProjetoSelecionado == null
                          ? const <EnsaioModel>[]
                          : EnsaioModel.catalogoDoTipo(_tipoProjetoSelecionado))
                      .expand((ensaio) {
                    final selecionado = _ensaiosSelecionados.contains(ensaio.tipo);
                    final resumoController = _resumoControllers[ensaio.tipo.name];
                    return [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selecionado,
                        title: Text(ensaio.nome),
                        subtitle: Text('Ferramentas: ${ensaio.ferramentasNecessarias.join(', ')}'),
                        onChanged: (marcado) => setState(() {
                          if (marcado == true) {
                            _ensaiosSelecionados.add(ensaio.tipo);
                          } else {
                            _ensaiosSelecionados.remove(ensaio.tipo);
                          }
                        }),
                      ),
                      if (selecionado && resumoController != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 12),
                          child: TextField(
                            controller: resumoController,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Resumo do teste',
                              helperText: 'Compartilhado com a equipe; salvo ao concluir a elaboração.',
                            ),
                          ),
                        ),
                    ];
                  }),
                  _configuracaoEnsaiosDasSalas(),
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: _salvando ? null : _salvarElaboracao,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _salvando
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Concluir Elaboração', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                  ),
                ],
              ),
            );
  }
}

/// Editor dinâmico de filtros (tipo × quantidade + marca/modelo/dimensões); muta a lista recebida.
class _EditorFiltros extends StatefulWidget {
  final List<FiltroModel> filtros;
  final LocalizacaoFiltro localizacao;

  const _EditorFiltros({required this.filtros, required this.localizacao});

  @override
  State<_EditorFiltros> createState() => _EditorFiltrosState();
}

class _LinhaFiltro {
  final String id;
  TipoFiltro tipo;
  final quantidade = TextEditingController(text: '0');
  final marca = TextEditingController();
  final modelo = TextEditingController();
  final dimensoes = TextEditingController();

  _LinhaFiltro(this.id, this.tipo);

  int get qtd => int.tryParse(quantidade.text.trim()) ?? 0;

  void dispose() {
    quantidade.dispose();
    marca.dispose();
    modelo.dispose();
    dimensoes.dispose();
  }
}

class _EditorFiltrosState extends State<_EditorFiltros> {
  static const List<String> _marcasSugeridas = ['Trox'];
  final List<_LinhaFiltro> _linhas = [];
  int _sequencia = 0;

  @override
  void initState() {
    super.initState();
    // Uma linha por categoria (grosso/fino/absoluto); só entram no relatório as com quantidade > 0.
    for (final tipo in TipoFiltro.values) {
      _linhas.add(_novaLinha(tipo));
    }
  }

  _LinhaFiltro _novaLinha(TipoFiltro tipo) {
    final linha = _LinhaFiltro('FILTRO-${DateTime.now().microsecondsSinceEpoch}-${_sequencia++}', tipo);
    for (final c in [linha.quantidade, linha.marca, linha.modelo, linha.dimensoes]) {
      c.addListener(_sincronizar);
    }
    return linha;
  }

  void _sincronizar() {
    widget.filtros
      ..clear()
      ..addAll(_linhas.where((l) => l.qtd > 0).map((l) => FiltroModel(
            id: l.id,
            tipo: l.tipo,
            quantidade: l.qtd,
            localizacao: widget.localizacao,
            marca: l.marca.text.trim(),
            modelo: l.modelo.text.trim(),
            dimensoes: l.dimensoes.text.trim(),
          )));
  }

  @override
  void dispose() {
    for (final l in _linhas) {
      l.dispose();
    }
    super.dispose();
  }

  Widget _buildLinha(_LinhaFiltro linha) {
    return Container(
      key: ValueKey(linha.id),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: linha.qtd > 0 ? Colors.blue.shade200 : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TipoFiltro>(
                  initialValue: linha.tipo,
                  decoration: const InputDecoration(labelText: 'Tipo de filtro', isDense: true),
                  items: TipoFiltro.values.map((t) => DropdownMenuItem(value: t, child: Text(t.rotulo))).toList(),
                  onChanged: (t) => setState(() {
                    linha.tipo = t ?? linha.tipo;
                    _sincronizar();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: linha.quantidade,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qtd.', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Remover linha',
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setState(() {
                  _linhas.remove(linha);
                  linha.dispose();
                  _sincronizar();
                }),
              ),
            ],
          ),
          if (linha.qtd > 0)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: linha.marca,
                    decoration: InputDecoration(
                      labelText: 'Marca',
                      isDense: true,
                      suffixIcon: PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (m) => linha.marca.text = m,
                        itemBuilder: (_) => _marcasSugeridas.map((m) => PopupMenuItem(value: m, child: Text(m))).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: linha.modelo,
                    decoration: const InputDecoration(labelText: 'Modelo', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: linha.dimensoes,
                    decoration: const InputDecoration(labelText: 'Dimensões', hintText: '610x610x48', isDense: true),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._linhas.map(_buildLinha),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _linhas.add(_novaLinha(TipoFiltro.h14))),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Adicionar linha de filtro'),
          ),
        ),
        const Text('Filtros com quantidade 0 não entram no relatório.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _EditorFiltrosSala extends StatefulWidget {
  final HandlingUnitModel maquina;
  final List<SalaModel> salasExistentes;
  final List<FiltroModel> filtros;

  const _EditorFiltrosSala({super.key, required this.maquina, required this.salasExistentes, required this.filtros});

  @override
  State<_EditorFiltrosSala> createState() => _EditorFiltrosSalaState();
}

class _LinhaFiltroSala {
  final FiltroModel base;
  final int maxQuantidade;
  final TextEditingController quantidade;

  _LinhaFiltroSala({required this.base, required this.maxQuantidade}) : quantidade = TextEditingController(text: '0');

  int get qtd => int.tryParse(quantidade.text.trim()) ?? 0;

  String get descricao {
    final detalhes = [
      [base.marca, base.modelo].where((valor) => valor.isNotEmpty).join(' '),
      base.dimensoes,
    ].where((valor) => valor.isNotEmpty).join(', ');
    return '${base.tipo.rotulo}${detalhes.isEmpty ? '' : ' ($detalhes)'}';
  }

  void dispose() => quantidade.dispose();
}

class _EditorFiltrosSalaState extends State<_EditorFiltrosSala> {
  final List<_LinhaFiltroSala> _linhas = [];

  String _chave(FiltroModel filtro) => [
        filtro.tipo.name,
        filtro.marca.trim().toLowerCase(),
        filtro.modelo.trim().toLowerCase(),
        filtro.dimensoes.trim().toLowerCase(),
      ].join('|');

  @override
  void initState() {
    super.initState();
    final prototipos = <String, FiltroModel>{};
    final totais = <String, int>{};
    for (final filtro in widget.maquina.filtros) {
      final chave = _chave(filtro);
      prototipos[chave] = filtro;
      totais[chave] = (totais[chave] ?? 0) + filtro.quantidade;
    }

    final usados = <String, int>{};
    for (final sala in widget.salasExistentes.where((sala) => sala.handlingUnitId == widget.maquina.id)) {
      for (final filtro in sala.filtros) {
        final chave = _chave(filtro);
        usados[chave] = (usados[chave] ?? 0) + filtro.quantidade;
      }
    }

    for (final entrada in totais.entries) {
      _linhas.add(
        _LinhaFiltroSala(
          base: prototipos[entrada.key]!,
          maxQuantidade: (entrada.value - (usados[entrada.key] ?? 0)).clamp(0, entrada.value),
        ),
      );
    }
    _sincronizar();
  }

  void _sincronizar() {
    widget.filtros
      ..clear()
      ..addAll(
        _linhas.where((linha) => linha.qtd > 0).map(
              (linha) => FiltroModel(
                id: linha.base.id,
                tipo: linha.base.tipo,
                quantidade: linha.qtd,
                localizacao: LocalizacaoFiltro.terminal,
                marca: linha.base.marca,
                modelo: linha.base.modelo,
                dimensoes: linha.base.dimensoes,
              ),
            ),
      );
  }

  void _alterarQuantidade(_LinhaFiltroSala linha, String texto) {
    final valor = int.tryParse(texto.trim()) ?? 0;
    if (valor > linha.maxQuantidade) {
      linha.quantidade.text = linha.maxQuantidade.toString();
      linha.quantidade.selection = TextSelection.collapsed(offset: linha.quantidade.text.length);
    }
    setState(_sincronizar);
  }

  @override
  void dispose() {
    for (final linha in _linhas) {
      linha.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_linhas.isEmpty) {
      return const Text('A máquina selecionada não possui filtros cadastrados.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._linhas.map(
          (linha) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(linha.descricao)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 86,
                  child: TextField(
                    controller: linha.quantidade,
                    enabled: linha.maxQuantidade > 0,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Qtd.', helperText: 'Máx. ${linha.maxQuantidade}', isDense: true),
                    onChanged: (texto) => _alterarQuantidade(linha, texto),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Text(
          'A quantidade disponível considera somente esta máquina e as salas já cadastradas.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
