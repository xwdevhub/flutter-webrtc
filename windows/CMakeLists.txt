cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "flutter_webrtc")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "flutter_webrtc_plugin")

add_definitions(-DLIB_WEBRTC_API_DLL)
add_definitions(-DRTC_DESKTOP_DEVICE)
# WinRT support for Windows Graphics Capture
add_definitions(-DWIN32_LEAN_AND_MEAN)
add_definitions(-DNOMINMAX)
# C++ filesystem library support
add_definitions(-D_SILENCE_CXX17_ITERATOR_DEPRECATION_WARNING)

add_library(${PLUGIN_NAME} SHARED
  "../common/cpp/src/flutter_common.cc"
  "../common/cpp/src/flutter_data_channel.cc"
  "../common/cpp/src/flutter_frame_cryptor.cc"
  "../common/cpp/src/flutter_media_stream.cc"
  "../common/cpp/src/flutter_peerconnection.cc"
  "../common/cpp/src/flutter_frame_capturer.cc"
  "../common/cpp/src/flutter_video_renderer.cc"
  "../common/cpp/src/flutter_screen_capture.cc"
  "../common/cpp/src/flutter_webrtc.cc"
  "../common/cpp/src/flutter_webrtc_base.cc"
  "../third_party/uuidxx/uuidxx.cc"
  "flutter_webrtc_plugin.cc"
  "../common/cpp/src/recording/flutter_audio_recorder.cc"
  "../common/cpp/src/recording/flutter_video_recorder.cc"
  "../common/cpp/src/recording/flutter_media_recorder.cc"
  "../common/cpp/src/recording/aac_encoder.cc"
  "../common/cpp/src/recording/h264_encoder.cc"
  "../common/cpp/src/recording/mp4_muxer.cc"
  "../common/cpp/src/recording/task_thread.cc"
)

target_compile_options(${PLUGIN_NAME} PRIVATE /utf-8)

include_directories(
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include/recording"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/uuidxx"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/svpng"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/include"
)

# Create INTERFACE library for FFMPEG to isolate compiler warnings
add_library(ffmpeg_interface INTERFACE)
target_include_directories(ffmpeg_interface INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/include"
)
set_target_properties(ffmpeg_interface PROPERTIES
  INTERFACE_COMPILE_OPTIONS "$<$<CXX_COMPILER_ID:MSVC>:/wd4244>"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  ffmpeg_interface
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/win64/libwebrtc.dll.lib"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avcodec.lib"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avfilter.lib"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avformat.lib"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avutil.lib"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/swresample.lib"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/swscale.lib"
  # Windows Graphics Capture and Direct3D libraries
  d3d11.lib
  dxgi.lib
  # GDI libraries
  gdi32.lib
  user32.lib
  # WinRT runtime
  runtimeobject.lib
  windowsapp.lib
)

# List of absolute paths to libraries that should be bundled with the plugin
set(flutter_webrtc_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/win64/libwebrtc.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avcodec-61.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avformat-61.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avfilter-10.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/avutil-59.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/swresample-5.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ffmpeg/lib/win64/swscale-8.dll"
  PARENT_SCOPE
)
