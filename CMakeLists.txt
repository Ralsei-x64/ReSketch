# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only

cmake_minimum_required(VERSION 3.21)

project(ReSketch VERSION 0.3.3 LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Concurrent Network Quick QuickControls2 WebEngineQuick Widgets)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Notifications REQUIRED)
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

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(resketch src/main.cpp src/FontHelper.cpp src/FontHelper.h)
target_compile_definitions(resketch PRIVATE
    RESKETCH_VERSION="${PROJECT_VERSION}"
    RESKETCH_COMMIT="${RESKETCH_COMMIT}"
)
qt_add_qml_module(resketch
    URI org.aether64.resketch
    VERSION 1.0
    NO_IMPORT_SCAN
    QML_FILES src/Main.qml src/SettingsWindow.qml src/AboutWindow.qml src/ExportHistoryWindow.qml src/WindowControls.qml src/WindowResizeHandles.qml src/TabBarButton.qml src/FigmaMenus.qml src/TabGroupMenu.qml src/ChromiumToolsWindow.qml src/ExternalWindowHeader.qml
    RESOURCES src/Policy.js src/FigmaMenu.js src/FigmaTheme.js src/NotificationPolicy.js src/Shortcuts.js
)

qt_add_resources(resketch "branding"
    PREFIX "/"
    FILES Branding/SketchbookPNG/Folder-256.png
)

target_link_libraries(resketch PRIVATE
    Qt6::Concurrent
    Fontconfig::Fontconfig
    Freetype::Freetype
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::WebEngineQuick
    Qt6::Widgets
    KF6::WindowSystem
    KF6::Notifications
)

install(TARGETS resketch RUNTIME DESTINATION bin)
install(FILES LICENSE DESTINATION share/licenses/resketch)
install(FILES org.aether64.resketch.desktop DESTINATION share/applications)
install(FILES org.aether64.resketch.notifyrc DESTINATION share/knotifications6)
install(FILES Branding/SketchbookSVG/Folder-512.svg
        DESTINATION share/icons/hicolor/scalable/apps RENAME org.aether64.resketch.svg)
foreach(size 48 64 128 256 512)
    install(FILES Branding/SketchbookPNG/Folder-${size}.png
            DESTINATION share/icons/hicolor/${size}x${size}/apps RENAME org.aether64.resketch.png)
endforeach()
