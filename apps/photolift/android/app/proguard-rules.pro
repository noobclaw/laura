# libphotolift.so resolves these by name through JNI: the static native
# methods (class name must survive) and the per-tile progress callback that
# is looked up with GetMethodID("onProgress", "(II)V").
-keep class com.noobclaw.photolift.NcnnUpscaler { *; }
-keep interface com.noobclaw.photolift.NcnnUpscaler$Progress { *; }
-keepclassmembers class * implements com.noobclaw.photolift.NcnnUpscaler$Progress {
    public void onProgress(int, int);
}
