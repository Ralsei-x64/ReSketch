cmake_minimum_required(VERSION 3.21)

project(ReSketch VERSION 0.1.0 LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Network Quick QuickControls2 WebEngineQuick Widgets)
find_package(KF6WindowSystem REQUIRED)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(resketch src/main.cpp)
qt_add_qml_module(resketch
    URI org.aether64.resketch
    VERSION 1.0
    NO_IMPORT_SCAN
    QML_FILES src/Main.qml src/SettingsWindow.qml src/AboutWindow.qml src/WindowControls.qml src/WindowResizeHandles.qml src/TabBarButton.qml src/FigmaMenus.qml
    RESOURCES src/Policy.js src/FigmaMenu.js
)

qt_add_resources(resketch "branding"
    PREFIX "/"
    FILES Branding/SketchbookPNG/Folder-256.png
)

target_link_libraries(resketch PRIVATE
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::WebEngineQuick
    Qt6::Widgets
    KF6::WindowSystem
)

install(TARGETS resketch RUNTIME DESTINATION bin)
install(FILES org.aether64.resketch.desktop DESTINATION share/applications)
install(FILES Branding/SketchbookSVG/Folder-512.svg
        DESTINATION share/icons/hicolor/scalable/apps RENAME org.aether64.resketch.svg)
foreach(size 48 64 128 256 512)
    install(FILES Branding/SketchbookPNG/Folder-${size}.png
            DESTINATION share/icons/hicolor/${size}x${size}/apps RENAME org.aether64.resketch.png)
endforeach()
