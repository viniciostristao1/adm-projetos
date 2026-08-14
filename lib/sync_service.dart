import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'storage.dart';

/// Sincroniza os projetos com o Firestore (documento `usuarios/{uid}`), com
/// os dados locais como fonte imediata. Estratégia simples para uso pessoal:
/// **quem salvou por último vence** (comparação pelo campo `atualizadoEm`).
///
/// - Ao entrar: se a nuvem for mais nova, baixa; senão, sobe o que está no
///   telefone (nunca apaga nada).
/// - A cada salvamento local, sobe para a nuvem (com debounce de 3s).
/// - Mudanças vindas de outro aparelho são aplicadas na hora (ignora o eco
///   dos próprios envios).
///
/// Se o Firebase ainda não estiver configurado, o app simplesmente continua
/// 100% local (a inicialização falha em silêncio no main).
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  User? usuario;
  StreamSubscription<DocumentSnapshot>? _subRemoto;
  Timer? _debounceEnvio;
  int _ultimoAplicadoMs = 0;
  bool _aplicandoRemoto = false;

  /// Estado visível da sincronização: 'desligado', 'Conectando…',
  /// 'Sincronizado', 'Enviando…' ou 'Erro' (com [ultimaMensagem]).
  String status = 'desligado';
  String? ultimaMensagem;
  DateTime? ultimoEnvio;

  bool get conectado => usuario != null;

  Future<void> iniciar() async {
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
    _subRemoto?.cancel();
    _subRemoto = null;
    _debounceEnvio?.cancel();
    _debounceEnvio = null;
    Storage.instance.removeListener(_aoSalvarLocal);
    status = 'desligado';
    ultimaMensagem = null;
    notifyListeners();
  }

  void _setStatus(String s, [String? msg]) {
    status = s;
    ultimaMensagem = msg;
    notifyListeners();
  }

  Future<void> _aoMudarAuth(User? u) async {
    if (u == null) {
      _desligar();
      return;
    }
    usuario = u;
    Storage.instance.addListener(_aoSalvarLocal);
    _setStatus('Conectando…');
    try {
      final doc = await _db.collection('usuarios').doc(u.uid).get();
      final remoto = doc.exists ? doc.data() : null;
      final remotoMs = remoto?['atualizadoEm'] as int? ?? 0;
      final dados = remoto?['dados'] as String?;
      final localMs = await Storage.instance.ultimaModificacaoMs();
      if (dados != null && remotoMs > localMs) {
        // Nuvem mais nova (ex.: outro celular): baixa e aplica.
        await _aplicarRemoto(dados, remotoMs);
      } else {
        // Telefone mais novo (ou nuvem vazia): sobe o que já existe.
        await enviarAgora();
      }
    } catch (e) {
      _setStatus('Erro', e.toString());
    }
    _ouvirRemoto(u.uid);
  }

  void _ouvirRemoto(String uid) {
    _subRemoto?.cancel();
    _subRemoto = _db.collection('usuarios').doc(uid).snapshots().listen((snap) {
      if (!snap.exists) return;
      final dados = snap.data();
      final ms = dados?['atualizadoEm'] as int? ?? 0;
      if (ms == 0 || ms <= _ultimoAplicadoMs) return; // eco do próprio envio
      final json = dados?['dados'] as String?;
      if (json == null) return;
      _aplicarRemoto(json, ms);
    });
  }

  Future<void> _aplicarRemoto(String json, int ms) async {
    _aplicandoRemoto = true;
    try {
      // Defesa extra: nunca aplicar dados da nuvem que não sejam MAIS NOVOS
      // que o conteúdo local (o arquivo guarda o horário junto com os dados).
      final localMs = await Storage.instance.ultimaModificacaoMs();
      if (ms <= localMs) return;
      final lista = (jsonDecode(json) as List)
          .map((e) => Projeto.fromJson(e as Map<String, dynamic>))
          .toList();
      await Storage.instance.substituir(lista);
      await Storage.instance.marcarModificacaoEm(ms);
      _ultimoAplicadoMs = ms;
      _setStatus('Sincronizado');
      debugPrint('sync: dados da nuvem aplicados ($ms)');
    } catch (e) {
      _setStatus('Erro', e.toString());
      debugPrint('sync: aplicar remoto falhou: $e');
    } finally {
      _aplicandoRemoto = false;
    }
  }

  void _aoSalvarLocal() {
    if (_aplicandoRemoto || usuario == null) return;
    _debounceEnvio?.cancel();
    _debounceEnvio = Timer(const Duration(seconds: 3), enviarAgora);
  }

  /// Sobe os dados locais para a nuvem (público para o botão "Tentar de novo").
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
      _ultimoAplicadoMs = ms;
      ultimoEnvio = DateTime.now();
      await Storage.instance.marcarModificacaoEm(ms);
      _setStatus('Sincronizado');
      debugPrint('sync: enviado para a nuvem ($ms)');
    } catch (e) {
      _setStatus('Erro', e.toString());
      debugPrint('sync: enviar falhou: $e');
    }
  }
}
