// lib/novo_projeto_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'empresa_model.dart';
import 'empresa_service.dart'; // Importa o novo serviço

class NovoProjetoPage extends StatefulWidget {
  const NovoProjetoPage({super.key});

  @override
  State<NovoProjetoPage> createState() => _NovoProjetoPageState();
}

class _NovoProjetoPageState extends State<NovoProjetoPage> {
  final EmpresaService _empresaService = EmpresaService(); // Instancia o serviço
  List<bool> _selecaoAbas = [true, false];
  bool _carregandoEmpresas = true;

  // --- Controllers para Novo Cliente ---
  final _formKeyNovoCliente = GlobalKey<FormState>();
  final _controllerRazaoSocial = TextEditingController();
  final _controllerNomeFantasia = TextEditingController();
  final _controllerCnpjNovo = TextEditingController();

  // --- Controllers e Estados para Cliente Existente ---
  String? _empresaSelecionadaDropdown;
  final _controllerCnpjExistente = TextEditingController();
  List<EmpresaModel> _empresasCarregadas = []; // Lista dinâmica vinda do serviço

  @override
  void initState() {
    super.initState();
    _carregarDadosDoBanco();
  }

  // Puxa as empresas cadastradas no banco local ao iniciar a tela
  Future<void> _carregarDadosDoBanco() async {
    try {
      final empresas = await _empresaService.buscarTodasEmpresas();
      setState(() {
        _empresasCarregadas = empresas;
        _carregandoEmpresas = false;
      });
    } catch (e) {
      setState(() => _carregandoEmpresas = false);
    }
  }

  @override
  void dispose() {
    _controllerRazaoSocial.dispose();
    _controllerNomeFantasia.dispose();
    _controllerCnpjNovo.dispose();
    _controllerCnpjExistente.dispose();
    super.dispose();
  }

  // --- FUNÇÃO PARA SALVAR O NOVO CLIENTE ---
  Future<void> _processarNovoCadastro() async {
    if (!_formKeyNovoCliente.currentState!.validate()) return;

    final razao = _controllerRazaoSocial.text.trim();
    final fantasia = _controllerNomeFantasia.text.trim();
    final cnpj = _controllerCnpjNovo.text.trim();

    if (razao.isEmpty || cnpj.isEmpty) {
      _mostrarMensagem('Razão Social e CNPJ são obrigatórios!', Colors.orange);
      return;
    }

    // Criando o modelo baseado nos campos digitados
    final novaEmpresa = EmpresaModel(
      razaoSocial: razao,
      nomeFantasia: fantasia.isEmpty ? razao : fantasia, // Se fantasia for nulo, assume a razão social
      cnpj: cnpj,
    );

    // Mostra indicador de progresso circular
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Salva usando o serviço
    bool sucesso = await _empresaService.salvarEmpresa(novaEmpresa);

    if (!mounted) return;
    Navigator.pop(context); // Remove o loading do CircularProgressIndicator

    if (sucesso) {
      _mostrarMensagem('Empresa cadastrada com sucesso no banco local!', Colors.green);
      
      // Recarrega a lista interna para que o dropdown do "Cliente Existente" se atualize automaticamente
      _carregarDadosDoBanco();
      
      // TODO: Continuar fluxo do projeto após salvar
    } else {
      _mostrarMensagem('Erro: Este CNPJ já está cadastrado no sistema.', Colors.red);
    }
  }

  void _mostrarMensagem(String msg, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: cor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Novo Projeto'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ToggleButtons(
                  borderRadius: BorderRadius.circular(12),
                  selectedColor: Colors.white,
                  fillColor: Colors.blue[700],
                  color: Colors.grey[700],
                  constraints: const BoxConstraints(minHeight: 45.0, minWidth: 150.0),
                  isSelected: _selecaoAbas,
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < _selecaoAbas.length; i++) {
                        _selecaoAbas[i] = (i == index);
                      }
                    });
                  },
                  children: const [
                    Text('Novo Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Cliente Existente', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Expanded(
                child: _carregandoEmpresas
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: _selecaoAbas[0] 
                            ? _buildFormNovoCliente() 
                            : _buildFormClienteExistente(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- FORMULÁRIO 1: CADASTRAR NOVO CLIENTE ---
  Widget _buildFormNovoCliente() {
    return Form(
      key: _formKeyNovoCliente,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ficha de Cadastro',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _controllerRazaoSocial,
            decoration: const InputDecoration(
              labelText: 'Nome da empresa (Razão Social)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _controllerNomeFantasia,
            decoration: const InputDecoration(
              labelText: 'Nome Fantasia',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.storefront),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _controllerCnpjNovo,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'CNPJ (Somente números)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _processarNovoCadastro, // Chama a nova função com persistência
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Avançar', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // --- FORMULÁRIO 2: CLIENTE EXISTENTE ---
  Widget _buildFormClienteExistente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Localizar Cliente',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
        ),
        const SizedBox(height: 16),
        
        // Dropdown atualizado puxando dinamicamente do modelo de dados
        DropdownButtonFormField<String>(
          value: _empresaSelecionadaDropdown,
          decoration: const InputDecoration(
            labelText: 'Pesquisa por nome da empresa',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          items: _empresasCarregadas.map((empresa) {
            return DropdownMenuItem<String>(
              value: empresa.razaoSocial,
              child: Text(empresa.razaoSocial),
            );
          }).toList(),
          onChanged: (String? novoValor) {
            setState(() {
              _empresaSelecionadaDropdown = novoValor;
              if (novoValor != null) {
                _controllerCnpjExistente.clear();
              }
            });
          },
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey[400])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('ou', style: TextStyle(color: Colors.grey[500])),
            ),
            Expanded(child: Divider(color: Colors.grey[400])),
          ],
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _controllerCnpjExistente,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Pesquisa por CNPJ (Somente números)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.numbers),
          ),
          onChanged: (texto) {
            if (texto.isNotEmpty && _empresaSelecionadaDropdown != null) {
              setState(() {
                _empresaSelecionadaDropdown = null;
              });
            }
          },
        ),
        const SizedBox(height: 32),
        
        ElevatedButton(
          onPressed: () {
            if (_empresaSelecionadaDropdown == null && _controllerCnpjExistente.text.isEmpty) {
              _mostrarMensagem('Por favor, selecione uma empresa ou digite um CNPJ.', Colors.orange);
              return;
            }

            String busca = _empresaSelecionadaDropdown ?? _controllerCnpjExistente.text;
            _mostrarMensagem('Buscando dados de: $busca...', Colors.blue);
            
            // TODO: Continuar o fluxo capturando a entidade EmpresaModel encontrada
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.blue[800],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Próximo', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}