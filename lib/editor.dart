import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mostra um aviso que some sozinho após [duracao]. Além da duração própria
/// do SnackBar, um Timer força o fechamento — garante que desapareça mesmo
/// com animações do sistema desativadas.
void mostrarAviso(BuildContext context, String texto,
    {Duration duracao = const Duration(seconds: 4)}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto), duration: duracao));
  Timer(duracao, messenger.hideCurrentSnackBar);
}

/// Aviso com botão de ação (ex.: "Desfazer"). Mesma garantia de fechamento
/// automático do [mostrarAviso].
void mostrarAvisoAcao(
  BuildContext context,
  String texto,
  String rotuloAcao,
  VoidCallback onAcao, {
  Duration duracao = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto),
      duration: duracao,
      action: SnackBarAction(
        label: rotuloAcao,
        onPressed: () {
          messenger.hideCurrentSnackBar();
          onAcao();
        },
      ),
    ));
  Timer(duracao, messenger.hideCurrentSnackBar);
}

/// Copia um texto para a área de transferência e mostra um aviso.
void copiarTexto(BuildContext context, String texto) {
  Clipboard.setData(ClipboardData(text: texto));
  mostrarAviso(context, 'Copiado!');
}

/// Controlador de texto que DESTACA (fundo amarelo) as ocorrências de um
/// termo de busca. O destaque é montado dentro do próprio `buildTextSpan` do
/// TextField — ou seja, faz parte do MESMO layout do texto — então nunca sai
/// do lugar (diferente do antigo `CustomPaint` por cima, que precisava
/// recalcular a geometria à mão e às vezes marcava a palavra/linha errada).
///
/// ⚠️ NÃO desenhar os glifos ☐/☑ com estilo próprio aqui (fontSize maior etc.):
/// a V0.1.52 tentou e quebrou a digitação nas linhas de to-do (Enter duplicava,
/// palavra gigante na 2ª linha) — o TextField deixa de renderizar o texto
/// corretamente com o IME. Revertido na V0.1.53; ver AGENTS.md §6.
class BuscaController extends TextEditingController {
  BuscaController({super.text});

  /// Termo ativo da busca (vazio = sem destaque). Definir e chamar setState
  /// no widget que o usa para repintar.
  String termo = '';

  static const _corDestaque = Color(0x59FFC107);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = termo.trim().toLowerCase();
    final texto = value.text;
    // Sem termo ativo: comportamento PADRÃO (inclui o sublinhado da palavra em
    // composição do teclado). Só assumimos o desenho quando há o que destacar.
    if (t.isEmpty || !texto.toLowerCase().contains(t)) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final base = style ?? const TextStyle();
    final destaque = base.copyWith(backgroundColor: _corDestaque);
    final lower = texto.toLowerCase();
    final spans = <TextSpan>[];
    var from = 0;
    while (true) {
      final idx = lower.indexOf(t, from);
      if (idx < 0) {
        spans.add(TextSpan(text: texto.substring(from)));
        break;
      }
      if (idx > from) {
        spans.add(TextSpan(text: texto.substring(from, idx)));
      }
      spans.add(TextSpan(
        text: texto.substring(idx, idx + t.length),
        style: destaque,
      ));
      from = idx + t.length;
    }
    return TextSpan(style: base, children: spans);
  }
}

/// Deixa a PRIMEIRA letra (não-espaço) em maiúscula.
String capitalizarInicial(String texto) {
  final m = RegExp(r'\S').firstMatch(texto);
  if (m == null) return texto;
  final i = m.start;
  final letra = texto[i];
  if (letra == letra.toUpperCase()) return texto;
  return texto.replaceRange(i, i + 1, letra.toUpperCase());
}

/// Próximo número da sequência da lista (maior número existente + 1).
/// Ex.: "1- a\n2- b" -> 3; texto vazio -> 1.
int proximoNumeroLista(String texto) {
  var maior = 0;
  for (final a in RegExp(r'(?:^|\n)\s*(\d+)\s*-').allMatches(texto)) {
    final v = int.parse(a.group(1)!);
    if (v > maior) maior = v;
  }
  return maior + 1;
}

