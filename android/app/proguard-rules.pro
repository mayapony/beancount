# ML Kit 的中文识别插件里顺手引用了其它脚本（日文/韩文/天城文）的类，
# 但我们只依赖了 text-recognition-chinese，release 构建时 R8 会报缺类。
# 这些分支在运行时不会被走到，直接放行即可（不要为了消警告而把整套脚本都打进包里）。
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.common.** { *; }
