// lib/gestao_ferramentas_page.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_helper.dart';
import 'auth_service.dart';
import 'firestore_colecoes.dart';
import 'instrumento_model.dart';
import 'instrumento_service.dart';

class GestaoFerramentasPage extends StatefulWidget {
  final String emailLogado;

  const GestaoFerramentasPage({
    super.key, 
    required this.emailLogado,
  });

  @override
  State<GestaoFerramentasPage> createState() => _GestaoFerramentasPageState();
}

class _GestaoFerramentasPageState extends State<GestaoFerramentasPage> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final InstrumentoService _instrumentoService = InstrumentoService();

  List<InstrumentoModel> _listaFerramentas = [];
  bool _carregando = true;

  // Controllers para Nova Ferramenta
  final _formKeyAdd = GlobalKey<FormState>();
  final _tipoController = TextEditingController();
  final _tagController = TextEditingController();
  final _serieController = TextEditingController();
  final _certController = TextEditingController();
  final _validadeController = TextEditingController();

  // Campos para Atualizar Certificado
  final _formKeyUpdate = GlobalKey<FormState>();
  String? _tagSelecionadaParaAtualizar;
  final _novoCertController = TextEditingController();
  final _novaValidadeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sincronizarECarregarFerramentas();
  }

  @override
  void dispose() {
    _tipoController.dispose();
    _tagController.dispose();
    _serieController.dispose();
    _certController.dispose();
    _validadeController.dispose();
    _novoCertController.dispose();
    _novaValidadeController.dispose();
    super.dispose();
  }

  /// Carrega as ferramentas locais e tenta atualizar com dados da Nuvem de forma resiliente
  Future<void> _sincronizarECarregarFerramentas() async {
    setState(() => _carregando = true);
    final dominio = _authService.extrairDominio(widget.emailLogado);

    final listaFinal = await _instrumentoService.listarPorDominio(
      dominio,
      aoCarregarCacheLocal: (listaLocal) {
        // Resposta visual imediata com o cache local, antes da nuvem responder
        if (!mounted) return;
        setState(() => _listaFerramentas = listaLocal);
      },
    );

    if (!mounted) return;
    setState(() {
      _listaFerramentas = listaFinal;
      _carregando = false;
    });
  }

  /// Adiciona uma ferramenta localmente e na Nuvem
  void _adicionarFerramenta() async {
    if (!_formKeyAdd.currentState!.validate()) return;

    final dominio = _authService.extrairDominio(widget.emailLogado);
    final tagFormatada = _tagController.text.trim().toUpperCase();
    final idGerado = 'INST-${DateTime.now().millisecondsSinceEpoch}';

    final novoInstrumento = InstrumentoModel(
      id: idGerado,
      tipo: _tipoController.text.trim(),
      tag: tagFormatada,
      numeroSerie: _serieController.text.trim(),
      numeroCertificado: _certController.text.trim(),
      validade: _validadeController.text.trim(),
      estaValido: InstrumentoModel.validadeEhValida(_validadeController.text.trim()),
      dominioEmpresa: dominio,
    );

    // 1. Persistência Local (SQLite)
    int localResult = await _dbHelper.insertInstrumento(novoInstrumento.toMap());

    if (localResult > 0) {
      try {
        // 2. Sincronização na Nuvem (Firestore)
        await _firestore.collection(FirestoreColecoes.instrumentos).doc(tagFormatada).set(novoInstrumento.toMap());
      } catch (e) {
        debugPrint("Ferramenta salva offline. Sincronização pendente: $e");
      }

      // Limpa formulário e recarrega visual
      _tipoController.clear();
      _tagController.clear();
      _serieController.clear();
      _certController.clear();
      _validadeController.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ativo $tagFormatada cadastrado com sucesso!'), backgroundColor: Colors.green),
      );
      _sincronizarECarregarFerramentas();
    }
  }

  /// Gera uma planilha .xlsx com os ativos do domínio atual e abre o menu de compartilhamento/salvamento
  Future<void> _exportarPlanilha() async {
    try {
      final workbook = excel_pkg.Excel.createExcel();
      const nomeAba = 'Ferramentas';
      final nomeAbaOriginal = workbook.getDefaultSheet();
      final sheet = workbook[nomeAba];
      if (nomeAbaOriginal != null && nomeAbaOriginal != nomeAba) {
        workbook.delete(nomeAbaOriginal);
      }

      sheet.appendRow([
        excel_pkg.TextCellValue('TAG'),
        excel_pkg.TextCellValue('Tipo'),
        excel_pkg.TextCellValue('Numero de Serie'),
        excel_pkg.TextCellValue('Numero de Certificado'),
        excel_pkg.TextCellValue('Validade'),
      ]);

      for (final f in _listaFerramentas) {
        sheet.appendRow([
          excel_pkg.TextCellValue(f.tag),
          excel_pkg.TextCellValue(f.tipo),
          excel_pkg.TextCellValue(f.numeroSerie),
          excel_pkg.TextCellValue(f.numeroCertificado),
          excel_pkg.TextCellValue(f.validade),
        ]);
      }

      final bytes = workbook.encode();
      if (bytes == null) throw Exception('Falha ao gerar os bytes da planilha.');

      final dominio = _authService.extrairDominio(widget.emailLogado);
      final dir = await getTemporaryDirectory();
      final caminho = '${dir.path}/ferramentas_$dominio.xlsx';
      await File(caminho).writeAsBytes(bytes, flush: true);

      await Share.shareXFiles([XFile(caminho)], text: 'Planilha de ferramentas para atualização');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar planilha: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Normaliza um cabeçalho de coluna (remove acentos/espaços/caixa) para casar com nomes flexíveis
  String _normalizarCabecalho(String texto) {
    var s = texto.trim().toLowerCase();
    const comAcento = 'áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ';
    const semAcento = 'aaaaeeioooucAAAAEEIOOOUC';
    for (var i = 0; i < comAcento.length; i++) {
      s = s.replaceAll(comAcento[i], semAcento[i]);
    }
    return s.replaceAll(' ', '');
  }

  /// Lê um arquivo .xlsx ou .csv e devolve as linhas como texto puro (linha 0 = cabeçalho)
  List<List<String>> _lerLinhasDaPlanilha(String nomeArquivo, List<int> bytes) {
    if (nomeArquivo.toLowerCase().endsWith('.csv')) {
      final texto = utf8.decode(bytes, allowMalformed: true);
      final linhasCsv = const CsvToListConverter(eol: '\n').convert(texto);
      return linhasCsv.map((linha) => linha.map((c) => c?.toString().trim() ?? '').toList()).toList();
    }

    final workbook = excel_pkg.Excel.decodeBytes(bytes);
    final primeiraAba = workbook.tables.keys.first;
    final sheet = workbook.tables[primeiraAba]!;
    return sheet.rows
        .map((linha) => linha.map((celula) => celula?.value?.toString().trim() ?? '').toList())
        .toList();
  }

  /// Importa uma planilha .xlsx/.csv exportada (e editada) pelo usuário, atualizando/criando ativos por TAG
  Future<void> _importarPlanilha() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    final arquivo = resultado?.files.single;
    if (arquivo?.bytes == null) return;

    List<List<String>> linhas;
    try {
      linhas = _lerLinhasDaPlanilha(arquivo!.name, arquivo.bytes!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao ler o arquivo: $e'), backgroundColor: Colors.red),
      );
      return;
    }
    if (linhas.isEmpty) return;

    final cabecalho = linhas.first.map(_normalizarCabecalho).toList();
    final idxTag = cabecalho.indexOf('tag');
    final idxTipo = cabecalho.indexOf('tipo');
    final idxSerie = cabecalho.indexWhere((h) => h.contains('serie'));
    final idxCert = cabecalho.indexWhere((h) => h.contains('certificado'));
    final idxValidade = cabecalho.indexOf('validade');

    if (idxTag == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coluna TAG não encontrada na planilha.'), backgroundColor: Colors.red),
      );
      return;
    }

    String valorDaColuna(List<String> linha, int idx) => (idx != -1 && idx < linha.length) ? linha[idx].trim() : '';

    final dominio = _authService.extrairDominio(widget.emailLogado);
    int criados = 0, atualizados = 0, ignorados = 0;

    for (var i = 1; i < linhas.length; i++) {
      final linha = linhas[i];
      final tag = valorDaColuna(linha, idxTag).toUpperCase();
      if (tag.isEmpty) continue;

      final tipo = valorDaColuna(linha, idxTipo);
      final serie = valorDaColuna(linha, idxSerie);
      final cert = valorDaColuna(linha, idxCert);
      final validade = valorDaColuna(linha, idxValidade);

      final existentes = _listaFerramentas.where((f) => f.tag == tag);

      if (existentes.isEmpty) {
        if (tipo.isEmpty) {
          ignorados++;
          continue; // sem tipo não é possível cadastrar um novo ativo
        }
        final novo = InstrumentoModel(
          tipo: tipo,
          tag: tag,
          numeroSerie: serie,
          numeroCertificado: cert,
          validade: validade,
          estaValido: InstrumentoModel.validadeEhValida(validade),
          dominioEmpresa: dominio,
        );
        await _dbHelper.insertInstrumento(novo.toMap());
        try {
          await _firestore.collection(FirestoreColecoes.instrumentos).doc(tag).set(novo.toMap());
        } catch (e) {
          debugPrint('Novo ativo $tag salvo offline: $e');
        }
        criados++;
      } else {
        final camposAtualizados = <String, dynamic>{};
        if (tipo.isNotEmpty) camposAtualizados['tipo'] = tipo;
        if (serie.isNotEmpty) camposAtualizados['numeroSerie'] = serie;
        if (cert.isNotEmpty) camposAtualizados['numeroCertificado'] = cert;
        if (validade.isNotEmpty) {
          camposAtualizados['validade'] = validade;
          camposAtualizados['estaValido'] = InstrumentoModel.validadeEhValida(validade) ? 1 : 0;
        }
        if (camposAtualizados.isEmpty) {
          ignorados++;
          continue;
        }

        await _dbHelper.updateInstrumentoPorTag(tag, camposAtualizados);
        try {
          await _firestore.collection(FirestoreColecoes.instrumentos).doc(tag).set(camposAtualizados, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Atualização de $tag salva offline: $e');
        }
        atualizados++;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Importação concluída: $criados criados, $atualizados atualizados, $ignorados ignorados.'),
        backgroundColor: Colors.green,
      ),
    );
    _sincronizarECarregarFerramentas();
  }

  /// Atualiza o certificado e validade de uma ferramenta existente
  void _atualizarCertificado() async {
    if (!_formKeyUpdate.currentState!.validate() || _tagSelecionadaParaAtualizar == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione uma TAG válida.'), backgroundColor: Colors.amber),
      );
      return;
    }

    final tagAlvo = _tagSelecionadaParaAtualizar!;
    final novoCertificado = _novoCertController.text.trim();
    final novaValidade = _novaValidadeController.text.trim();

    final dadosAtualizadosSqlite = {
      'numeroCertificado': novoCertificado,
      'validade': novaValidade,
      'estaValido': InstrumentoModel.validadeEhValida(novaValidade) ? 1 : 0,
    };

    // 1. Atualização Local (SQLite)
    int localResult = await _dbHelper.updateInstrumentoPorTag(tagAlvo, dadosAtualizadosSqlite);

    if (localResult > 0) {
      try {
        // 2. Atualização na Nuvem (Firestore usando merge para não deletar os outros campos)
        final bool validadeOk = InstrumentoModel.validadeEhValida(novaValidade);
        await _firestore.collection(FirestoreColecoes.instrumentos).doc(tagAlvo).set({
          'numeroCertificado': novoCertificado,
          'validade': novaValidade,
          'estaValido': validadeOk ? 1 : 0,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Atualização salva em cache offline: $e");
      }

      _novoCertController.clear();
      _novaValidadeController.clear();
      setState(() => _tagSelecionadaParaAtualizar = null);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calibração da TAG $tagAlvo atualizada com sucesso!'), backgroundColor: Colors.green),
      );
      _sincronizarECarregarFerramentas();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Gestão de Ativos & Ferramental'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCardImportExport(),
                  const SizedBox(height: 24),
                  _buildCardCadastro(),
                  const SizedBox(height: 24),
                  _buildCardAtualizacao(),
                  const SizedBox(height: 24),
                  _buildSeccaoListaVisual(),
                ],
              ),
            ),
    );
  }

  Widget _buildCardImportExport() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Atualização em Massa via Planilha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900])),
            const SizedBox(height: 8),
            const Text(
              'Exporte os ativos atuais, edite os dados no Excel e importe novamente para atualizar tudo de uma vez.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportarPlanilha,
                    icon: const Icon(Icons.file_download),
                    label: const Text('Exportar Planilha'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _importarPlanilha,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Importar Planilha'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardCadastro() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKeyAdd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cadastrar Nova Ferramenta Padrão', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900])),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tipoController,
                decoration: const InputDecoration(labelText: 'Tipo do Instrumento (Ex: Manômetro)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.construction)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira o tipo' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'TAG Única (Ex: MAN-011)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.tag)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira a TAG' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _serieController,
                decoration: const InputDecoration(labelText: 'Número de Série', border: OutlineInputBorder(), prefixIcon: Icon(Icons.fingerprint)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira o número de série' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _certController,
                decoration: const InputDecoration(labelText: 'Nº Certificado / Licença de Calibração', border: OutlineInputBorder(), prefixIcon: Icon(Icons.gavel)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira o certificado' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _validadeController,
                decoration: const InputDecoration(labelText: 'Validade da Calibração (MM/AAAA)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Insira a validade' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _adicionarFerramenta,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Center(child: Text('Registrar Ativo no Sistema', style: TextStyle(fontWeight: FontWeight.bold))),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardAtualizacao() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKeyUpdate,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Renovação de Calibração / Certificado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900])),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _tagSelecionadaParaAtualizar,
                hint: const Text('Selecione a TAG do equipamento'),
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.tag)),
                items: _listaFerramentas.map((f) {
                  return DropdownMenuItem(value: f.tag, child: Text('${f.tag} - ${f.tipo}'));
                }).toList(),
                onChanged: (val) => setState(() => _tagSelecionadaParaAtualizar = val),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _novoCertController,
                decoration: const InputDecoration(labelText: 'Novo Número do Certificado', border: OutlineInputBorder(), prefixIcon: Icon(Icons.gavel)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _novaValidadeController,
                decoration: const InputDecoration(labelText: 'Nova Validade (MM/AAAA)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _atualizarCertificado,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Center(child: Text('Atualizar Dados de Calibração', style: TextStyle(fontWeight: FontWeight.bold))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeccaoListaVisual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text('Ativos Cadastrados no seu Domínio (${_listaFerramentas.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        _listaFerramentas.isEmpty
            ? const Card(child: ListTile(title: Text('Nenhum ativo localizado para o seu domínio organizacional.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _listaFerramentas.length,
                itemBuilder: (context, index) {
                  final f = _listaFerramentas[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.blue[50], child: Icon(Icons.handyman, color: Colors.blue[800])),
                      title: Text('${f.tag} — ${f.tipo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Série: ${f.numeroSerie} | Certificado: ${f.numeroCertificado}\nValidade: ${f.validade}', style: const TextStyle(fontSize: 12)),
                      trailing: Icon(
                        Icons.check_circle,
                        color: InstrumentoModel.validadeEhValida(f.validade) ? Colors.green : Colors.grey,
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }
}