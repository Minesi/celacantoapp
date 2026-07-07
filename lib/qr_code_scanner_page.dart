// lib/qr_code_scanner_page.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // Usado para a webcam no Windows
import 'package:mobile_scanner/mobile_scanner.dart' as mobile; // Usado para o mobile

class QrCodeScannerPage extends StatefulWidget {
  const QrCodeScannerPage({super.key});

  @override
  State<QrCodeScannerPage> createState() => _QrCodeScannerPageState();
}

class _QrCodeScannerPageState extends State<QrCodeScannerPage> {
  // Controle para Mobile (Android/iOS)
  mobile.MobileScannerController? _mobileController;

  // Controle para Desktop (Windows)
  CameraController? _windowsCameraController;
  
  bool _jaEscaneou = false;
  bool _mostrarDigitacaoManual = false;
  bool _erroNoHardwareDaCamera = false; 
  final TextEditingController _manualController = TextEditingController();

  // Identifica se estamos rodando nativamente no Windows Desktop
  bool get _isWindows => !kIsWeb && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _inicializarCameraCerta();
  }

  Future<void> _inicializarCameraCerta() async {
    if (_isWindows) {
      // Caminho Windows: Inicializa a Webcam usando o pacote 'camera' padrão
      try {
        final cameras = await availableCameras();
        if (cameras.isNotEmpty) {
          _windowsCameraController = CameraController(
            cameras.first,
            ResolutionPreset.medium,
            enableAudio: false,
          );
          await _windowsCameraController!.initialize();
          if (mounted) setState(() {});
        } else {
          _marcarErroCamera();
        }
      } catch (e) {
        _marcarErroCamera();
      }
    } else {
      // Caminho Mobile: Inicializa o MobileScanner
      try {
        _mobileController = mobile.MobileScannerController();
      } catch (e) {
        _marcarErroCamera();
      }
    }
  }

  void _marcarErroCamera() {
    if (mounted) {
      setState(() {
        _erroNoHardwareDaCamera = true;
        _mostrarDigitacaoManual = true;
      });
    }
  }

  @override
  void dispose() {
    // Libera os recursos de acordo com a plataforma ativa
    if (_isWindows) {
      _windowsCameraController?.dispose();
    } else {
      _mobileController?.dispose();
    }
    _manualController.dispose();
    super.dispose();
  }

  void _retornarCodigo(String codigo) {
    if (_jaEscaneou) return;
    setState(() => _jaEscaneou = true);
    Navigator.pop(context, codigo.trim().toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text(_isWindows ? 'Scanner de Ativo (Webcam Windows)' : 'Scanner de Ativo (Mobile)'),
        actions: [
          IconButton(
            icon: Icon(_mostrarDigitacaoManual ? Icons.videocam : Icons.keyboard),
            tooltip: _mostrarDigitacaoManual ? 'Ativar Câmera' : 'Digitação Manual',
            onPressed: () {
              setState(() {
                _mostrarDigitacaoManual = !_mostrarDigitacaoManual;
              });
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          setState(() {
            _mostrarDigitacaoManual = !_mostrarDigitacaoManual;
          });
        },
        backgroundColor: _mostrarDigitacaoManual ? Colors.green : Colors.blue,
        icon: Icon(_mostrarDigitacaoManual ? Icons.videocam : Icons.edit, color: Colors.white),
        label: Text(
          _mostrarDigitacaoManual ? 'Usar Câmera / Webcam' : 'Digitar Código Manual',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          // -------------------------------------------------------------------
          // FLUXO DE VISUALIZAÇÃO DA CÂMERA (Se o modo manual estiver desligado)
          // -------------------------------------------------------------------
          if (!_mostrarDigitacaoManual && !_erroNoHardwareDaCamera) ...[
            // Cenário A: Windows rodando Webcam Nativa
            if (_isWindows && _windowsCameraController != null && _windowsCameraController!.value.isInitialized)
              Positioned.fill(
                child: AspectRatio(
                  aspectRatio: _windowsCameraController!.value.aspectRatio,
                  child: CameraPreview(_windowsCameraController!),
                ),
              )
            // Cenário B: Android/iOS rodando MobileScanner
            else if (!_isWindows && _mobileController != null)
              mobile.MobileScanner(
                controller: _mobileController,
                errorBuilder: (context, error) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _marcarErroCamera();
                  });
                  return const SizedBox.shrink();
                },
                onDetect: (capture) {
                  final List<mobile.Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      _retornarCodigo(barcode.rawValue!);
                      break;
                    }
                  }
                },
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.blue)),

            // Máscara guia visual centralizada (Aparece para Windows e Mobile quando a câmera está aberta)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  if (_isWindows) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                      child: const Text(
                        'Modo Windows: Posicione o QR Code ou digite usando o botão abaixo',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  ]
                ],
              ),
            ),
          ],

          // -------------------------------------------------------------------
          // FLUXO DE DIGITAÇÃO MANUAL (Disponível em ambas as plataformas)
          // -------------------------------------------------------------------
          if (_mostrarDigitacaoManual || _erroNoHardwareDaCamera)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isWindows ? Icons.desktop_windows : Icons.phone_android, 
                              color: Colors.blue
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _erroNoHardwareDaCamera ? 'Falha na Câmera - Entrada Manual' : 'Digitação Manual do Ativo', 
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Caso não consiga realizar a leitura pela câmera, insira a TAG/Número de Série do equipamento manualmente para prosseguir.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _manualController,
                          decoration: const InputDecoration(
                            labelText: 'Código da TAG / Número de Série',
                            border: OutlineInputBorder(),
                            hintText: 'Ex: MAN-011',
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!_erroNoHardwareDaCamera)
                              TextButton(
                                onPressed: () => setState(() => _mostrarDigitacaoManual = false),
                                child: const Text('Voltar para Câmera'),
                              ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                if (_manualController.text.trim().isNotEmpty) {
                                  _retornarCodigo(_manualController.text);
                                }
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                              child: const Text('Confirmar Ativo', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        )
                      ],
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
