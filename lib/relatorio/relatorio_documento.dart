// lib/relatorio/relatorio_documento.dart
// Monta o relatório final como uma lista de blocos (título, parágrafo, lista, tabela, imagem).
// Os mesmos blocos alimentam a revisão na tela e a geração do .docx na Cloud Function.
import '../ensaio_model.dart';
import '../norma_calculo_service.dart';
import '../paralelismo_model.dart';
import '../projeto_model.dart';
import '../sala_model.dart';
import 'textos_modelo_relatorio.dart';

sealed class BlocoRelatorio {
  const BlocoRelatorio();
  Map<String, dynamic> toJson();
}

class BlocoTitulo extends BlocoRelatorio {
  final String texto;
  final int nivel; // 1 = seção, 2 = subseção
  const BlocoTitulo(this.texto, {this.nivel = 1});
  @override
  Map<String, dynamic> toJson() => {'tipo': 'titulo', 'texto': texto, 'nivel': nivel};
}

class BlocoParagrafo extends BlocoRelatorio {
  final String texto;
  final String? rotulo; // Prefixo em negrito, ex.: "Proposta:"
  const BlocoParagrafo(this.texto, {this.rotulo});
  @override
  Map<String, dynamic> toJson() => {'tipo': 'paragrafo', 'texto': texto, 'rotulo': rotulo};
}

class BlocoLista extends BlocoRelatorio {
  final List<String> itens;
  final bool numerada;
  const BlocoLista(this.itens, {this.numerada = false});
  @override
  Map<String, dynamic> toJson() => {'tipo': 'lista', 'itens': itens, 'numerada': numerada};
}

class BlocoTabela extends BlocoRelatorio {
  final List<String> cabecalho;
  final List<List<String>> linhas;
  const BlocoTabela(this.cabecalho, this.linhas);
  @override
  Map<String, dynamic> toJson() => {'tipo': 'tabela', 'cabecalho': cabecalho, 'linhas': linhas};
}

class BlocoImagem extends BlocoRelatorio {
  final String url;
  final String legenda;
  const BlocoImagem(this.url, this.legenda);
  @override
  Map<String, dynamic> toJson() => {'tipo': 'imagem', 'url': url, 'legenda': legenda};
}

class DocumentoRelatorio {
  final String titulo;
  final String cabecalho;
  final List<BlocoRelatorio> blocos;
  const DocumentoRelatorio({required this.titulo, required this.cabecalho, required this.blocos});

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'cabecalho': cabecalho,
        'blocos': blocos.map((b) => b.toJson()).toList(),
      };
}

class AssinaturaRelatorio {
  final String papel;
  final String nome;
  final String funcao;
  final DateTime? data;
  const AssinaturaRelatorio({required this.papel, required this.nome, required this.funcao, this.data});
}

class ConclusaoQualificacao {
  final bool cumpre;
  final String comentarios;
  const ConclusaoQualificacao({required this.cumpre, this.comentarios = ''});
}

class DadosRelatorio {
  final ProjetoModel projeto;
  final String nomeEmpresa;
  final String sistemaNome;
  final DateTime dataEmissao;
  final Map<String, List<Map<String, dynamic>>> pontosPorChave; // 'salaId|TipoEnsaio.name'
  final Map<String, String> resumosPorEnsaio;
  final List<AssinaturaRelatorio> assinaturas;
  final ConclusaoQualificacao? conclusao; // null = ainda não emitido (revisão)
  final RegistroParalelismo? paralelismo;

  const DadosRelatorio({
    required this.projeto,
    required this.nomeEmpresa,
    required this.sistemaNome,
    required this.dataEmissao,
    this.pontosPorChave = const {},
    this.resumosPorEnsaio = const {},
    this.assinaturas = const [],
    this.conclusao,
    this.paralelismo,
  });
}

class RelatorioDocumentoBuilder {
  final DadosRelatorio dados;
  final NormaCalculoService norma;
  final List<BlocoRelatorio> _blocos = [];
  int _secao = 0;

  RelatorioDocumentoBuilder(this.dados, {NormaCalculoService? norma}) : norma = norma ?? NormaCalculoService();

  ProjetoModel get _projeto => dados.projeto;

  static String formatarData(DateTime? d) => d == null
      ? '-'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _ou(String v) => v.trim().isEmpty ? '-' : v.trim();

