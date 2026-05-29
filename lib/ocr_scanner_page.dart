// lib/ocr_scanner_page.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';

class OcrScannerPage extends StatefulWidget {
  const OcrScannerPage({super.key});

  @override
  State<OcrScannerPage> createState() => _OcrScannerPageState();
}

class _OcrScannerPageState extends State<OcrScannerPage> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _estaProcessando = false;
  bool _jaDetectou = false;

  @override
  void initState() {
    super.initState();
    _inicializarCamera();
  }

  // Localiza a câmera traseira do celular e inicia o fluxo de frames
  Future<void> _inicializarCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    // Filtra para usar a câmera traseira
    final cameraTraseira = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      cameraTraseira,
      ResolutionPreset.medium, // Resolução média é ideal e mais leve para o OCR
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;

      // Inicia a escuta de frames da câmera em tempo real
      _cameraController!.startImageStream((CameraImage imagemFrame) {
        if (_estaProcessando || _jaDetectou) return;
        _processarFrameOcr(imagemFrame);
      });

      setState(() {});
    } catch (e) {
      debugPrint('Erro ao iniciar câmera: $e');
    }
  }

  // Converte o frame bruto da câmera no formato que o Google ML Kit entende
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
      
      // Executa o reconhecimento de texto do frame
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // Se encontrou algum texto legível no display
      if (recognizedText.text.trim().isNotEmpty && !_jaDetectou) {
        _jaDetectou = true;
        _cameraController?.stopImageStream();
        
        // Retorna para a HomePage passando o bloco de texto lido
        if (mounted) {
          Navigator.pop(context, recognizedText.text);
        }
      }
    } catch (e) {
      debugPrint('Erro no processamento do OCR: $e');
    } finally {
      _estaProcessando = false;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close(); // Libera o motor do ML Kit da memória
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
        title: const Text('Leitura de Display (OCR)'),
      ),
      body: Stack(
        children: [
          // Exibe o preview em tela cheia
          CameraPreview(_cameraController!),
          
          // Máscara guia (Retângulo) simulando onde posicionar o display
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
                    'Posicione o display aqui',
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