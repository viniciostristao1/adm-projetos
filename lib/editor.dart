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

/// Pilha de desfazer da caixinha: guarda o texto ANTES de cada RAJADA de
/// apagamento — um toque no desfazer restaura tudo o que foi apagado de uma
/// vez (digitação normal não empilha, para o botão não desfazer tecla por
/// tecla). Ações da barra (centralizar, numerar, item de to-do) empilham via
/// [empilhar], virando "desfazer a ação anterior".
class HistoricoTexto {
  HistoricoTexto({this.limite = 40});

  final int limite;
  final List<String> _pilha = [];
  bool _apagando = false;
  bool _suprimido = false;
  String _atual = '';

  /// Estado inicial (chamar ao abrir a caixinha).
  void comecar(String texto) {
    _atual = texto;
    _apagando = false;
    _suprimido = false;
    _pilha.clear();
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
    _apagando = false;
  }

  /// Chamado a cada mudança de texto. Quando uma rajada de apagamento
  /// COMEÇA, salva o texto anterior na pilha.
  void registrar(String novo) {
    final ehDelecao = novo.length < _atual.length;
    if (ehDelecao && !_apagando && !_suprimido) {
      _pilha.add(_atual);
      if (_pilha.length > limite) _pilha.removeAt(0);
    }
    _apagando = ehDelecao;
    _atual = novo;
  }

  /// Restaura o último estado (ou null se não houver nada).
  String? desfazer() {
    if (_pilha.isEmpty) return null;
    _apagando = false;
    _atual = _pilha.removeLast();
    return _atual;
  }

  bool get podeDesfazer => _pilha.isNotEmpty;
}