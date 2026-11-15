cmake_minimum_required(VERSION 3.24)

project(YouTubeCreator LANGUAGES CXX)

set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

if(MSVC)
  add_compile_options(/utf-8)
endif()

find_package(Qt6 REQUIRED COMPONENTS
  Quick QuickControls2 QuickTest Sql Multimedia Network)

if(NOT FFMPEG_ROOT)
  set(FFMPEG_ROOT "$ENV{FFMPEG_ROOT}")
endif()
if(NOT FFMPEG_ROOT OR
   NOT EXISTS "${FFMPEG_ROOT}/include/libavcodec/avcodec.h")
  set(_ffmpeg_roots)
  if(DEFINED ENV{LOCALAPPDATA})
    file(GLOB _ffmpeg_roots
      "$ENV{LOCALAPPDATA}/Microsoft/WinGet/Packages/Gyan.FFmpeg.Shared*/ffmpeg-*-full_build-shared")
  endif()
  file(GLOB _ffmpeg_c_roots "C:/ffmpeg-*-full_build-shared")
  list(APPEND _ffmpeg_roots ${_ffmpeg_c_roots})
  foreach(_ffmpeg_try IN LISTS _ffmpeg_roots)
    if(EXISTS "${_ffmpeg_try}/include/libavcodec/avcodec.h")
      set(FFMPEG_ROOT "${_ffmpeg_try}")
      break()
    endif()
  endforeach()
endif()
if(NOT FFMPEG_ROOT OR
   NOT EXISTS "${FFMPEG_ROOT}/include/libavcodec/avcodec.h")
  message(FATAL_ERROR
    "FFmpeg shared not found. Set FFMPEG_ROOT to the folder "
    "with include/ and lib/, for example the Gyan full_build-shared "
    "directory. In Qt Creator: Projects → Build → CMake → "
    "FFMPEG_ROOT.")
endif()
set(FFMPEG_ROOT "${FFMPEG_ROOT}" CACHE PATH
  "FFmpeg shared root with include/ and lib/")
get_filename_component(FFMPEG_ROOT "${FFMPEG_ROOT}" ABSOLUTE)
# MSVC link.exe fails on non-ASCII paths; stage libs/DLLs under build/.
set(_FFMPEG_STAGE "${CMAKE_BINARY_DIR}/ffmpeg_stage")
file(MAKE_DIRECTORY "${_FFMPEG_STAGE}/lib")
file(MAKE_DIRECTORY "${_FFMPEG_STAGE}/bin")
foreach(_fflib avcodec avformat avutil swscale swresample)
  configure_file("${FFMPEG_ROOT}/lib/${_fflib}.lib"
    "${_FFMPEG_STAGE}/lib/${_fflib}.lib" COPYONLY)
endforeach()
file(GLOB _FFMPEG_SRC_DLLS "${FFMPEG_ROOT}/bin/*.dll")
foreach(_ffdll IN LISTS _FFMPEG_SRC_DLLS)
  get_filename_component(_ffdll_name "${_ffdll}" NAME)
  configure_file("${_ffdll}"
    "${_FFMPEG_STAGE}/bin/${_ffdll_name}" COPYONLY)
endforeach()
file(GLOB _FFMPEG_DLLS "${_FFMPEG_STAGE}/bin/*.dll")

get_filename_component(_QT_ROOT "${Qt6_DIR}/../../.." ABSOLUTE)
set(_SQLITE_DIR "${_QT_ROOT}/plugins/sqldrivers")

function(youtube_copy_sqlite target)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:${target}>/sqldrivers"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_SQLITE_DIR}/$<IF:$<CONFIG:Debug>,qsqlited.dll,qsqlite.dll>"
            "$<TARGET_FILE_DIR:${target}>/sqldrivers/"
    VERBATIM)
endfunction()

function(youtube_copy_imageformats target)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:${target}>/imageformats"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_QT_ROOT}/plugins/imageformats/$<IF:$<CONFIG:Debug>,qjpegd.dll,qjpeg.dll>"
            "$<TARGET_FILE_DIR:${target}>/imageformats/"
    VERBATIM)
endfunction()

function(youtube_copy_ffmpeg target)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${_FFMPEG_DLLS}
            "$<TARGET_FILE_DIR:${target}>"
    VERBATIM)
endfunction()

