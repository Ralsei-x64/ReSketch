cmake_minimum_required(VERSION 3.21)

project(ReSketch VERSION 0.1.0 LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Network Quick QuickControls2 WebEngineQuick Widgets)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6ColorScheme 6.6 REQUIRED)
find_package(KF6IconThemes 6.3 REQUIRED)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(resketch src/main.cpp)
qt_add_qml_module(resketch
    URI org.aether64.resketch
    VERSION 1.0
    NO_IMPORT_SCAN
    QML_FILES src/Main.qml src/SettingsWindow.qml src/AboutWindow.qml src/ExportHistoryWindow.qml src/WindowControls.qml src/WindowResizeHandles.qml src/TabBarButton.qml src/FigmaMenus.qml
    RESOURCES src/Policy.js src/FigmaMenu.js src/FigmaTheme.js
)

qt_add_resources(resketch "branding"
    PREFIX "/"
    FILES Branding/SketchbookPNG/Folder-256.png
)

set(resketch_libraries
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::WebEngineQuick
    Qt6::Widgets
    KF6::WindowSystem
    KF6::ColorScheme
    KF6::IconThemes
)
target_link_libraries(resketch PRIVATE ${resketch_libraries})

include(CTest)
if(BUILD_TESTING)
    foreach(test_name export-folders theme)
        add_executable(resketch-${test_name}-test tests/${test_name}.test.cpp)
        # These tests include main.cpp and reuse the app's generated main.moc.
        set_target_properties(resketch-${test_name}-test PROPERTIES AUTOMOC OFF)
        add_dependencies(resketch-${test_name}-test resketch)
        target_include_directories(resketch-${test_name}-test PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/resketch_autogen/include)
        target_link_libraries(resketch-${test_name}-test PRIVATE ${resketch_libraries})
        target_compile_options(resketch-${test_name}-test PRIVATE -UNDEBUG)
        target_compile_definitions(resketch-${test_name}-test PRIVATE RESKETCH_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME ${test_name} COMMAND resketch-${test_name}-test)
        set_tests_properties(${test_name} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
    endforeach()
endif()

install(TARGETS resketch RUNTIME DESTINATION bin)
install(FILES org.aether64.resketch.desktop DESTINATION share/applications)
install(FILES Branding/SketchbookSVG/Folder-512.svg
        DESTINATION share/icons/hicolor/scalable/apps RENAME org.aether64.resketch.svg)
foreach(size 48 64 128 256 512)
    install(FILES Branding/SketchbookPNG/Folder-${size}.png
            DESTINATION share/icons/hicolor/${size}x${size}/apps RENAME org.aether64.resketch.png)
endforeach()
