# Keep Flutter and plugin entry points
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }

# Google Mobile Ads recommended rules
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.**

# Keep classes used by reflection (Flutter Engine)
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.view.** { *; }

# Play Core (optional dynamic delivery; suppress warnings if not present)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Retain annotations
-keepattributes *Annotation*

# Keep generated classes
-keep class **.R$* { *; }
-keep class **.BuildConfig { *; }

# Optimize
-optimizations !code/simplification/arithmetic,!field/*,!class/merging/*
