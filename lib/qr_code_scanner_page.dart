// lib/qr_code_scanner_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as flutter_show_hide; // dummy import to keep analyzer happy
// The `mobile_scanner` package is optional. If it's not available in
// this project, provide a lightweight fallback so this file still
// compiles and the page can be used (for example, in debug or tests).
// If you have `mobile_scanner` as a dependency, remove the fallback
// below and restore the import above.

// BEGIN FALLBACK (only used when package:mobile_scanner is not present)
class MobileScannerController {
  void dispose() {}
}

class Barcode {
  final String? rawValue;
  Barcode(this.rawValue);
}

class BarcodeCapture {
  final List<Barcode> barcodes;
  BarcodeCapture(this.barcodes);
}

typedef MobileScannerDetectCallback = void Function(BarcodeCapture capture);

class MobileScanner extends StatelessWidget {
  final MobileScannerController? controller;
  final MobileScannerDetectCallback? onDetect;

  const MobileScanner({super.key, this.controller, this.onDetect});

  @override
  Widget build(BuildContext context) {
    // Simple UI that simulates a QR detection when tapped.
    return GestureDetector(
      onTap: () {
        if (onDetect != null) {
          onDetect!(BarcodeCapture([Barcode('SAMPLE_QR_CODE')]));
        }
      },
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Tap to simulate QR scan',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
// END FALLBACK

class QrCodeScannerPage extends StatefulWidget {
  const QrCodeScannerPage({super.key});

  @override
  State<QrCodeScannerPage> createState() => _QrCodeScannerPageState();
}

class _QrCodeScannerPageState extends State<QrCodeScannerPage> {
  // Controlador para gerenciar o ciclo de vida da câmera
  final MobileScannerController _controller = MobileScannerController();
  bool _jaEscaneou = false; // Evita ler o mesmo código múltiplas vezes seguidas

  @override
  void dispose() {
    _controller.dispose(); // Libera a câmera quando a tela fechar
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context), // Volta sem dados se cancelar
        ),
      ),
      body: Stack(
        children: [
          // Exibe o preview da câmera em tempo real
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_jaEscaneou) return;

              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  setState(() {
                    _jaEscaneou = true;
                  });
                  
                  // Fecha a tela da câmera devolvendo o texto do QR Code
                  Navigator.pop(context, barcode.rawValue);
                  break;
                }
              }
            },
          ),
          
          // Uma máscara visual por cima da câmera para guiar o usuário
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}