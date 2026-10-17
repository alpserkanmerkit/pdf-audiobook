# ML Kit text recognition: the app bundles only the Latin recognizer.
# The plugin (google_mlkit_text_recognition) references optional language recognizers
# (Chinese, Japanese, Korean, Devanagari), but these are not packaged in the app.
# Silence the warnings so R8 does not stop on these missing classes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
