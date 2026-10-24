import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Voz da Muse SINTETIZADA NO PRÓPRIO CELULAR (offline), via sherpa-onnx + o
/// modelo Piper "dii" (a mesma voz feminina da VPS). Elimina o gargalo do 1 vCPU
/// da VPS e a rede → voz bem mais rápida, offline, e sem carga no servidor.
///
/// ⚠️ A síntese (`tts.generate`) é uma chamada NATIVA SÍNCRONA que leva
/// ~0,5–1s por parágrafo. ANTES rodava no isolate PRINCIPAL e travava a UI:
/// não dava p/ rolar a conversa e, se o usuário tocasse "voltar" no meio, o
/// Android acusava "Taskix não está respondendo" (ANR = UI thread presa >5s).
/// Agora o motor vive num ISOLATE DEDICADO (`_isolateMain`): o `generate` roda
/// fora da UI; o principal só manda o texto e recebe o WAV pronto via portas.
///
/// O modelo (~67 MB) é baixado 1x na 1ª vez e guardado no aparelho. Se qualquer
/// passo falhar (sem modelo ainda, erro nativo, isolate não subiu, etc.), os
/// métodos devolvem null/false e o chamador cai no /tts da VPS (reserva) — nunca
/// quebra nem bloqueia a UI.
class TtsOnDevice {
  static const _url =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_BR-dii-high.tar.bz2';
  static const _pasta = 'tts_dii'; // sob o diretório de documentos do app
  static const _sub = 'vits-piper-pt_BR-dii-high'; // pasta que o .tar.bz2 cria
  // Velocidade da fala (lengthScale: MAIOR = mais lenta). O dono é o
  // VozController (`voz_velocidade_v1`, padrão 1.04); aqui fica só o valor em
  // uso — o isolate RECRIA o motor se um pedido chegar com outra velocidade
  // (sem derrubar nada, sem vazar isolate).
  static double _velocidade = 1.04;

  /// Ajusta a velocidade dos próximos pedidos (o isolate se adapta sozinho).
  static void definirVelocidade(double v) {
    if (v.isFinite) _velocidade = v;
  }

  static SendPort? _req; // porta p/ pedir síntese ao isolate (null = não pronto)
  static bool _falhou = false; // isolate não subiu → usa o servidor (não insiste)
  static Future<bool>? _preparando; // garante 1 download/subida de isolate só
  static int _seq = 0; // id incremental de cada pedido
  static final Map<int, Completer<Uint8List?>> _pend = {}; // pedidos aguardando

  /// Pronto p/ sintetizar no aparelho (isolate de voz no ar)?
  static bool get pronto => _req != null;

  /// Ainda falta BAIXAR o modelo (p/ avisar do download só quando for o caso)?
  static Future<bool> precisaBaixar() async => !await _temModelo();

