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

  static const List<String> _tiposDeProjeto = [
    'Fluxo Laminar',
    'Ar Comprimido',
    'Cabine de Exaustão',
    'HVAC',
    'Teste',
  ];

  bool _carregando = true;
  bool _salvando = false;

  List<EmpresaModel> _empresas = [];
  List<SistemaModel> _sistemas = [];

  String _cnpjSelecionado = '';
  EmpresaModel? _empresaSelecionada;
  String? _tipoProjetoSelecionado;
  SistemaModel? _sistemaSelecionado;
  final _areaController = TextEditingController();

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
                                .map((h) => DropdownMenuItem(value: h.id, child: Text(h.nome, overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (id) => setModalState(() => handlingUnitIdSelecionado = id ?? handlingUnitIdSelecionado),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Filtros (saídas) da Sala', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _EditorFiltros(filtros: filtrosTemp, localizacao: LocalizacaoFiltro.terminal),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (nomeController.text.trim().isEmpty) return;
                        setState(() {
                          _salas.add(SalaModel(
                            id: 'SALA-${DateTime.now().microsecondsSinceEpoch}',
                            nome: nomeController.text.trim(),
                            area: double.tryParse(areaController.text.replaceAll(',', '.')) ?? 0,
                            volume: double.tryParse(volumeController.text.replaceAll(',', '.')) ?? 0,
                            grau: grauSelecionado,
                            handlingUnitId: handlingUnitIdSelecionado,
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

  void _abrirModalNovaHandlingUnit() {
    final nomeController = TextEditingController();
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

  void _salvarElaboracao() async {
    if (_empresaSelecionada == null || _tipoProjetoSelecionado == null || _salvando) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione a empresa e o tipo de projeto.'), backgroundColor: Colors.amber),
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
          content: Text('${h.nome} atende ${salasAtendidas.length} sala(s). Elas também serão removidas.'),
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
                    onChanged: (t) => setState(() => _tipoProjetoSelecionado = t),
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
                      final atendidas = _salas.where((s) => s.handlingUnitId == h.id).map((s) => s.nome).toList();
                      return Card(
                        child: ListTile(
                          title: Text(h.nome),
                          subtitle: Text(
                            '${h.filtros.isEmpty ? 'Sem filtros internos' : h.filtros.map((f) => '${f.quantidade}× ${f.tipo.name.toUpperCase()}').join(', ')}'
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
                      final maquina = _handlingUnits.where((h) => h.id == s.handlingUnitId).firstOrNull;
                      final filtros = s.filtros.isEmpty
                          ? 'sem filtros'
                          : s.filtros.map((f) => '${f.quantidade}× ${f.tipo.name.toUpperCase()}').join(', ');
                      return Card(
                        child: ListTile(
                          title: Text('${s.nome} — Grau ${s.grau.name.toUpperCase()}'),
                          subtitle: Text('${s.area} m² · ${s.volume} m³ · $filtros\nMáquina: ${maquina?.nome ?? '-'}'),
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
                  ...EnsaioModel.catalogoPadrao().expand((ensaio) {
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

/// Editor de filtros G4/F9/H14 (tipo + quantidade) usado nos modais de máquina e de sala.
/// Muta diretamente a lista recebida.
class _EditorFiltros extends StatefulWidget {
  final List<FiltroModel> filtros;
  final LocalizacaoFiltro localizacao;

  const _EditorFiltros({required this.filtros, required this.localizacao});

  @override
  State<_EditorFiltros> createState() => _EditorFiltrosState();
}

class _EditorFiltrosState extends State<_EditorFiltros> {
  TipoFiltro _tipo = TipoFiltro.g4;
  final _qtdController = TextEditingController(text: '1');

  @override
  void dispose() {
    _qtdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<TipoFiltro>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo de filtro'),
                items: TipoFiltro.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase())))
                    .toList(),
                onChanged: (t) => setState(() => _tipo = t ?? TipoFiltro.g4),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _qtdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Qtd.'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue),
              onPressed: () {
                final qtd = int.tryParse(_qtdController.text) ?? 0;
                if (qtd <= 0) return;
                setState(() {
                  widget.filtros.add(FiltroModel(
                    id: 'FILTRO-${DateTime.now().microsecondsSinceEpoch}',
                    tipo: _tipo,
                    quantidade: qtd,
                    localizacao: widget.localizacao,
                  ));
                });
              },
            ),
          ],
        ),
        ...widget.filtros.map((f) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${f.tipo.name.toUpperCase()} — ${f.quantidade} un.'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setState(() => widget.filtros.remove(f)),
              ),
            )),
      ],
    );
  }
}
