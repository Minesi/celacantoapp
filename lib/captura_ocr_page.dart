// lib/captura_ocr_page.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; // Motor real do OCR

class CapturaOcrPage extends StatefulWidget {
  final String? idProjeto;
  final String? tipoProjeto;

  const CapturaOcrPage({
    super.key,
    this.idProjeto,
    this.tipoProjeto,
  });

  @override
  State<CapturaOcrPage> createState() => _CapturaOcrPageState();
}

class _CapturaOcrPageState extends State<CapturaOcrPage> {
  CameraController? _cameraController;
  bool _mostrarDigitacaoManual = false;
  bool _erroNaCamera = false;
  bool _processandoOcr = false; // Estado visual de carregamento analítico
  final TextEditingController _ocrManualController = TextEditingController();

  // Instancia o Reconhecedor de Texto do Google ML Kit
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  // --- CONTROLE DE ESTADO DO FLUXO DE MEDIÇÕES ---
  List<String> _ferramentasDoProjeto = [];
  int _indiceFerramentaAtual = 0;
  int _tentativaLeituraAtual = 1; 

  final List<Map<String, dynamic>> _leiturasRegistradasFinal = [];
  String _valorLeitura1SendoFeita = '';

  @override
  void initState() {
    super.initState();
    _definirEscopoDeFerramentas();
    _inicializarCameraDoDispositivo();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _ocrManualController.dispose();
    _textRecognizer.close(); // Fecha o motor analítico para evitar vazamento de memória
    super.dispose();
  }

  void _definirEscopoDeFerramentas() {
    final tipo = widget.tipoProjeto ?? '';
    if (tipo.contains('Fluxo Laminar')) {
      _ferramentasDoProjeto = ['Anemômetro', 'Manômetro Diferencial'];
    } else if (tipo.contains('Área Limpa')) {
      _ferramentasDoProjeto = ['Manômetro Diferencial', 'Anemômetro'];
    } else {
      _ferramentasDoProjeto = ['Manômetro Diferencial'];
    }
  }

  Future<void> _inicializarCameraDoDispositivo() async {
    try {
      final listaDeCameras = await availableCameras();
      if (listaDeCameras.isEmpty) {
        setState(() => _erroNaCamera = true);
        return;
      }

      _cameraController = CameraController(
        listaDeCameras.first,
        ResolutionPreset.high, // Alta definição para o OCR ler números pequenos perfeitamente
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Erro ao abrir hardware da câmera: $e');
      setState(() => _erroNaCamera = true);
    }
  }

  // --- REGRA ESSENCIAL: PROCESSAMENTO DO TEXTO EXTRAÍDO PELO MOTOR REAL ---
  Future<void> _baterFotoEProcessarOcr() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _processandoOcr) {
      return;
    }

    setState(() {
      _processandoOcr = true;
    });

