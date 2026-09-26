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
project(ether_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Network Qml)
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
)
# Qt's generated type registration includes the headers by name
target_include_directories(ethernative PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(ethernative PRIVATE Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml ${CMAKE_DL_LIBS})
target_compile_options(ethernative PRIVATE -Wall -Wextra)

set(ETHER_QML_DIR "$ENV{HOME}/.local/lib/ether-shell/qml"
    CACHE PATH "Where the Ether.Native module is installed")
install(DIRECTORY ${CMAKE_BINARY_DIR}/qml/Ether DESTINATION ${ETHER_QML_DIR})