/// Formata a digitação para que, ao pressionar Enter DEPOIS de um item
/// numerado, a nova linha ganhe o próximo número ("2-", "3-", ...).
///
/// Só age quando a edição termina com uma linha nova (Enter no final) e a
/// linha anterior é numerada — assim NÃO atrapalha o backspace de apagar os
/// números nem interfere na digitação por voz.
class LinhasNumeradas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final texto = newValue.text;
    // Só age no Enter no final: a edição precisa TERMINAR com linha nova E
    // ter AUMENTADO o texto (digitar Enter acrescenta; apagar com backspace
    // não pode re-criar os números).
    if (!texto.endsWith('\n')) return newValue;
    if (texto.length <= oldValue.text.length) return newValue;

    final linhas = texto.split('\n');
    if (linhas.length < 2) return newValue;

    final m = RegExp(r'^\s*(\d+)\s*-').firstMatch(linhas[linhas.length - 2]);
    if (m != null) {
      final proximo = int.parse(m.group(1)!) + 1;
      final novoTexto = '$texto$proximo- ';
      return newValue.copyWith(
        text: novoTexto,
        selection: TextSelection.collapsed(offset: novoTexto.length),
      );
    }

    // Linha anterior é item de to-do ("☐ " ou já marcado "☑") -> a nova
    // linha continua com "☐ " (desmarcado). O \uFE0E força a apresentação em
    // TEXTO do quadradinho (senão alguns celulares desenham o ☐/☑ como
    // emoji colorido).
    final anterior = linhas[linhas.length - 2].trimLeft();
    if (anterior.startsWith('☐') || anterior.startsWith('☑')) {
      final novoTexto = '$texto☐\uFE0E ';
      return newValue.copyWith(
        text: novoTexto,
        selection: TextSelection.collapsed(offset: novoTexto.length),
      );
    }

    return newValue;
  }
}

/// Garante letra MAIÚSCULA logo após cada item numerado ("1- A", "2- B"...).
/// Só age quando o primeiro caractere digitado depois de "N- " está minúsculo.
String maiusculaAposItem(String texto) {
  final linhas = texto.split('\n');
  final ultima = linhas.last;
  final m = RegExp(r'^(\d+\s*-\s*)([a-zà-ú])').firstMatch(ultima);
  if (m == null) return texto;
  final letra = m.group(2)!.toUpperCase();
  final pos = texto.length - (ultima.length - m.group(1)!.length);
  return texto.replaceRange(pos, pos + 1, letra);
}

/// Pilha de desfazer da caixinha. Guarda o texto ANTES de cada "movimento"
/// de edição — um toque no desfazer volta o movimento inteiro (não tecla por
/// tecla). Um novo movimento começa quando: é a 1ª mudança desde que a
/// caixinha abriu, houve uma PAUSA na edição, ou o sentido mudou
/// (digitar <-> apagar). Assim tanto DIGITAR quanto APAGAR criam pontos de
/// desfazer, em vários níveis. Ações da barra (centralizar, numerar, item de
/// to-do) empilham via [empilhar], virando "desfazer a ação anterior".
class HistoricoTexto {
  HistoricoTexto({this.limite = 200, this.pausaMs = 600});

  final int limite;

  /// Intervalo (ms) sem editar que fecha o movimento atual — a próxima
  /// mudança vira um novo ponto de desfazer.
  final int pausaMs;

  final List<String> _pilha = [];
  bool _suprimido = false;
  String _atual = '';
  int _tipo = 0; // 0 = nenhum ainda, 1 = inserção, -1 = deleção
  int _ultimoMs = 0;

  /// Estado inicial (chamar ao abrir a caixinha).
  void comecar(String texto) {
    _atual = texto;
    _suprimido = false;
    _tipo = 0;
    _pilha.clear();
    _ultimoMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Empilha o estado atual na pilha (para ações de toolbar, antes de
  /// alterar o texto). Ignora se for idêntico ao topo (evita duplicatas).
  void empilhar(String texto) {
    if (_pilha.isNotEmpty && _pilha.last == texto) return;
    _pilha.add(texto);
    if (_pilha.length > limite) _pilha.removeAt(0);
  }

  /// Durante uma AÇÃO da barra (centralizar, numerar, to-do): suprime o
  /// registro automático das mudanças intermediárias (o estado já foi
  /// empilhado por [empilhar]) para o desfazer voltar ao estado anterior.
  void suprimir() => _suprimido = true;

  void reativar() {
    _suprimido = false;
    _tipo = 0;
  }

  /// Alinha o estado atual SEM criar um ponto de desfazer. Usado pela
  /// correção automática de maiúscula (feita direto no controlador, sem
  /// passar por [registrar]) para não virar um passo de undo espúrio.
  void sincronizar(String texto) => _atual = texto;

  /// Chamado a cada mudança de texto vinda da digitação.
  void registrar(String novo) {
    if (_suprimido) {
      _atual = novo;
      return;
    }
    if (novo == _atual) return;
    final tipo = novo.length >= _atual.length ? 1 : -1;
    final agora = DateTime.now().millisecondsSinceEpoch;
    final pausou = agora - _ultimoMs > pausaMs;
    final trocouSentido = _tipo != 0 && tipo != _tipo;
    if (_tipo == 0 || pausou || trocouSentido) {
      empilhar(_atual);
    }
    _tipo = tipo;
    _atual = novo;
    _ultimoMs = agora;
  }

  /// Restaura o último estado (ou null se não houver nada). A próxima
  /// digitação recomeça um movimento novo.
  String? desfazer() {
    if (_pilha.isEmpty) return null;
    _atual = _pilha.removeLast();
    _tipo = 0;
    return _atual;
  }

  bool get podeDesfazer => _pilha.isNotEmpty;
}