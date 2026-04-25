if (NOT EMSCRIPTEN)
    # Defer to CMake's stock FindFontconfig.cmake by explicit path; naive
    # find_package() recursion-traps because list(REMOVE_ITEM) doesn't
    # propagate to the recursive call's scope.
    include("${CMAKE_ROOT}/Modules/FindFontconfig.cmake")
    return()
endif()
# Headless replay doesn't need font config discovery — stub as empty interface.
set(Fontconfig_FOUND TRUE)
set(Fontconfig_VERSION "2.14.0")
set(Fontconfig_LIBRARIES "")
set(Fontconfig_INCLUDE_DIRS "")
if (NOT TARGET Fontconfig::Fontconfig)
    add_library(Fontconfig::Fontconfig INTERFACE IMPORTED GLOBAL)
endif()