  late final Map<String, String> _variaveis = {
    'EMPRESA': _ou(dados.nomeEmpresa),
    'CNPJ': _ou(_projeto.cnpjEmpresa),
    'SISTEMA': _ou(dados.sistemaNome),
    'AREA': _ou(_projeto.area),
    'TIPO_PROJETO': _ou(_projeto.tipoProjeto),
    'DESCRICAO_SISTEMA': TextosModeloRelatorio.descricaoDoSistema(_projeto.tipoProjeto),
    'DATA': formatarData(dados.dataEmissao),
  };

  String _t(String texto) => preencherVariaveis(texto, _variaveis);

  /// Ensaios selecionados pelo elaborador, na ordem do catálogo (define a numeração TESTE 1..N).
  late final List<EnsaioModel> ensaiosSelecionados = EnsaioModel.catalogoPadrao()
      .where((e) => _projeto.ensaiosSelecionados.contains(e.tipo.name))
      .toList();

  void _secaoTitulo(String titulo) => _blocos.add(BlocoTitulo('${++_secao}. $titulo'));

  DocumentoRelatorio construir() {
    _blocos.clear();
    _secao = 0;
    _identificacao();
    _objetivo();
    _referencia();
    _definicoes();
    _escopo();
    _responsabilidades();
    _anexos();
    _testes();
    _tabelaResumo();
    _documentacaoApoio();
    if (dados.paralelismo != null) _paralelismo();
    _resultadosSelecionados();
    _assinaturas();
    _conclusao();
    return DocumentoRelatorio(
      titulo: _t(TextosModeloRelatorio.titulo),
      cabecalho: _t(TextosModeloRelatorio.titulo),
      blocos: List.unmodifiable(_blocos),
    );
  }

  void _identificacao() {
    _blocos
      ..add(BlocoTabela(const ['Informações gerais', ''], [
        ['Empresa', _variaveis['EMPRESA']!],
        ['CNPJ', _variaveis['CNPJ']!],
        ['Tipo de projeto', _variaveis['TIPO_PROJETO']!],
        ['Nome / TAG do sistema', _variaveis['SISTEMA']!],
        ['Área', _variaveis['AREA']!],
        ['Nº do relatório', _projeto.id],
        ['Data de emissão', _variaveis['DATA']!],
      ]))
      ..add(BlocoParagrafo(_t(TextosModeloRelatorio.notaConfidencialidade)));
  }

  void _objetivo() {
    _secaoTitulo(SecaoModelo.objetivo.titulo);
    _blocos.add(BlocoParagrafo(_t(TextosModeloRelatorio.objetivo)));
  }

  void _referencia() {
    _secaoTitulo(SecaoModelo.referencia.titulo);
    _blocos.add(BlocoLista(TextosModeloRelatorio.referencias.map(_t).toList(), numerada: true));
  }

  void _definicoes() {
    _secaoTitulo(SecaoModelo.definicoes.titulo);
    _blocos.add(BlocoTabela(
      const ['Termo', 'Descrição'],
      TextosModeloRelatorio.definicoes.map((d) => [d.$1, d.$2]).toList(),
    ));
  }

  void _escopo() {
    _secaoTitulo(SecaoModelo.escopo.titulo);
    _blocos
      ..add(BlocoParagrafo(_t(TextosModeloRelatorio.escopoAplicacao)))
      ..add(BlocoTitulo('Estratégia de qualificação', nivel: 2))
      ..add(BlocoLista(TextosModeloRelatorio.escopoEstrategia.map(_t).toList()))
      ..add(BlocoTitulo('Método da qualificação de Desempenho', nivel: 2))
      ..add(BlocoLista(TextosModeloRelatorio.escopoMetodo.map(_t).toList()));
  }

  void _responsabilidades() {
    _secaoTitulo(SecaoModelo.responsabilidades.titulo);
    for (final (papel, descricao) in TextosModeloRelatorio.responsabilidades) {
      _blocos.add(BlocoParagrafo(descricao, rotulo: '$papel:'));
    }
  }

