# ML Kit (reconocimiento de texto de los tickets).
#
# El plugin google_mlkit_text_recognition referencia los reconocedores de
# todos los alfabetos, pero aquí solo se incluye el latino: sin estas reglas
# R8 aborta la build de release por las clases que faltan.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit carga parte de su maquinaria por reflexión, así que si R8 la ofusca
# el escáner compila pero revienta en tiempo de ejecución, y solo en release.
-keep class com.google.mlkit.** { *; }
