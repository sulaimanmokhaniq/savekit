# youtubedl-android loads its classes and JSON mappers reflectively.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keepnames class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.databind.**
-dontwarn org.apache.commons.compress.**
-dontwarn java.beans.**
