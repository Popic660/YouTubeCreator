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

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 QuickTest)

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
)
target_include_directories(creator_qml PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(creator_qml PUBLIC Qt6::Quick Qt6::QuickControls2)
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
target_link_libraries(youtube-creator PRIVATE Qt6::Quick Qt6::QuickControls2 creator_qmlplugin)

qt_add_executable(shell_tests
  tests/tst_shell.cpp
)
target_link_libraries(shell_tests
  PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::QuickTest creator_qmlplugin)
target_compile_definitions(shell_tests PRIVATE
  QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests"
)
