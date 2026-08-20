import 'dart:convert';
import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testes do backup automático (.bak): a cada gravação o arquivo ANTERIOR é
/// guardado em `adm_projetos.bak.json`; o `carregar()` restaura dele se o
/// principal sumir ou corromper (regressão do "apagou todo o conteúdo").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('adm_bak_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return dir.path;
      }
      return null;
    });
    Storage.instance.reiniciarParaTeste();
  });

  tearDown(() => Storage.instance.reiniciarParaTeste());

  Future<void> salvarCom(int n) async {
    final p = Projeto(
      id: 'p$n',
      nome: 'Projeto $n',
      tarefas: [Nota(id: 'n$n', texto: 'conteudo $n')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);
  }

  test('salvar guarda a versão anterior no .bak', () async {
    await salvarCom(1);
    expect(File('${dir.path}/adm_projetos.bak.json').existsSync(), isFalse);
    await salvarCom(2);
    final bak = File('${dir.path}/adm_projetos.bak.json');
    expect(bak.existsSync(), isTrue);
    final antigo = jsonDecode(bak.readAsStringSync()) as Map<String, dynamic>;
    expect((antigo['projetos'] as List).length, 1);
    expect((antigo['projetos'] as List).first['nome'], 'Projeto 1');
  });

  test('carregar restaura do .bak quando o principal está corrompido',
      () async {
    await salvarCom(1);
    await salvarCom(2);
    File('${dir.path}/adm_projetos.json')
        .writeAsStringSync('{corrompido!!!');
    Storage.instance.reiniciarParaTeste();
    final lista = await Storage.instance.carregar();
    expect(lista.length, 1);
    expect(lista.first.nome, 'Projeto 1');
  });

  test('carregar restaura do .bak quando o principal sumiu', () async {
    await salvarCom(1);
    await salvarCom(2);
    File('${dir.path}/adm_projetos.json').deleteSync();
    Storage.instance.reiniciarParaTeste();
    final lista = await Storage.instance.carregar();
    expect(lista.length, 1);
    expect(lista.first.nome, 'Projeto 1');
  });

  test('principal válido vazio não é substituído pelo .bak', () async {
    await salvarCom(1);
    await salvarCom(2);
    // Usuário apagou tudo de propósito: principal vazio é o estado válido.
    await Storage.instance.substituir([]);
    Storage.instance.reiniciarParaTeste();
    final lista = await Storage.instance.carregar();
    expect(lista, isEmpty);
  });

  test('JSON truncado no meio é REPARADO (recupera os projetos gravados)',
      () async {
    // Simula gravação interrompida: corta o arquivo dentro do 2º projeto.
    final p1 = Projeto(id: 'p1', nome: 'Casa',
        tarefas: [Nota(id: 'n1', texto: 'comprar tinta')]);
    final p2 = Projeto(id: 'p2', nome: 'Trabalho',
        tarefas: [Nota(id: 'n2', texto: 'relatório')]);
    final raw = jsonEncode({
      'atualizadoEm': 123,
      'projetos': [p1.toJson(), p2.toJson()],
    });
    File('${dir.path}/adm_projetos.json')
        .writeAsStringSync(raw.substring(0, raw.length - 30));
    Storage.instance.reiniciarParaTeste();
    final lista = await Storage.instance.carregar();
    expect(lista.length, greaterThanOrEqualTo(1));
    expect(lista.first.nome, 'Casa');
    expect(lista.first.tarefas.first.texto, 'comprar tinta');
    expect(Storage.instance.recuperadoDeCorrupcao, isTrue);
  });

  test('um projeto inválido não derruba os demais', () async {
    final p1 = Projeto(id: 'p1', nome: 'Casa',
        tarefas: [Nota(id: 'n1', texto: 'ok')]);
    final raw = jsonEncode({
      'atualizadoEm': 123,
      'projetos': [p1.toJson(), {'id': 123, 'nome': 'quebra'}],
    });
    File('${dir.path}/adm_projetos.json').writeAsStringSync(raw);
    Storage.instance.reiniciarParaTeste();
    final lista = await Storage.instance.carregar();
    expect(lista.length, 1);
    expect(lista.first.nome, 'Casa');
  });

  test('principal ilegível é preservado em .corrompido (1ª cópia)', () async {
    await salvarCom(1);
    await salvarCom(2);
    final lixo = '{{{corrompido em pedaços';
    File('${dir.path}/adm_projetos.json').writeAsStringSync(lixo);
    Storage.instance.reiniciarParaTeste();
    await Storage.instance.carregar();
    final corrompido = File('${dir.path}/adm_projetos.corrompido.json');
    expect(corrompido.existsSync(), isTrue);
    expect(corrompido.readAsStringSync(), lixo);
  });
}
