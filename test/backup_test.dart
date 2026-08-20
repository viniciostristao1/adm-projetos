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
}
