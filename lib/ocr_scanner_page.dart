// lib/ocr_scanner_page.dart
/*import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';
import 'instrumento_model.dart';
import 'relatorio_service.dart';

class OcrScannerPage extends StatefulWidget {
  final String idProjeto;
  final String tipoProjeto;
  // Recebe o mapa completo com os dados reais recuperados via QR Code
  final Map<String, InstrumentoModel> ferramentasVinculadas; 
  final String assetTemplatePath; // Caminho do arquivo .docx recebido do Dropdown

  const OcrScannerPage({
    super.key,
    required this.idProjeto,
    required this.tipoProjeto,
    required this.ferramentasVinculadas,
    required this.assetTemplatePath,
  });

  @override
  State<OcrScannerPage> createState() => _OcrScannerPageState();
}

class _OcrScannerPageState extends State<OcrScannerPage> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final RelatorioService _relatorioService = RelatorioService();
  
  bool _estaProcessando = false;
  bool _jaDetectou = false;

  @override
  void initState() {
    super.initState();
    _inicializarCamera();
  }

  Future<void> _inicializarCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final cameraTraseira = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      cameraTraseira,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;

      _cameraController!.startImageStream((CameraImage imagemFrame) {
        if (_estaProcessando || _jaDetectou) return;
        _processarFrameOcr(imagemFrame);
      });

      setState(() {});
    } catch (e) {
      debugPrint('Erro ao iniciar câmera: $e');
    }
  }

  Future<void> _processarFrameOcr(CameraImage image) async {
    _estaProcessando = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = (await availableCameras()).first;
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputMetadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputMetadata);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      String textoLimpo = recognizedText.text.trim();
      // Detecta se há números no frame capturado
      if (textoLimpo.isNotEmpty && !_jaDetectou && RegExp(r'[0-9]').hasMatch(textoLimpo)) {
        _jaDetectou = true;
        await _cameraController?.stopImageStream();
        
        if (mounted) {
          _solicitarValidacaoUsuario(textoLimpo);
        }
      }
    } catch (e) {
      debugPrint('Erro no processamento do OCR: $e');
    } finally {
      _estaProcessando = false;
    }
  }

  // Janela modal para conferência e ajuste do valor lido pelo OCR
  void _solicitarValidacaoUsuario(String textoInicial) {
    final TextEditingController ocrController = TextEditingController(text: textoInicial);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Colors.blue),
            SizedBox(width: 8),
            Text('Confirmar Leitura OCR'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('O sistema detectou o seguinte valor no display. Ajuste caso necessário:'),
            const SizedBox(height: 12),
            TextField(
              controller: ocrController,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Valor Medido',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _jaDetectou = false;
              await _cameraController?.startImageStream((CameraImage imagemFrame) {
                if (_estaProcessando || _jaDetectou) return;
                _processarFrameOcr(imagemFrame);
              });
            },
            child: const Text('Tentar Novamente', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _compilarRelatorioFinalComDados(ocrController.text);
            },
            child: const Text('Confirmar & Gerar Word'),
          ),
        ],
      ),
    );
  }

  // Recupera as informações reais escaneadas anteriormente e gera o arquivo Word preenchido
  Future<void> _compilarRelatorioFinalComDados(String valorValidado) async {
    // Busca o primeiro instrumento real contido no mapa enviado pelo QR Code
    InstrumentoModel instrumentoReal;

    if (widget.ferramentasVinculadas.isNotEmpty) {
      instrumentoReal = widget.ferramentasVinculadas.values.first;
    } else {
      // Fallback de segurança caso o mapa venha vazio por algum motivo imprevisto
      instrumentoReal = InstrumentoModel(
        tag: 'TAG-IGNORADA',
        numeroSerie: 'S/N',
        numeroCertificado: 'S/C',
        validade: 'S/V',
        estaValido: false
      );
    }

    // Abre o indicador de progresso (Spinner)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Dispara a geração passando o arquivo de template dinâmico correspondente ao projeto
    final File? arquivoDocxFinal = await _relatorioService.gerarRelatorioPreenchido(
      instrumento: instrumentoReal,
      nomeProjeto: 'RELATORIO_${widget.tipoProjeto.replaceAll(' ', '_')}',
      assetTemplatePath: widget.assetTemplatePath,
    );

    if (!mounted) return;
    Navigator.pop(context); // Fecha o Spinner de carregamento

    if (arquivoDocxFinal != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text('Relatório Gerado!'),
            ],
          ),
          content: Text(
            'Processo concluído com sucesso!\n\n'
            'Escopo do Projeto: ${widget.tipoProjeto}\n'
            'Valor Injetado via OCR: $valorValidado\n\n'
            'O documento Word foi salvo em:\n${arquivoDocxFinal.path}'
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context); // Retorna para a NovoProjetoPage / Início
              },
              child: const Text('Finalizar Fluxo'),
            )
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao injetar os dados salvos no template Word.')),
      );
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Leitura OCR: ${widget.tipoProjeto}'),
      ),
      body: Stack(
        children: [
          CameraPreview(_cameraController!),
          Center(
            child: Container(
              width: 280,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 3),
                borderRadius: BorderRadius.circular(8),
                color: Colors.transparent,
              ),
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Text(
                    'Posicione o display numérico aqui',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, backgroundColor: Colors.white54),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
*/