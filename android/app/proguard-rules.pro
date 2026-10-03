# ProGuard 规则：发布版开启 R8 压缩时，保留必要的 Flutter / 插件类，
# 避免反射或原生桥接被误删导致运行时崩溃。
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class de.urmogorov.audioplayers.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class net.sqlcipher.database.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.mr.flutter.filepicker.** { *; }
-keep class androidx.media.** { *; }

# 保留原生方法（JNI）
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留枚举
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
