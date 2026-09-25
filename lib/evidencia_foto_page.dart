// lib/evidencia_foto_page.dart
// Captura da foto de evidência (ex.: fita do contador de partículas) exigida antes de
// finalizar determinados ensaios em campo.
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class EvidenciaFotoPage extends StatefulWidget {
  const EvidenciaFotoPage({super.key});

  @override
  State<EvidenciaFotoPage> createState() => _EvidenciaFotoPageState();
}

class _EvidenciaFotoPageState extends State<EvidenciaFotoPage> {
  CameraController? _cameraController;
  bool _erroNaCamera = false;
  bool _capturando = false;

  @override
  void initState() {
    super.initState();
    _inicializarCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _inicializarCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _erroNaCamera = true);
        return;
      }
      _cameraController = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Erro ao abrir a câmera para evidência: $e');
      setState(() => _erroNaCamera = true);
    }
  }

  Future<void> _capturarFoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _capturando) return;
    setState(() => _capturando = true);
    try {
      final arquivo = await _cameraController!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(arquivo.path);
    } catch (e) {
      debugPrint('Falha ao capturar foto de evidência: $e');
      setState(() => _capturando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Foto da Evidência'), backgroundColor: Colors.black),
      body: _erroNaCamera
          ? const Center(
              child: Text('Câmera indisponível neste dispositivo.', style: TextStyle(color: Colors.white)),
            )
          : (_cameraController == null || !_cameraController!.value.isInitialized)
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    CameraPreview(_cameraController!),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: FloatingActionButton(
                        onPressed: _capturarFoto,
                        backgroundColor: Colors.white,
                        child: _capturando
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.camera_alt, color: Colors.black),
                      ),
                    ),
                  ],
                ),
    );
  }
}
