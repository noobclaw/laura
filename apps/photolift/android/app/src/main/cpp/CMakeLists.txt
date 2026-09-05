# PhotoLift native layer: ncnn (Vulkan) + the shared upscaling core + JNI glue.
#
# The prebuilt ncnn package is downloaded by the `fetchNcnn` Gradle task in
# android/app/build.gradle.kts and handed in as -DNCNN_ROOT=<dir>; it holds
# one `<abi>/lib/cmake/ncnn` per ABI, so `find_package` resolves per ABI.
cmake_minimum_required(VERSION 3.22)
project(photolift LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED NCNN_ROOT)
    message(FATAL_ERROR "NCNN_ROOT not set — the fetchNcnn Gradle task must run before the CMake build")
endif()

set(ncnn_DIR "${NCNN_ROOT}/${ANDROID_ABI}/lib/cmake/ncnn")
find_package(ncnn REQUIRED)

set(PHOTOLIFT_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../native")

add_library(photolift SHARED
    photolift_jni.cpp
    "${PHOTOLIFT_CORE_DIR}/photolift_core.cpp")

target_include_directories(photolift PRIVATE "${PHOTOLIFT_CORE_DIR}")

# ncnn's imported target already carries glslang, OpenMP and the Android
# system libraries it needs; jnigraphics is for the Bitmap access in the glue.
target_link_libraries(photolift PRIVATE ncnn android jnigraphics log)
