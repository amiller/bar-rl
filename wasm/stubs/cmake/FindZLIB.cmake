# ZLIB shim for Emscripten builds — redirects find_package(ZLIB) to
# emscripten's -sUSE_ZLIB=1 port via an INTERFACE imported target.
if (NOT EMSCRIPTEN)
    # Fall through to CMake's bundled FindZLIB.cmake
    list(REMOVE_ITEM CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")
    find_package(ZLIB ${ZLIB_FIND_VERSION})
    list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")
    return()
endif()

set(ZLIB_FOUND TRUE)
set(ZLIB_VERSION_STRING "1.3.1")
set(ZLIB_LIBRARY "")
set(ZLIB_LIBRARIES "")
set(ZLIB_INCLUDE_DIR "")
set(ZLIB_INCLUDE_DIRS "")

if (NOT TARGET ZLIB::ZLIB)
    add_library(ZLIB::ZLIB INTERFACE IMPORTED GLOBAL)
    target_compile_options(ZLIB::ZLIB INTERFACE "SHELL:-sUSE_ZLIB=1")
    target_link_options(ZLIB::ZLIB INTERFACE "SHELL:-sUSE_ZLIB=1")
endif()
