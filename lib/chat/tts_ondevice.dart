import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Voz da Muse SINTETIZADA NO PRÓPRIO CELULAR (offline), via sherpa-onnx + o
/// modelo Piper "dii" (a mesma voz feminina da VPS). Elimina o gargalo do 1 vCPU
/// da VPS e a rede → voz bem mais rápida, offline, e sem carga no servidor.
///
/// O modelo (~67 MB) é baixado 1x na 1ª vez e guardado no aparelho. Se qualquer
/// passo falhar (sem modelo ainda, erro nativo, etc.), os métodos devolvem
/// null/false e o chamador cai no /tts da VPS (reserva) — nunca quebra.
class TtsOnDevice {
  static const _url =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_BR-dii-high.tar.bz2';
  static const _pasta = 'tts_dii'; // sob o diretório de documentos do app
  static const _sub = 'vits-piper-pt_BR-dii-high'; // pasta que o .tar.bz2 cria
  static const double _lengthScale = 1.02; // ~mesma velocidade da VPS

  static sherpa.OfflineTts? _tts;
  static bool _bindings = false;
  static Future<bool>? _preparando; // garante 1 download/carregamento só

  /// Pronto p/ sintetizar no aparelho (modelo carregado)?
  static bool get pronto => _tts != null;

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

  /// Garante o modelo baixado + o motor carregado. Idempotente (só 1 download
  /// mesmo se chamado várias vezes). Devolve true se ficou pronto p/ falar.
  static Future<bool> preparar() {
    if (_tts != null) return Future.value(true);
    return _preparando ??=
        _prepararInterno().whenComplete(() => _preparando = null);
  }

  static Future<bool> _prepararInterno() async {
    try {
      final d = await _baseDir();
      if (!await _temModelo()) {
        if (!await _baixar(d)) return false;
      }
      if (!_bindings) {
        sherpa.initBindings();
        _bindings = true;
      }
      _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: '${d.path}/pt_BR-dii-high.onnx',
            tokens: '${d.path}/tokens.txt',
            dataDir: '${d.path}/espeak-ng-data',
            lengthScale: _lengthScale,
          ),
          numThreads: 2,
          debug: false,
        ),
      ));
      return true;
    } catch (_) {
      _tts = null;
      return false;
    }
  }

  static Future<bool> _baixar(Directory modelDir) async {
    try {
      final resp =
          await http.get(Uri.parse(_url)).timeout(const Duration(minutes: 6));
      if (resp.statusCode != 200 || resp.bodyBytes.length < 1000000) {
        return false;
      }
      final tar = BZip2Decoder().decodeBytes(resp.bodyBytes);
      final arquivo = TarDecoder().decodeBytes(tar);
      // extrai para <docs>/tts_dii/ (cria a subpasta vits-piper-pt_BR-dii-high/).
      final destino = modelDir.parent; // <docs>/tts_dii
      if (destino.existsSync()) destino.deleteSync(recursive: true);
      destino.createSync(recursive: true);
      extractArchiveToDisk(arquivo, destino.path);
      return await _temModelo();
    } catch (_) {
      return false;
    }
  }

  /// Sintetiza o texto NO APARELHO → WAV (Uint8List). null se não estiver pronto
  /// ou falhar (o chamador cai no servidor). Síntese roda no isolate principal
  /// (~0,5–1s por parágrafo num celular moderno); ok porque corre adiantada à fala.
  static Future<Uint8List?> sintetizar(String texto) async {
    final tts = _tts;
    final t = texto.trim();
    if (tts == null || t.isEmpty) return null;
    try {
      final audio = tts.generate(text: t, sid: 0, speed: 1.0);
      if (audio.samples.isEmpty) return null;
      return _wav(audio.samples, audio.sampleRate);
    } catch (_) {
      return null;
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
