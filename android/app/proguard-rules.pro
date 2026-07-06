# Ignorar as classes ausentes de outros idiomas do ML Kit Text Recognition
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# 1. Leitores de Câmera, QR Code e OCR (ML Kit)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.vision.** { *; }

# 2. Preservar a comunicação nativa do Flutter e Plugins
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.engine.plugins.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# 3. Preservar mapeamento de banco de dados e serialização de JSON
-keepclassmembers class * {
    *** get*();
    *** set*(*);
}
-keep class com.tekartik.sqflite.** { *; }

# 4. Ignorar avisos de classes de recursos geradas automaticamente
-dontwarn **.R$*