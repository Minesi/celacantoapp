// lib/calculos_pesagem.dart
// Cálculos do modelo de Pesagem (Anexos 2 e 6), sem dependência de tela ou banco.
import 'dart:math' as math;

class CalculosPesagem {
  const CalculosPesagem._();

  /// Área em m² a partir de "LARGURA x ALTURA" em milímetros; null se o texto não tiver as dimensões.
  static double? areaFiltroM2(String dimensoes) {
    final partes = RegExp(r'(\d+(?:[.,]\d+)?)\s*[xX×]\s*(\d+(?:[.,]\d+)?)').firstMatch(dimensoes);
    if (partes == null) return null;
    final largura = double.tryParse(partes.group(1)!.replaceAll(',', '.'));
    final altura = double.tryParse(partes.group(2)!.replaceAll(',', '.'));
    if (largura == null || altura == null || largura <= 0 || altura <= 0) return null;
    return (largura / 1000) * (altura / 1000);
  }

  /// Vazão em m³/h: velocidade média (m/s) × área (m²) × 3600.
  static double vazaoM3h({required double velocidadeMediaMs, required double areaM2}) =>
      velocidadeMediaMs * areaM2 * 3600;

  /// Ângulo em graus = arctg(X / L). Usa o módulo de X, porque o critério mede o desvio, não o sentido.
  static double? anguloParalelismoGraus({required double distanciaL, required double distanciaX}) {
    if (distanciaL <= 0) return null;
    return math.atan(distanciaX.abs() / distanciaL) * 180 / math.pi;
  }
}
