# Ether Shell's native plugin: the work that runs all the time, in C++.
#
#   SystemStats   CPU, memory and network from /proc, and the GPU through
#                 NVIDIA's own library (NVML), in-process: no helper programs
#   CavaReader    the visualiser's bars, read from cava's binary output
#   ArtColors     accent colours from album art, for the media views
#
# Optional: the shell falls back to its own readers when this isn't built.
#
#   cmake -S native -B build -DCMAKE_BUILD_TYPE=Release
#   cmake --build build
#   cmake --install build          # to ~/.local/lib/ether-shell/qml
cmake_minimum_required(VERSION 3.16)
project(ether_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Network Qml Concurrent)
qt_standard_project_setup()
# the modern resource location for QML modules (and no warning about it)
if(QT_KNOWN_POLICY_QTP0001)
    qt_policy(SET QTP0001 NEW)
endif()

# the built module lands in build/qml/Ether/Native, ready to install
set(QT_QML_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml)

qt_add_qml_module(ethernative
    URI Ether.Native
    VERSION 1.0
    PLUGIN_TARGET ethernative
    SOURCES
        src/systemstats.h src/systemstats.cpp
        src/cavareader.h  src/cavareader.cpp
        src/artcolors.h   src/artcolors.cpp
        src/fileindex.h   src/fileindex.cpp
        src/ddc.h         src/ddc.cpp       src/ddcproto.h
        src/audiobars.h   src/audiobars.cpp src/spectrum.h
        src/clipboard.h   src/clipboard.cpp
)
# Qt's generated type registration includes the headers by name
target_include_directories(ethernative PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(ethernative PRIVATE Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Concurrent ${CMAKE_DL_LIBS})
target_compile_options(ethernative PRIVATE -Wall -Wextra)

# the visualiser straight from PipeWire (without it, AudioBars reports
# itself unavailable and the shell runs cava instead)
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(PIPEWIRE QUIET IMPORTED_TARGET libpipewire-0.3)
endif()
if(PIPEWIRE_FOUND)
    target_link_libraries(ethernative PRIVATE PkgConfig::PIPEWIRE)
    target_compile_definitions(ethernative PRIVATE ETHER_HAVE_PIPEWIRE)
    message(STATUS "Visualiser: PipeWire ${PIPEWIRE_VERSION}")
else()
    message(STATUS "Visualiser: no PipeWire development files; the shell will use cava")
endif()

set(ETHER_QML_DIR "$ENV{HOME}/.local/lib/ether-shell/qml"
    CACHE PATH "Where the Ether.Native module is installed")
install(DIRECTORY ${CMAKE_BINARY_DIR}/qml/Ether DESTINATION ${ETHER_QML_DIR})

# the clipboard straight from the compositor (wlr data-control); without
# Wayland's development files, ClipboardHistory reports itself unavailable
# and the shell keeps using wl-paste and cliphist
if(PkgConfig_FOUND)
    pkg_check_modules(WAYLAND QUIET IMPORTED_TARGET wayland-client)
    find_program(WAYLAND_SCANNER wayland-scanner)
endif()
if(WAYLAND_FOUND AND WAYLAND_SCANNER)
    set(DC_XML ${CMAKE_CURRENT_SOURCE_DIR}/protocols/wlr-data-control-unstable-v1.xml)
    set(DC_H   ${CMAKE_CURRENT_BINARY_DIR}/wlr-data-control-unstable-v1-client-protocol.h)
    set(DC_C   ${CMAKE_CURRENT_BINARY_DIR}/wlr-data-control-unstable-v1-protocol.c)
    add_custom_command(OUTPUT ${DC_H} COMMAND ${WAYLAND_SCANNER} client-header ${DC_XML} ${DC_H} DEPENDS ${DC_XML})
    add_custom_command(OUTPUT ${DC_C} COMMAND ${WAYLAND_SCANNER} private-code ${DC_XML} ${DC_C} DEPENDS ${DC_XML})
    target_sources(ethernative PRIVATE ${DC_H} ${DC_C})
    target_include_directories(ethernative PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
    target_link_libraries(ethernative PRIVATE PkgConfig::WAYLAND)
    target_compile_definitions(ethernative PRIVATE ETHER_HAVE_WAYLAND)
    message(STATUS "Clipboard: Wayland ${WAYLAND_VERSION} (wlr data-control)")
else()
    message(STATUS "Clipboard: no Wayland development files; the shell will use cliphist")
endif()