  void _anexos() {
    _secaoTitulo(SecaoModelo.anexos.titulo);
    _blocos
      ..add(BlocoParagrafo(TextosModeloRelatorio.anexosObjetivo, rotulo: 'Objetivo:'))
      ..add(BlocoParagrafo(TextosModeloRelatorio.anexosMetodologia, rotulo: 'Metodologia:'))
      ..add(BlocoParagrafo(TextosModeloRelatorio.anexosCriterio, rotulo: 'Critério de aceitação:'))
      ..add(const BlocoTitulo('Instrumentos utilizados e certificados de calibração', nivel: 2));

    final instrumentos = [
      for (final entrada in _projeto.ferramentasEscaneadas.entries)
        for (final i in entrada.value)
          [entrada.key, _ou(i.tag), _ou(i.numeroSerie), _ou(i.numeroCertificado), _ou(i.validade)],
    ];
    if (instrumentos.isEmpty) {
      _blocos.add(const BlocoParagrafo('Nenhum instrumento registrado em campo.'));
    } else {
      _blocos.add(BlocoTabela(
        const ['Instrumento', 'TAG', 'Nº de série', 'Nº do certificado', 'Validade da calibração'],
        instrumentos,
      ));
    }

    _blocos.add(const BlocoTitulo('Evidências fotográficas', nivel: 2));
    final evidencias = _evidenciasFotograficas();
    if (evidencias.isEmpty) {
      _blocos.add(const BlocoParagrafo('Nenhuma evidência fotográfica anexada.'));
    } else {
      _blocos.addAll(evidencias);
    }
  }

  List<BlocoImagem> _evidenciasFotograficas() {
    final vistas = <String>{};
    final imagens = <BlocoImagem>[];
    for (final ensaio in ensaiosSelecionados) {
      for (final sala in _projeto.salas) {
        for (final ponto in dados.pontosPorChave['${sala.id}|${ensaio.tipo.name}'] ?? const []) {
          final url = ponto['fotoEvidenciaUrl']?.toString() ?? '';
          if (url.isEmpty || !vistas.add(url)) continue;
          imagens.add(BlocoImagem(url, '${_nomeEnsaio(ensaio.tipo)} – ${sala.nome}'));
        }
      }
    }
    return imagens;
  }

  String _nomeEnsaio(TipoEnsaio tipo) => TextosModeloRelatorio.ensaios[tipo]?.nome ?? tipo.name;

  void _testes() {
    _secaoTitulo(SecaoModelo.testes.titulo);
    if (ensaiosSelecionados.isEmpty) {
      _blocos.add(const BlocoParagrafo('Nenhum teste selecionado.'));
      return;
    }
    _blocos.add(const BlocoParagrafo(TextosModeloRelatorio.testesIntroducao));
    for (var i = 0; i < ensaiosSelecionados.length; i++) {
      final tipo = ensaiosSelecionados[i].tipo;
      final texto = TextosModeloRelatorio.ensaios[tipo];
      _blocos.add(BlocoTitulo('$_secao.${i + 1}. ${_nomeEnsaio(tipo)}', nivel: 2));
      if (texto != null) {
        _blocos
          ..add(BlocoParagrafo(texto.proposta, rotulo: 'Proposta:'))
          ..add(BlocoParagrafo(texto.criterioAceitacao, rotulo: 'Critério de aceitação:'));
        if (texto.preRequisitos.isNotEmpty) {
          _blocos
            ..add(const BlocoParagrafo('', rotulo: 'Pré-requisitos:'))
            ..add(BlocoLista(texto.preRequisitos));
        }
        if (texto.descricao.isNotEmpty) {
          _blocos
            ..add(const BlocoParagrafo('', rotulo: 'Descrição do teste:'))
            ..add(BlocoLista(texto.descricao, numerada: true));
        }
      }
      final resumo = dados.resumosPorEnsaio[tipo.name]?.trim() ?? '';
      if (resumo.isNotEmpty) _blocos.add(BlocoParagrafo(resumo, rotulo: 'Observações:'));
    }
  }

  List<SalaModel> _salasDoEnsaio(EnsaioModel ensaio) =>
      _projeto.salas.where((s) => ensaio.aplicavelGraus.contains(s.grau)).toList();

  /// (pontos preenchidos, pontos exigidos) do ensaio somando todas as salas aplicáveis.
  (int, int) progressoDoEnsaio(EnsaioModel ensaio) {
    var feitos = 0;
    var exigidos = 0;
    for (final sala in _salasDoEnsaio(ensaio)) {
      exigidos += norma.pontosExigidosParaExecucao(sala, ensaio.tipo);
      feitos += (dados.pontosPorChave['${sala.id}|${ensaio.tipo.name}'] ?? const [])
          .where((p) => (p['valor05um']?.toString() ?? '').trim().isNotEmpty)
          .length;
    }
    return (feitos, exigidos);
  }

  static String situacao((int, int) progresso) {
    final (feitos, exigidos) = progresso;
    if (exigidos == 0) return 'N.A';
    if (feitos == 0) return 'Pendente';
    return feitos >= exigidos ? 'Realizado' : 'Parcial';
  }

