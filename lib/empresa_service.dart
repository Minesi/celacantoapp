// lib/empresa_service.dart
import 'empresa_model.dart';

class EmpresaService {
  // Singleton para garantir que usemos a mesma instância e os dados não sumam entre telas
  static final EmpresaService _instance = EmpresaService._internal();
  factory EmpresaService() => _instance;
  EmpresaService._internal();

  // Nossa tabela simulada do Banco de Dados Local
  final List<EmpresaModel> _bancoDadosEmpresas = [
    EmpresaModel(razaoSocial: 'Celacanto Indústria Textil LTDA', nomeFantasia: 'Celacanto Textil', cnpj: '12345678000100'),
    EmpresaModel(razaoSocial: 'Auto Peças SBC S/A', nomeFantasia: 'SBC Auto', cnpj: '98765432000199'),
    EmpresaModel(razaoSocial: 'Desenvolvimento de Sistemas Alfa', nomeFantasia: 'Alfa Dev', cnpj: '55555555000155'),
  ];

  // RETORNA TODAS AS EMPRESAS (Usado no seu Dropdown de cliente existente)
  Future<List<EmpresaModel>> buscarTodasEmpresas() async {
    // Simula um pequeno delay de leitura de banco (bom para testar carregamentos futuros)
    await Future.delayed(const Duration(milliseconds: 300));
    return _bancoDadosEmpresas;
  }

  // SALVA UMA NOVA EMPRESA (Usado no Avançar do Novo Cliente)
  Future<bool> salvarEmpresa(EmpresaModel novaEmpresa) async {
    await Future.delayed(const Duration(milliseconds: 500)); // Simula o tempo de rede/gravação
    
    // Regra de validação: Evitar CNPJ duplicado
    bool cnpjJaExiste = _bancoDadosEmpresas.any((e) => e.cnpj == novaEmpresa.cnpj);
    if (cnpjJaExiste) {
      return false; // Retorna falso se já existir, impedindo o cadastro
    }

    _bancoDadosEmpresas.add(novaEmpresa);
    return true; 
    
    /* FUTURAMENTE EM NUVEM (Exemplo Supabase):
    final response = await supabase.from('empresas').insert(novaEmpresa.toMap());
    return response.error == null;
    */
  }
}