import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Escolhe uma imagem da galeria e devolve o texto extraído (OCR no próprio
/// aparelho, sem internet). Devolve null se o usuário cancelar, se a galeria
/// estiver indisponível ou se nada for reconhecido.
Future<String?> extrairTextoDeImagem() async {
  final XFile? foto;
  try {
    foto = await ImagePicker().pickImage(source: ImageSource.gallery);
  } catch (_) {
    return null; // sem permissão ou galeria indisponível
  }
  if (foto == null) return null;

  final TextRecognizer reconhecedor = TextRecognizer();
  try {
    final resultado =
        await reconhecedor.processImage(InputImage.fromFilePath(foto.path));
    final texto = resultado.text.trim();
    return texto.isEmpty ? null : texto;
  } catch (_) {
    return null;
  } finally {
    reconhecedor.close();
  }
}