function(youtube_copy_multimedia target)
  add_custom_command(TARGET ${target} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_QT_ROOT}/bin/$<IF:$<CONFIG:Debug>,Qt6Multimediad.dll,Qt6Multimedia.dll>"
            "$<TARGET_FILE_DIR:${target}>"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_QT_ROOT}/bin/$<IF:$<CONFIG:Debug>,Qt6Networkd.dll,Qt6Network.dll>"
            "$<TARGET_FILE_DIR:${target}>"
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:${target}>/multimedia"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_QT_ROOT}/plugins/multimedia/$<IF:$<CONFIG:Debug>,windowsmediaplugind.dll,windowsmediaplugin.dll>"
            "$<TARGET_FILE_DIR:${target}>/multimedia/"
    VERBATIM)
endfunction()

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

qt_add_library(creator_qml STATIC)
set_source_files_properties(qml/Theme.qml PROPERTIES
  QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(creator_qml
  URI Creator
  VERSION 1.0
  OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/Creator
  SOURCES
    src/window_state.h
    src/window_state.cpp
    src/library_store.h
    src/library_store.cpp
    src/library_model.h
    src/library_model.cpp
    src/media_model.h
    src/media_model.cpp
    src/dock_state.h
    src/dock_state.cpp
    src/media_io.h
    src/media_io.cpp
    src/project_document.h
    src/project_document.cpp
    src/frame_compositor.h
    src/frame_compositor.cpp
    src/exporter.h
    src/exporter.cpp
    src/preview_audio.h
    src/preview_audio.cpp
    src/secret_store.h
    src/secret_store.cpp
    src/http_transport.h
    src/http_transport.cpp
    src/chat_tool.h
    src/chat_tool.cpp
    src/speech_tool.h
    src/speech_tool.cpp
    src/pipeline.h
    src/pipeline.cpp
    src/scene_parser.h
    src/scene_parser.cpp
    src/video_tool.h
    src/video_tool.cpp
    src/cover_tool.h
    src/cover_tool.cpp
    src/channel_auth.h
    src/channel_auth.cpp
    src/publisher.h
    src/publisher.cpp
    src/stats_sync.h
    src/stats_sync.cpp
  QML_FILES
    qml/Main.qml
    qml/Theme.qml
    qml/HeaderBar.qml
    qml/ToolColumn.qml
    qml/DisabledTool.qml
    qml/Glyph.qml
    qml/FrameView.qml
    qml/TimelineHost.qml
    qml/LibraryPane.qml
    qml/MediaPane.qml
    qml/PanelChrome.qml
    qml/CapsuleButton.qml
    qml/HintTip.qml
    qml/AnalyticsView.qml
)
target_include_directories(creator_qml PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${FFMPEG_ROOT}/include")
target_link_libraries(creator_qml PUBLIC
  Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Multimedia
  Qt6::Network crypt32
  "${_FFMPEG_STAGE}/lib/avcodec.lib"
  "${_FFMPEG_STAGE}/lib/avformat.lib"
  "${_FFMPEG_STAGE}/lib/avutil.lib"
  "${_FFMPEG_STAGE}/lib/swscale.lib"
  "${_FFMPEG_STAGE}/lib/swresample.lib")
qt_add_resources(creator_qml window_icon
  PREFIX "/icons"
  BASE "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons"
  FILES
    assets/icons/window-icon.png
)
qt_add_resources(creator_qml fonts
  PREFIX "/fonts"
  BASE "${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts"
  FILES
    assets/fonts/Roboto-Regular.ttf
    assets/fonts/Roboto-Medium.ttf
    assets/fonts/Roboto-Bold.ttf
)

qt_add_executable(youtube-creator
  src/main.cpp
)
target_link_libraries(youtube-creator PRIVATE
  Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Multimedia
  Qt6::Network creator_qmlplugin)
youtube_copy_sqlite(youtube-creator)
youtube_copy_imageformats(youtube-creator)
youtube_copy_ffmpeg(youtube-creator)
youtube_copy_multimedia(youtube-creator)

qt_add_executable(shell_tests
  tests/tst_shell.cpp
  tests/temp_directory.cpp
  tests/temp_directory.h
)
target_link_libraries(shell_tests
  PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::QuickTest Qt6::Sql
          Qt6::Multimedia Qt6::Network creator_qmlplugin)
target_include_directories(shell_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src")
youtube_copy_sqlite(shell_tests)
youtube_copy_imageformats(shell_tests)
youtube_copy_ffmpeg(shell_tests)
youtube_copy_multimedia(shell_tests)
target_compile_definitions(shell_tests PRIVATE
  QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests"
)
