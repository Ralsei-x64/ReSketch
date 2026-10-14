# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only
set(CEF_VERSION "154.0.34+g14c5a08+chromium-154.0.8037.98")
set(CEF_ARCHIVE "cef_binary_${CEF_VERSION}_linux64_minimal.tar.bz2")
set(CEF_ROOT "" CACHE PATH "Extracted CEF binary distribution")
if(NOT CEF_ROOT AND DEFINED ENV{CEF_ROOT})
    set(CEF_ROOT "$ENV{CEF_ROOT}")
endif()
if(NOT CEF_ROOT)
    include(FetchContent)
    FetchContent_Declare(cef_binary
        URL "https://cef-builds.spotifycdn.com/${CEF_ARCHIVE}"
        URL_HASH SHA1=15c91ad767097217b2e82ba8b933fe30b134be69
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    FetchContent_GetProperties(cef_binary)
    if(NOT cef_binary_POPULATED)
        FetchContent_Populate(cef_binary)
    endif()
    set(CEF_ROOT "${cef_binary_SOURCE_DIR}")
endif()
# Load the distribution's wrapper configuration without building its sample apps.
list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
find_package(CEF REQUIRED)
add_subdirectory("${CEF_ROOT}/libcef_dll" "${CMAKE_BINARY_DIR}/cef-wrapper" EXCLUDE_FROM_ALL)
add_library(cef_shared SHARED IMPORTED GLOBAL)
set_target_properties(cef_shared PROPERTIES IMPORTED_LOCATION "${CMAKE_BINARY_DIR}/cef/libcef.so"
    INTERFACE_INCLUDE_DIRECTORIES "${CEF_ROOT}")
set_target_properties(libcef_dll_wrapper PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(libcef_dll_wrapper PUBLIC CEF_API_VERSION=15400)
set(RESKETCH_CEF_RUNTIME "${CMAKE_BINARY_DIR}/cef")
file(MAKE_DIRECTORY "${RESKETCH_CEF_RUNTIME}")
foreach(directory Release Resources)
    file(COPY "${CEF_ROOT}/${directory}/" DESTINATION "${RESKETCH_CEF_RUNTIME}")
endforeach()
install(DIRECTORY "${RESKETCH_CEF_RUNTIME}/" DESTINATION lib/ReSketch/cef USE_SOURCE_PERMISSIONS)
install(FILES "${CEF_ROOT}/LICENSE.txt" DESTINATION share/licenses/resketch RENAME CEF-LICENSE.txt)