  void _tabelaResumo() {
    _secaoTitulo(SecaoModelo.tabelaTestesResumo.titulo);
    if (ensaiosSelecionados.isEmpty) {
      _blocos.add(const BlocoParagrafo('Nenhum teste selecionado.'));
      return;
    }
    _blocos
      ..add(const BlocoParagrafo(TextosModeloRelatorio.tabelaResumoIntroducao))
      ..add(BlocoTabela(
        const ['Teste', 'Nome do teste', 'Critério de aceitação', 'Pontos', 'Situação'],
        [
          for (var i = 0; i < ensaiosSelecionados.length; i++)
            () {
              final ensaio = ensaiosSelecionados[i];
              final progresso = progressoDoEnsaio(ensaio);
              return [
                '${i + 1}',
                _nomeEnsaio(ensaio.tipo),
                TextosModeloRelatorio.ensaios[ensaio.tipo]?.criterioAceitacao ?? '-',
                '${progresso.$1}/${progresso.$2}',
                situacao(progresso),
              ];
            }(),
        ],
      ));
  }

  void _documentacaoApoio() {
    _secaoTitulo(SecaoModelo.documentacaoApoio.titulo);
    _blocos
      ..add(const BlocoTitulo('Motivo da qualificação', nivel: 2))
      ..add(const BlocoLista(TextosModeloRelatorio.documentacaoMotivo))
      ..add(const BlocoTitulo('Registros', nivel: 2))
      ..add(const BlocoParagrafo(TextosModeloRelatorio.documentacaoRegistros));
  }

  void _paralelismo() {
    _secaoTitulo(SecaoModelo.paralelismoFluxoAr.titulo);
    final registro = dados.paralelismo;
    _blocos
      ..add(const BlocoParagrafo(TextosModeloRelatorio.paralelismoProposta, rotulo: 'Proposta:'))
      ..add(const BlocoParagrafo(TextosModeloRelatorio.paralelismoCriterio, rotulo: 'Critério de aceitação:'))
      ..add(BlocoParagrafo(
        registro == null || registro.resultado.trim().isEmpty ? 'Não registrado.' : registro.resultado.trim(),
        rotulo: 'Resultado:',
      ));
    if (registro != null && registro.fotoUrl.isNotEmpty) {
      _blocos.add(BlocoImagem(registro.fotoUrl, 'Paralelismo do fluxo de ar'));
    }
  }

  void _resultadosSelecionados() {
    _secaoTitulo('Máquinas, Salas e Resultados dos Testes');
    _blocos.add(const BlocoTitulo('Máquinas e salas atendidas', nivel: 2));
    if (_projeto.handlingUnits.isEmpty) {
      _blocos.add(const BlocoParagrafo('Nenhuma máquina cadastrada.'));
    }
    for (final maquina in _projeto.handlingUnits) {
      _blocos
        ..add(BlocoParagrafo(
          maquina.filtros.isEmpty ? 'Sem filtros internos.' : maquina.filtros.map((f) => f.descricao).join('; '),
          rotulo: '${maquina.nome} –',
        ))
        ..add(_tabelaSalas(_projeto.salas.where((s) => s.atendidaPor(maquina.id)).toList()));
    }
    final idsMaquinas = _projeto.handlingUnits.map((h) => h.id).toSet();
    final orfas = _projeto.salas.where((s) => !s.handlingUnitIds.any(idsMaquinas.contains)).toList();
    if (orfas.isNotEmpty) {
      _blocos
        ..add(const BlocoParagrafo('', rotulo: 'Salas sem máquina vinculada:'))
        ..add(_tabelaSalas(orfas));
    }

    for (var i = 0; i < ensaiosSelecionados.length; i++) {
      final ensaio = ensaiosSelecionados[i];
      _blocos.add(BlocoTitulo('TESTE ${i + 1} – ${_nomeEnsaio(ensaio.tipo).toUpperCase()}', nivel: 2));
      final instrumentos = [
        for (final tipoFerramenta in ensaio.ferramentasNecessarias)
          for (final inst in _projeto.ferramentasEscaneadas[tipoFerramenta] ?? const [])
            [tipoFerramenta, _ou(inst.tag), _ou(inst.numeroCertificado), _ou(inst.validade)],
      ];
      if (instrumentos.isNotEmpty) {
        _blocos.add(BlocoTabela(const ['Instrumento', 'TAG', 'Certificado', 'Validade'], instrumentos));
      }
      _blocos.add(_tabelaResultados(ensaio));
      _blocos.add(BlocoParagrafo(situacao(progressoDoEnsaio(ensaio)), rotulo: 'Situação do teste:'));
    }
  }

