# SDL2 shim:
#   - Emscripten: redirect to -sUSE_SDL=2 port via INTERFACE imported target.
#   - Native (BAR_USE_STUBS=1): there's no stock FindSDL2.cmake; SDL2's
#     installed sdl2-config.cmake provides a CONFIG package. Use that.
if (NOT EMSCRIPTEN)
    find_package(SDL2 CONFIG REQUIRED)
    return()
endif()

set(SDL2_FOUND TRUE)
set(SDL2_VERSION "2.28.0")
set(SDL2_LIBRARY "")
set(SDL2_LIBRARIES "")
set(SDL2_INCLUDE_DIR "")
set(SDL2_INCLUDE_DIRS "")

if (NOT TARGET SDL2::SDL2)
    add_library(SDL2::SDL2 INTERFACE IMPORTED GLOBAL)
    target_compile_options(SDL2::SDL2 INTERFACE "SHELL:-sUSE_SDL=2")
    target_link_options(SDL2::SDL2 INTERFACE "SHELL:-sUSE_SDL=2")
endif()
if (NOT TARGET SDL2::SDL2main)
    add_library(SDL2::SDL2main INTERFACE IMPORTED GLOBAL)
    target_link_libraries(SDL2::SDL2main INTERFACE SDL2::SDL2)
endif()
