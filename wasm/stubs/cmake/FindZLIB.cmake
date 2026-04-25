# ZLIB shim:
#   - Emscripten: redirect to -sUSE_ZLIB=1 port via INTERFACE imported target.
#   - Native (BAR_USE_STUBS=1): defer to CMake's stock FindZLIB.cmake by
#     explicit path; naive find_package() recursion-traps because
#     list(REMOVE_ITEM) doesn't propagate to the recursive call's scope.
if (NOT EMSCRIPTEN)
    include("${CMAKE_ROOT}/Modules/FindZLIB.cmake")
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