    try {
      // 1. Tira o snapshot físico usando a câmera do celular
      final XFile arquivoFotoBruta = await _cameraController!.takePicture();
      
      // 2. Transforma o arquivo gerado em uma estrutura que o ML Kit compreende
      final InputImage imagemParaProcessar = InputImage.fromFilePath(arquivoFotoBruta.path);
      
      // 3. Executa a extração matemática do texto na imagem
      final RecognizedText resultadoMapeamentoTexto = await _textRecognizer.processImage(imagemParaProcessar);
      
      String textoBrutoLimpo = resultadoMapeamentoTexto.text;
      debugPrint('TEXTO BRUTO DETECTADO PELO OCR: $textoBrutoLimpo');

      // 4. Filtro Inteligente: Isola números e decimais para facilitar para o técnico
      // Busca padrões numéricos como: "24.5", "1,20", "0.03"
      final RegExp expressaoFiltroNumerico = RegExp(r'\d+[\.,]\d+|\d+');
      final Iterable<Match> correspondencias = expressaoFiltroNumerico.allMatches(textoBrutoLimpo);

      String valorFinalFiltrado = '';
      if (correspondencias.isNotEmpty) {
        // Pega o primeiro número claro localizado no display da ferramenta
        valorFinalFiltrado = correspondencias.first.group(0)!.replaceAll(',', '.');
      } else {
        // Se o display contiver ruído, traz apenas as primeiras linhas limpas sem quebras
        valorFinalFiltrado = textoBrutoLimpo.split('\n').first.trim();
      }

      if (valorFinalFiltrado.isEmpty) {
        valorFinalFiltrado = "0.0";
      }

      setState(() {
        _processandoOcr = false;
      });

      // 5. Envia o resultado filtrado para a validação em caixa de diálogo do técnico
      _processarValorCapturado(valorFinalFiltrado);

    } catch (e) {
      setState(() {
        _processandoOcr = false;
      });
      debugPrint('Falha no motor OCR: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao processar imagem. Digite manualmente ou tente novamente.')),
      );
    }
  }

  void _processarValorCapturado(String valorLido) {
    _ocrManualController.clear();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.analytics_outlined, color: Colors.blue, size: 40),
          title: Text('Confirmar Medição - $_tentativaLeituraAtualª Coleta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ferramenta Atual:\n${_ferramentasDoProjeto[_indiceFerramentaAtual]}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 16),
              const Text('O sistema interpretou o seguinte valor no display:'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Text(
                  valorLido,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontFamily: 'Courier'),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context); // Fecha diálogo e permite tirar outra foto
              },
              icon: const Icon(Icons.refresh, color: Colors.red),
              label: const Text('Refazer', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _registrarEAvancarFluxo(valorLido);
              },
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('Confirmar', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
            ),
          ],
        );
      },
    );
  }

  void _registrarEAvancarFluxo(String valorDefinitivo) {
    if (_tentativaLeituraAtual == 1) {
      _valorLeitura1SendoFeita = valorDefinitivo;
      
      // Pergunta se deseja coletar a segunda medição para a mesma ferramenta
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.add_chart_rounded, color: Colors.orange, size: 40),
          title: const Text('Nova Medição?'),
          content: Text('Deseja realizar a segunda leitura (Leitura 2) para a ferramenta ${_ferramentasDoProjeto[_indiceFerramentaAtual]}?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Usuário não quis a segunda leitura, salva apenas a primeira
                _salvarMapeamentoCompletoDaFerramenta(leitura1: _valorLeitura1SendoFeita, leitura2: '');
              },
              child: const Text('Não, Avançar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _tentativaLeituraAtual = 2; // Seta para capturar o segundo valor
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
              child: const Text('Sim, Coletar Leitura 2', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    } else {
      // É a leitura 2, consolida o mapa
      _salvarMapeamentoCompletoDaFerramenta(leitura1: _valorLeitura1SendoFeita, leitura2: valorDefinitivo);
    }
  }

  void _salvarMapeamentoCompletoDaFerramenta({required String leitura1, required String leitura2}) {
    _leiturasRegistradasFinal.add({
      'ferramenta': _ferramentasDoProjeto[_indiceFerramentaAtual],
      'leitura_1': leitura1,
      'leitura_2': leitura2,
    });

    if (_indiceFerramentaAtual + 1 < _ferramentasDoProjeto.length) {
      // Vai para a próxima ferramenta obrigatória do escopo
      setState(() {
        _indiceFerramentaAtual++;
        _tentativaLeituraAtual = 1;
        _valorLeitura1SendoFeita = '';
        _mostrarDigitacaoManual = false;
      });
    } else {
      // Finalizou o circuito de todas as ferramentas, retorna a lista estruturada para a página pai
      Navigator.pop(context, _leiturasRegistradasFinal);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erroNaCamera) {
      return Scaffold(
        appBar: AppBar(title: const Text('Coleta OCR')),
        body: const Center(child: Text('Hardware da câmera indisponível ou permissão negada.')),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OCR: ${_ferramentasDoProjeto[_indiceFerramentaAtual]}'),
            Text(
              'Etapa ${_indiceFerramentaAtual + 1} de ${_ferramentasDoProjeto.length} | L$_tentativaLeituraAtual',
              style: const TextStyle(color: Colors.amber, fontSize: 11),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Tela cheia com o preview real da Câmera
          Positioned.fill(
            child: CameraPreview(_cameraController!),
          ),

          // Alvo guia visual centralizado para o técnico alinhar o display numérico
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: _processandoOcr ? Colors.amber : Colors.green, width: 3),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withOpacity(0.15), // <-- Alterado de backgroundColor para color
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    color: _processandoOcr ? Colors.amber : Colors.green,
                    child: Text(
                      _processandoOcr ? 'PROCESSANDO REALTIME...' : 'ALINHE O DISPLAY AQUI',
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Botões Flutuantes Inferiores
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Alternador para Digitação Manual em caso de reflexo/falha de luz
                    FloatingActionButton(
                      heroTag: 'btn_manual',
                      backgroundColor: Colors.orange[800],
                      onPressed: () => setState(() => _mostrarDigitacaoManual = !_mostrarDigitacaoManual),
                      child: Icon(_mostrarDigitacaoManual ? Icons.camera : Icons.keyboard, color: Colors.white),
                    ),
                    
                    // Botão Central de Disparo de Foto + Processamento Analítico
                    GestureDetector(
                      onTap: _processandoOcr ? null : _baterFotoEProcessarOcr,
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: _processandoOcr ? Colors.grey : Colors.white,
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: _processandoOcr ? Colors.grey[700] : Colors.blue[900],
                          child: _processandoOcr 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Icon(Icons.document_scanner, color: Colors.white, size: 30),
                        ),
                      ),
                    ),
                    
                    // Cancelador de Circuito
                    FloatingActionButton(
                      heroTag: 'btn_cancelar',
                      backgroundColor: Colors.red[900],
                      onPressed: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Drawer de Inserção Teclada Manual (Caso precise burlar falhas em campo)
          if (_mostrarDigitacaoManual)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Inserção Manual de Segurança',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ocrManualController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Valor para Leitura $_tentativaLeituraAtual',
                          border: const OutlineInputBorder(),
                          hintText: 'Ex: 24.5 ou 1.15',
                          prefixIcon: const Icon(Icons.speed),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              if (_ocrManualController.text.trim().isNotEmpty) {
                                String valorDigitado = _ocrManualController.text.trim();
                                _processarValorCapturado(valorDigitado);
                              }
                            },
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: const Text('Confirmar Medição', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}