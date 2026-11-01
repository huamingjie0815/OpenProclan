# shared_preferences_android and package:jni look these types up by exact
# JNI name. Flutter release R8 otherwise renames them, and
# SharedPreferences.getInstance throws before runApp (blank splash).
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Result$Companion { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keep class kotlin.enums.** { *; }
