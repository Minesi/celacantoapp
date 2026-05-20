// lib/home_page.dart
import 'package:flutter/material.dart';
import 'auth_service.dart'; // Importante para reconhecer o PerfilUsuario
import 'cadastro_page.dart';
import 'perfil_page.dart';

class HomePage extends StatelessWidget {
  final PerfilUsuario perfil;
  final String nomeUsuario;
  
  final dynamic emailUsuario;

  const HomePage({
    super.key,
    required this.perfil,
    required this.nomeUsuario,
    required this.emailUsuario,
    
  });

  // Regra de negócio: Apenas Supervisor e Admin podem acessar
  bool get _temAcessoAvancado {
    return perfil == PerfilUsuario.supervisor || perfil == PerfilUsuario.admin;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50]!,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- PARTE SUPERIOR: Logo (Esquerda) e Usuário (Direita) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Image.asset('assets/images/logo.png', height: 40),
                  // 1. Logo da Empresa (Placeholder de ícone, substitua por Image.asset se quiser)
                  // 2. Nome do Usuário logado e sua Role
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Olá, $nomeUsuario',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Acesso: ${perfil.name.toUpperCase()}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              
              // --- CORPO CENTRALIZADO: Menu de Botões ---
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Botão: Novo Projeto (Livre)
                        _buildMenuButton(
                          label: 'Novo Projeto',
                          icon: Icons.add_box_outlined,
                          isEnable: true,
                          onPressed: () {
                            _mostrarAlerta(context, 'Abrindo: Novo Projeto');
                          },
                        ),
                        const SizedBox(height: 12),

                        // Botão: Editar Projeto (Restrito)
                        _buildMenuButton(
                          label: 'Editar Projeto',
                          icon: Icons.edit_note_outlined,
                          isEnable: _temAcessoAvancado,
                          onPressed: () {
                            _mostrarAlerta(context, 'Abrindo: Editar Projeto');
                          },
                        ),
                        const SizedBox(height: 12),

                        // Botão: Perfil (Livre)
                        _buildMenuButton(
                          label: 'Perfil',
                          icon: Icons.account_circle_outlined,
                          isEnable: true,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PerfilPage(
                                  perfilLogado: perfil,
                                  emailLogado: emailUsuario,
                                )
                              )
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Botão: Cadastrar novo usuário (Restrito)
                        _buildMenuButton(
                          label: 'Cadastrar Novo Usuário',
                          icon: Icons.person_add_alt_1_outlined,
                          isEnable: _temAcessoAvancado,
                          onPressed: () {
                            Navigator.push(context,
                             MaterialPageRoute(
                              builder: (context) => CadastroPage(
                                perfilLogado: perfil,
                                emailLogado: emailUsuario,
                                nomeLogado: nomeUsuario,
                              )));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- PARTE INFERIOR: Versão do App ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'v0.1',
                    style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  // Botão de Sair opcional para conseguir voltar à tela de login nos seus testes
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.exit_to_app, size: 16, color: Colors.red),
                    label: const Text('Sair', style: TextStyle(color: Colors.red)),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Componente de botão reutilizável que aplica o efeito esmaecido
  Widget _buildMenuButton({
    required String label,
    required IconData icon,
    required bool isEnable,
    required VoidCallback onPressed,
  }) {
    return Opacity(
      // Se estiver desativado, aplica opacidade de 35% (efeito esmaecido)
      opacity: isEnable ? 1.0 : 0.35, 
      child: ElevatedButton.icon(
        // Se isEnable for falso, passamos 'null' no onPressed para o Flutter desativar o botão nativamente
        onPressed: isEnable ? onPressed : null,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          alignment: Alignment.centerLeft, // Alinha o texto à esquerda dentro do botão
          elevation: isEnable ? 2 : 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _mostrarAlerta(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), duration: const Duration(seconds: 1)),
    );
  }
}