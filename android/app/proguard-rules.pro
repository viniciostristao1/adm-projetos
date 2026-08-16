# ML Kit (google_mlkit_text_recognition): o R8 remove as classes dos
# reconhecedores por idioma (chinese/devanagari/japanese/korean) referenciadas
# pelo plugin — sem estes keep rules o build release falha.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-dontwarn com.google.mlkit.vision.text.**
