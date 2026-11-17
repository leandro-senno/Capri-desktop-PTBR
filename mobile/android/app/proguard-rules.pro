# Ouvido offline da palavra de ativação (Vosk) e a ponte nativa dele (JNA): o R8 não pode renomear nem apagar.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
-keep class org.vosk.** { *; }
-dontwarn java.awt.**
-dontwarn com.sun.jna.**
