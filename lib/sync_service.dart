import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'storage.dart';

/// Sincroniza os projetos com o Firestore (documento `usuarios/{uid}`).
///
/// ⚠️ SINCRONIZAÇÃO 100% MANUAL (por botão). O app funciona SEMPRE local; a
/// nuvem é apenas um backup opcional. NADA é enviado nem baixado
/// automaticamente.
///
/// Por quê: o modo automático anterior aplicava dados da nuvem (inclusive o
/// eco do próprio envio) chamando `Storage.substituir()` — que TROCA os objetos
/// em memória por novos. Quando isso acontecia enquanto o usuário digitava, a
/// caixinha aberta continuava escrevendo no objeto ANTIGO (já descartado): o
/// texto recém-digitado se perdia e caixinhas excluídas "voltavam". Deixando a
/// nuvem 100% manual (só nas Configurações, sem nenhuma caixinha aberta), essa
/// troca nunca pega o usuário no meio da digitação.
///
/// - **Entrar com Google:** só autentica e mostra o estado (não sincroniza).
/// - **Enviar para a nuvem:** sobe o que está no telefone.
/// - **Baixar da nuvem:** substitui os projetos locais pelos da nuvem (com
///   confirmação na tela).
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  User? usuario;

  /// Estado visível da sincronização: 'desligado', 'Conectando…', 'Conectado',
  /// 'Enviando…', 'Baixando…', 'Sincronizado' ou 'Erro' (com [ultimaMensagem]).
  String status = 'desligado';
  String? ultimaMensagem;

  /// Data/hora do ÚLTIMO envio à nuvem bem-sucedido — persistida (aparece na
  /// prateleira "RECENTES" da página inicial).
  DateTime? ultimoEnvio;
  static const _chaveUltimoEnvio = 'ultimo_envio_v1';

  /// true quando a nuvem tem uma versão MAIS NOVA que a deste celular — apenas
  /// uma DICA para o usuário tocar em "Baixar da nuvem". Nunca aplica sozinho.
  bool nuvemMaisNova = false;

  bool get conectado => usuario != null;

  Future<void> iniciar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_chaveUltimoEnvio);
      ultimoEnvio = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}
    _auth.authStateChanges().listen(_aoMudarAuth);
  }

  Future<void> entrarComGoogle() async {
    await _auth.signInWithProvider(GoogleAuthProvider());
  }

  Future<void> sair() async {
    _desligar();
    await _auth.signOut();
  }

  void _desligar() {
    usuario = null;
    nuvemMaisNova = false;
    status = 'desligado';
    ultimaMensagem = null;
    notifyListeners();
  }

  void _setStatus(String s, [String? msg]) {
    status = s;
    ultimaMensagem = msg;
    notifyListeners();
  }

  /// Ao autenticar: apenas conecta. NÃO sincroniza — só verifica (sem aplicar
  /// nada) se a nuvem está mais nova que o local, para exibir a dica de baixar.
  Future<void> _aoMudarAuth(User? u) async {
    if (u == null) {
      _desligar();
      return;
    }
    usuario = u;
    _setStatus('Conectando…');
    try {
      final doc = await _db.collection('usuarios').doc(u.uid).get();
      final remoto = doc.exists ? doc.data() : null;
      final remotoMs = remoto?['atualizadoEm'] as int? ?? 0;
      final temDados = (remoto?['dados'] as String?) != null;
      final localMs = await Storage.instance.ultimaModificacaoMs();
      nuvemMaisNova = temDados && remotoMs > localMs;
      _setStatus('Conectado');
    } catch (e) {
      _setStatus('Erro', e.toString());
    }
  }

  /// MANUAL — sobe os dados locais para a nuvem (botão "Enviar para a nuvem").
  /// Seguro: apenas LÊ os projetos e envia; não mexe na lista em memória.
  Future<void> enviarAgora() async {
    final u = usuario;
    if (u == null) return;
    _setStatus('Enviando…');
    try {
      final json = await Storage.instance.exportarJson();
      final ms = DateTime.now().millisecondsSinceEpoch;
      await _db.collection('usuarios').doc(u.uid).set({
        'dados': json,
        'atualizadoEm': ms,
        'email': u.email ?? '',
      });
      ultimoEnvio = DateTime.now();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _chaveUltimoEnvio, ultimoEnvio!.millisecondsSinceEpoch);
      } catch (_) {}
      // Alinha o relógio local ao envio para o próximo login não achar que a
      // nuvem está "mais nova" que o que já está aqui.
      await Storage.instance.marcarModificacaoEm(ms);
      nuvemMaisNova = false;
      _setStatus('Sincronizado');
      debugPrint('sync: enviado para a nuvem ($ms)');
    } catch (e) {
      _setStatus('Erro', e.toString());
      debugPrint('sync: enviar falhou: $e');
    }
  }

  /// MANUAL — baixa os dados da nuvem e SUBSTITUI os projetos locais (botão
  /// "Baixar da nuvem", com confirmação na tela). Chamado só a partir das
  /// Configurações, com nenhuma caixinha aberta — por isso é seguro trocar a
  /// lista em memória aqui.
  Future<void> baixarDaNuvem() async {
    final u = usuario;
    if (u == null) return;
    _setStatus('Baixando…');
    try {
      final doc = await _db.collection('usuarios').doc(u.uid).get();
      final dados = doc.exists ? (doc.data()?['dados'] as String?) : null;
      if (dados == null) {
        _setStatus('Erro', 'A nuvem ainda não tem nenhum backup.');
        return;
      }
      final lista = (jsonDecode(dados) as List)
          .map((e) => Projeto.fromJson(e as Map<String, dynamic>))
          .toList();
      await Storage.instance.substituir(lista);
      nuvemMaisNova = false;
      _setStatus('Sincronizado');
      debugPrint('sync: dados da nuvem aplicados');
    } catch (e) {
      _setStatus('Erro', e.toString());
      debugPrint('sync: baixar falhou: $e');
    }
  }
}