  static Future<Directory> _baseDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/$_pasta/$_sub');
  }

  static Future<bool> _temModelo() async {
    final d = await _baseDir();
    return File('${d.path}/pt_BR-dii-high.onnx').existsSync() &&
        File('${d.path}/tokens.txt').existsSync() &&
        Directory('${d.path}/espeak-ng-data').existsSync();
  }

  /// Garante o modelo baixado + o isolate de voz no ar. Idempotente (só 1
  /// download / 1 subida mesmo se chamado várias vezes). true = pronto p/ falar.
  static Future<bool> preparar() {
    if (_req != null) return Future.value(true);
    if (_falhou) return Future.value(false);
    return _preparando ??=
        _prepararInterno().whenComplete(() => _preparando = null);
  }

  static Future<bool> _prepararInterno() async {
    try {
      final d = await _baseDir();
      if (!await _temModelo()) {
        if (!await _baixar(d)) return false; // ainda sem modelo (download falhou)
      }
      // Sobe o isolate de síntese (uma vez). A 1ª mensagem dele é a porta de
      // requisição; `null` significa que não conseguiu carregar o motor.
      final pronto = Completer<SendPort?>();
      final recv = ReceivePort();
      recv.listen((msg) {
        if (msg is SendPort) {
          if (!pronto.isCompleted) pronto.complete(msg);
        } else if (msg is List && msg.length == 2) {
          final id = msg[0] as int;
          final bytes = msg[1] as Uint8List?;
          _pend.remove(id)?.complete(bytes);
        } else {
          if (!pronto.isCompleted) pronto.complete(null); // falha ao iniciar
        }
      });
      await Isolate.spawn(
        _isolateMain,
        [
          recv.sendPort,
          '${d.path}/pt_BR-dii-high.onnx',
          '${d.path}/tokens.txt',
          '${d.path}/espeak-ng-data',
          _velocidade,
        ],
        onError: recv.sendPort, // erro não-tratado no spawn → destrava o Completer
        errorsAreFatal: false,
      );
      final sp = await pronto.future
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      if (sp == null) {
        recv.close();
        _falhou = true;
        return false;
      }
      _req = sp;
      return true;
    } catch (_) {
      _falhou = true;
      return false;
    }
  }

  /// Sintetiza o texto NO ISOLATE de voz → WAV (Uint8List). null se não estiver
  /// pronto ou falhar (o chamador cai no servidor). NÃO bloqueia a UI: o pesado
  /// roda no isolate; aqui só se aguarda a resposta pela porta.
  static Future<Uint8List?> sintetizar(String texto, {double? velocidade}) {
    final req = _req;
    final t = texto.trim();
    if (req == null || t.isEmpty) return Future.value(null);
    final id = _seq++;
    final c = Completer<Uint8List?>();
    _pend[id] = c;
    req.send([id, t, velocidade ?? _velocidade]);
    // Salvaguarda: nunca pendura o chamador pra sempre se a resposta sumir.
    return c.future.timeout(const Duration(seconds: 20), onTimeout: () {
      _pend.remove(id);
      return null;
    });
  }

  // ─────────────────────── roda NO ISOLATE de síntese ───────────────────────
  // Carrega o motor uma vez e responde cada pedido [id, texto, velocidade] com
  // [id, wav|null]. Se a velocidade mudar entre pedidos, o motor é RECRIADO
  // (sem derrubar o isolate nem a fila).
  static void _isolateMain(List args) {
    final SendPort out = args[0] as SendPort;
    final String modelo = args[1] as String;
    final String tokens = args[2] as String;
    final String dataDir = args[3] as String;
    double vel = (args[4] as num).toDouble();
    sherpa.OfflineTts? abrir(double v) {
      try {
        return sherpa.OfflineTts(sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: modelo,
              tokens: tokens,
              dataDir: dataDir,
              lengthScale: v,
            ),
            numThreads: 2,
            debug: false,
          ),
        ));
      } catch (_) {
        return null;
      }
    }

    sherpa.OfflineTts? tts;
    try {
      sherpa.initBindings();
      tts = abrir(vel);
    } catch (_) {
      tts = null;
    }
    if (tts == null) {
      out.send(null); // não carregou → o principal cai no servidor
      return;
    }
    final inbox = ReceivePort();
    out.send(inbox.sendPort); // devolve a porta de requisição ao principal
    inbox.listen((msg) {
      if (msg is! List || (msg.length != 2 && msg.length != 3)) return;
      final id = msg[0] as int;
      final texto = msg[1] as String;
      if (msg.length == 3) {
        final v = (msg[2] as num?)?.toDouble();
        if (v != null && v.isFinite && v != vel) {
          final novo = abrir(v);
          if (novo != null) {
            tts = novo;
            vel = v;
          }
        }
      }
      final motor = tts;
      Uint8List? bytes;
      try {
        final audio = motor!.generate(text: texto, sid: 0, speed: 1.0);
        if (audio.samples.isNotEmpty) {
          bytes = _wav(audio.samples, audio.sampleRate);
        }
      } catch (_) {}
      out.send([id, bytes]);
    });
  }

  /// Baixa + descompacta o modelo. O HTTP, o BZip2/Tar (~67 MB) e a extração são
  /// PESADOS: rodam num isolate efêmero (`Isolate.run`) p/ não travar a UI na 1ª
  /// vez. Devolve true se o modelo ficou no lugar.
  static Future<bool> _baixar(Directory modelDir) async {
    try {
      final destino = modelDir.parent.path; // <docs>/tts_dii
      final ok = await Isolate.run(() => _baixarIsolado(_url, destino));
      return ok && await _temModelo();
    } catch (_) {
      return false;
    }
  }

  /// Corpo do download/descompactação — roda inteiro fora do isolate principal.
  static Future<bool> _baixarIsolado(String url, String destino) async {
    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(minutes: 6));
      if (resp.statusCode != 200 || resp.bodyBytes.length < 1000000) {
        return false;
      }
      final tar = BZip2Decoder().decodeBytes(resp.bodyBytes);
      final arquivo = TarDecoder().decodeBytes(tar);
      final dir = Directory(destino);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      extractArchiveToDisk(arquivo, destino);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Float32 PCM [-1,1] → WAV PCM 16-bit mono.
  static Uint8List _wav(Float32List samples, int sampleRate) {
    final n = samples.length;
    final dataLen = n * 2;
    final out = BytesBuilder();
    void s(String v) => out.add(v.codeUnits);
    void u32(int v) =>
        out.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
    void u16(int v) => out.add([v & 255, (v >> 8) & 255]);
    s('RIFF');
    u32(36 + dataLen);
    s('WAVE');
    s('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits
    s('data');
    u32(dataLen);
    final pcm = Uint8List(dataLen);
    for (var i = 0; i < n; i++) {
      var v = (samples[i] * 32767).round();
      if (v > 32767) v = 32767;
      if (v < -32768) v = -32768;
      pcm[i * 2] = v & 255;
      pcm[i * 2 + 1] = (v >> 8) & 255;
    }
    out.add(pcm);
    return out.toBytes();
  }
}
