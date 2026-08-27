// lib/validadores.dart
// Funções de validação de formato compartilhadas entre os formulários do app.

/// Valida um CPF conferindo os dois dígitos verificadores (algoritmo oficial).
bool validarCpf(String cpf) {
  final digitos = cpf.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(digitos)) return false; // todos os dígitos iguais

  final numeros = digitos.split('').map(int.parse).toList();

  int calcularDigito(List<int> base, int fatorInicial) {
    var soma = 0;
    for (var i = 0; i < base.length; i++) {
      soma += base[i] * (fatorInicial - i);
    }
    final resto = (soma * 10) % 11;
    return resto == 10 ? 0 : resto;
  }

  final digito1 = calcularDigito(numeros.sublist(0, 9), 10);
  if (digito1 != numeros[9]) return false;

  final digito2 = calcularDigito(numeros.sublist(0, 10), 11);
  if (digito2 != numeros[10]) return false;

  return true;
}

/// Valida um CNPJ conferindo os dois dígitos verificadores (algoritmo oficial).
bool validarCnpj(String cnpj) {
  final digitos = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.length != 14) return false;
  if (RegExp(r'^(\d)\1{13}$').hasMatch(digitos)) return false; // todos os dígitos iguais

  final numeros = digitos.split('').map(int.parse).toList();

  int calcularDigito(List<int> base) {
    final pesos = base.length == 12
        ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    var soma = 0;
    for (var i = 0; i < base.length; i++) {
      soma += base[i] * pesos[i];
    }
    final resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  }

  final digito1 = calcularDigito(numeros.sublist(0, 12));
  if (digito1 != numeros[12]) return false;

  final digito2 = calcularDigito(numeros.sublist(0, 13));
  if (digito2 != numeros[13]) return false;

  return true;
}

/// Valida o formato geral de um endereço de e-mail.
bool validarEmail(String email) {
  return RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}(\.[a-zA-Z]{2,})?$').hasMatch(email.trim());
}