  BlocoTabela _tabelaSalas(List<SalaModel> salas) => BlocoTabela(
        const ['Sala', 'Grau', 'Área (m²)', 'Volume (m³)', 'Filtros'],
        salas
            .map((s) => [
                  s.nome,
                  s.grau.name.toUpperCase(),
                  '${s.area}',
                  '${s.volume}',
                  s.filtros.isEmpty ? '-' : s.filtros.map((f) => f.descricao).join('; '),
                ])
            .toList(),
      );

  BlocoTabela _tabelaResultados(EnsaioModel ensaio) {
    final ehContagem = ensaio.tipo == TipoEnsaio.contagemParticulas;
    final criterio = TextosModeloRelatorio.ensaios[ensaio.tipo]?.criterioAceitacao ?? '-';
    final linhas = <List<String>>[];
    for (final sala in _salasDoEnsaio(ensaio)) {
      final rotulos = norma.rotulosDosPontos(sala, ensaio.tipo);
      final pontos = dados.pontosPorChave['${sala.id}|${ensaio.tipo.name}'] ?? const [];
      final estados = ehContagem ? const ['repouso', 'operacao'] : const [''];
      for (final estado in estados) {
        for (var i = 0; i < rotulos.length; i++) {
          final ponto = pontos.where((p) {
            final mesmoNumero = p['numeroPonto'] == i + 1;
            return mesmoNumero && (!ehContagem || p['estado']?.toString() == estado);
          }).firstOrNull;
          final valor = (ponto?['valor05um']?.toString() ?? '').trim();
          final valor5 = (ponto?['valor5um']?.toString() ?? '').trim();
          linhas.add([
            sala.nome,
            if (ehContagem) estado == 'repouso' ? 'Repouso' : 'Operação',
            rotulos[i],
            valor.isEmpty ? '—' : valor,
            if (ehContagem) valor5.isEmpty ? '—' : valor5,
            criterio,
          ]);
        }
      }
    }
    return BlocoTabela(
      ehContagem
          ? const ['Sala', 'Estado', 'Ponto', '0,5 µm', '5,0 µm', 'Critério de aceitação']
          : const ['Sala', 'Ponto', 'Valor encontrado', 'Critério de aceitação'],
      linhas,
    );
  }

  void _assinaturas() {
    _secaoTitulo(SecaoModelo.registroAssinaturas.titulo);
    _blocos
      ..add(const BlocoParagrafo(TextosModeloRelatorio.assinaturasIntroducao))
      ..add(BlocoTabela(
        const ['Papel', 'Nome', 'Função', 'Empresa', 'Data', 'Assinatura'],
        dados.assinaturas
            .map((a) => [
                  a.papel,
                  _ou(a.nome),
                  _ou(a.funcao),
                  TextosModeloRelatorio.empresaExecutora,
                  formatarData(a.data),
                  '',
                ])
            .toList(),
      ));
  }

  void _conclusao() {
    _secaoTitulo(SecaoModelo.conclusaoQualificacao.titulo);
    final conclusao = dados.conclusao;
    String marcar(bool? sim) => sim == null ? '( ) Sim  ( ) Não' : (sim ? '(X) Sim  ( ) Não' : '( ) Sim  (X) Não');
    _blocos
      ..add(const BlocoParagrafo(TextosModeloRelatorio.conclusaoObjetivo, rotulo: 'Objetivo:'))
      ..add(const BlocoParagrafo(TextosModeloRelatorio.conclusaoMetodologia, rotulo: 'Metodologia:'))
      ..add(const BlocoParagrafo(TextosModeloRelatorio.conclusaoCriterio, rotulo: 'Critério de aceitação:'))
      ..add(BlocoTabela(const ['Discussão dos resultados', 'Resposta'], [
        [_t(TextosModeloRelatorio.conclusaoPerguntaExecucao), marcar(conclusao?.cumpre)],
        [_t(TextosModeloRelatorio.conclusaoPerguntaQualificado), marcar(conclusao?.cumpre)],
      ]))
      ..add(BlocoParagrafo(
        conclusao == null || conclusao.comentarios.trim().isEmpty ? '-' : conclusao.comentarios.trim(),
        rotulo: 'Comentários:',
      ))
      ..add(BlocoParagrafo(
        conclusao == null ? 'A definir na emissão.' : (conclusao.cumpre ? 'CUMPRE' : 'NÃO CUMPRE'),
        rotulo: 'Conclusão geral da qualificação de Desempenho:',
      ));
  }
}
