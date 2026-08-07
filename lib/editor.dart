import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copia um texto para a área de transferência e mostra um aviso.
void copiarTexto(BuildContext context, String texto) {
  Clipboard.setData(ClipboardData(text: texto));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Copiado!')));
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

/// Formata a digitação para que, ao pressionar Enter depois de um item
/// numerado, a linha nova receba automaticamente o próximo número ("2-",
/// "3-", etc.). Só mexe no texto quando há nova linha vazia após item
/// numerado — não interfere na digitação por voz.
class LinhasNumeradas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final texto = newValue.text;
    if (!texto.contains('\n')) return newValue;

    final linhas = texto.split('\n');
    var mudou = false;
    final saida = <String>[];
    int proximo = 1;
    var anteriorNumerada = false;

    for (final linha in linhas) {
      final m = RegExp(r'^\s*(\d+)\s*-').firstMatch(linha);
      if (m != null) {
        proximo = int.parse(m.group(1)!) + 1;
        anteriorNumerada = true;
        saida.add(linha);
      } else if (linha.isEmpty && anteriorNumerada) {
        saida.add('$proximo-');
        proximo++;
        mudou = true;
      } else {
        anteriorNumerada = false;
        saida.add(linha);
      }
    }
    if (!mudou) return newValue;

    final novoTexto = saida.join('\n');

    // Linha onde está o cursor (no texto original).
    final antes =
        texto.substring(0, newValue.selection.isValid ? newValue.selection.start : texto.length);
    var linhaCursor = antes.split('\n').length - 1;
    if (linhaCursor > saida.length - 1) linhaCursor = saida.length - 1;

    // Cursor no fim da linha do cursor (logo após o "N-" recém criado).
    var off = 0;
    for (var i = 0; i < linhaCursor; i++) {
      off += saida[i].length + 1;
    }
    off += saida[linhaCursor].length;

    return newValue.copyWith(
      text: novoTexto,
      selection: TextSelection.collapsed(offset: off),
    );
  }
}