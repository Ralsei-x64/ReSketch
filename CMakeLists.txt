# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only

cmake_minimum_required(VERSION 3.21)

project(ReSketch VERSION 1.4.8 LANGUAGES C CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Concurrent Network Quick QuickControls2 OpenGL Widgets)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Notifications REQUIRED)
find_package(KF6ColorScheme 6.6 REQUIRED)
find_package(KF6IconThemes 6.3 REQUIRED)
find_package(Fontconfig REQUIRED)
find_package(Freetype REQUIRED)

# Embed the source commit and refresh it when the checked-out revision changes.
find_package(Git QUIET)
set(RESKETCH_COMMIT "unknown")
if(GIT_FOUND)
    execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --short=7 HEAD
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        OUTPUT_VARIABLE git_commit OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET RESULT_VARIABLE git_result)
    if(git_result EQUAL 0)
        set(RESKETCH_COMMIT "${git_commit}")
        execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --path-format=absolute --git-path HEAD
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            OUTPUT_VARIABLE git_head OUTPUT_STRIP_TRAILING_WHITESPACE)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${git_head}")
        file(STRINGS "${git_head}" git_ref)
        if(git_ref MATCHES "^ref: (.+)$")
            execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --path-format=absolute --git-path "${CMAKE_MATCH_1}"
                WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
                OUTPUT_VARIABLE git_ref_path OUTPUT_STRIP_TRAILING_WHITESPACE)
            if(EXISTS "${git_ref_path}")
                set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${git_ref_path}")
            endif()
            get_filename_component(git_ref_directory "${git_ref_path}" DIRECTORY)
            if(EXISTS "${git_ref_directory}")
                set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${git_ref_directory}")
            endif()
        endif()
    endif()
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(cmake/CEF.cmake)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0)
pkg_check_modules(EGL REQUIRED IMPORTED_TARGET egl)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_qml_module(resketch_cef SHARED
    URI ReSketch.Cef VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/ReSketch/Cef"
    SOURCES src/CefView.h src/CefView.cpp src/CefApp.h src/CefApp.cpp src/CefTexture.h src/CefTexture.cpp)
target_include_directories(resketch_cef PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(resketch_cef PUBLIC Qt6::Quick cef_shared libcef_dll_wrapper PRIVATE Qt6::OpenGL Qt6::Widgets Qt6::Network PkgConfig::EGL PkgConfig::GLIB)
target_compile_definitions(resketch_cef PRIVATE RESKETCH_CEF_RUNTIME="${RESKETCH_CEF_RUNTIME}")
set_target_properties(resketch_cef PROPERTIES BUILD_RPATH "${RESKETCH_CEF_RUNTIME}" INSTALL_RPATH "$ORIGIN/cef")
qt_add_executable(resketch-cef-helper src/CefProcess.cpp src/CefApp.cpp src/CefApp.h)
target_link_libraries(resketch-cef-helper PRIVATE Qt6::Core cef_shared libcef_dll_wrapper)
set_target_properties(resketch-cef-helper PROPERTIES BUILD_RPATH "${RESKETCH_CEF_RUNTIME}" INSTALL_RPATH "$ORIGIN/../lib/ReSketch/cef")
install(TARGETS resketch_cef LIBRARY DESTINATION lib/ReSketch)
install(TARGETS resketch_cefplugin LIBRARY DESTINATION lib/qt6/qml/ReSketch/Cef)
install(FILES "${CMAKE_BINARY_DIR}/qml/ReSketch/Cef/qmldir" "${CMAKE_BINARY_DIR}/qml/ReSketch/Cef/resketch_cef.qmltypes" DESTINATION lib/qt6/qml/ReSketch/Cef)
install(TARGETS resketch-cef-helper RUNTIME DESTINATION bin)

qt_add_executable(resketch src/main.cpp src/FontHelper.cpp src/FontHelper.h src/UpdateChecker.cpp src/UpdateChecker.h)
target_compile_definitions(resketch PRIVATE
    RESKETCH_VERSION="${PROJECT_VERSION}"
    RESKETCH_COMMIT="${RESKETCH_COMMIT}"
    RESKETCH_QML_IMPORT_PATH="${CMAKE_BINARY_DIR}/qml"
)
qt_add_qml_module(resketch
    URI org.aether64.resketch
    VERSION 1.0
    NO_IMPORT_SCAN
    QML_FILES src/Main.qml src/SettingsWindow.qml src/AboutWindow.qml src/ExportHistoryWindow.qml src/WindowControls.qml src/WindowResizeHandles.qml src/TabBarButton.qml src/ScrollGestureArea.qml src/FigmaMenus.qml src/TabGroupMenu.qml src/ChromiumToolsWindow.qml src/ExternalWindowHeader.qml src/UpdateSettings.qml src/UpdateDialog.qml src/UpdateCompleteDialog.qml src/ChangelogDialog.qml
    RESOURCES src/Policy.js src/FigmaMenu.js src/FigmaTheme.js src/NotificationPolicy.js src/Shortcuts.js
)

qt_add_resources(resketch "branding"
    PREFIX "/"
    FILES Branding/SketchbookPNG/Folder-256.png
          CHANGELOG.txt
)

target_link_libraries(resketch PRIVATE
    Qt6::Concurrent
    Fontconfig::Fontconfig
    Freetype::Freetype
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    resketch_cef
    Qt6::Widgets
    KF6::WindowSystem
    KF6::Notifications
    KF6::ColorScheme
    KF6::IconThemes
)

# Chromium's close() interposer uses RTLD_NEXT to reach libc. Retain the
# transitive CEF dependency here so it loads before libc in release builds.
target_link_options(resketch PRIVATE "LINKER:--no-as-needed")
set_target_properties(resketch PROPERTIES INSTALL_RPATH "$ORIGIN/../lib/ReSketch;$ORIGIN/../lib/ReSketch/cef")
set_target_properties(resketch_cefplugin PROPERTIES INSTALL_RPATH "$ORIGIN/../../../../ReSketch;$ORIGIN/../../../../ReSketch/cef")
install(TARGETS resketch RUNTIME DESTINATION bin)
option(RESKETCH_BUILD_TESTS "Build CEF integration checks" OFF)
if(RESKETCH_BUILD_TESTS)
    qt_add_executable(cef-engine-test tests/cef-engine.test.cpp)
    target_link_libraries(cef-engine-test PRIVATE resketch_cef Qt6::Widgets Qt6::Network)
    target_compile_definitions(cef-engine-test PRIVATE RESKETCH_TEST_IMPORTS="${CMAKE_BINARY_DIR}/qml")
    set_target_properties(cef-engine-test PROPERTIES BUILD_RPATH "${RESKETCH_CEF_RUNTIME}")
endif()
install(FILES LICENSE DESTINATION share/licenses/resketch)
install(FILES org.aether64.resketch.desktop DESTINATION share/applications)
install(FILES org.aether64.resketch.notifyrc DESTINATION share/knotifications6)
install(FILES Branding/SketchbookSVG/Folder-512.svg
        DESTINATION share/icons/hicolor/scalable/apps RENAME org.aether64.resketch.svg)
foreach(size 48 64 128 256 512)
    install(FILES Branding/SketchbookPNG/Folder-${size}.png
            DESTINATION share/icons/hicolor/${size}x${size}/apps RENAME org.aether64.resketch.png)
endforeach()
