// lib/usuario_model.dart
import 'auth_service.dart'; // Importa o seu enum PerfilUsuario existente

class UsuarioModel {
  final String uid;             // ID único gerado pelo Firebase Auth
  final String nome;            // Mantendo a variável 'nome' do seu SQLite
  final String cpf;             // Mantendo a variável 'cpf' do seu SQLite
  final String email;           // Mantendo a variável 'email' do seu SQLite
  final PerfilUsuario perfil;   // Mantendo seu enum (operador, supervisor, admin)
  final String dominioEmpresa;  // O domínio isolador extraído do e-mail (@empresa.com)

  UsuarioModel({
    required this.uid,
    required this.nome,
    required this.cpf,
    required this.email,
    required this.perfil,
    required this.dominioEmpresa,
  });

  // Converte os dados para salvar no Cloud Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nome': nome,
      'cpf': cpf,
      'email': email,
      'perfil': perfil.name, // Salva como String ('admin', 'operador'...)
      'dominio_empresa': dominioEmpresa,
    };
  }

  // Reconstrói o Objeto a partir de um documento do Firestore
  factory UsuarioModel.fromFirestore(Map<String, dynamic> data, String id) {
    // Tratamento para converter a String de volta para o seu Enum PerfilUsuario
    PerfilUsuario perfilConvertido = PerfilUsuario.operador;
    if (data['perfil'] != null) {
      perfilConvertido = PerfilUsuario.values.firstWhere(
        (p) => p.name == data['perfil'],
        orElse: () => PerfilUsuario.operador,
      );
    }

    return UsuarioModel(
      uid: id,
      nome: data['nome'] ?? '',
      cpf: data['cpf'] ?? '',
      email: data['email'] ?? '',
      perfil: perfilConvertido,
      dominioEmpresa: data['dominio_empresa'] ?? '',
    );
  }
}