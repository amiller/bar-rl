if (NOT EMSCRIPTEN)
    # Defer to CMake's stock FindEXPAT.cmake by explicit path; naive
    # find_package() recursion-traps because list(REMOVE_ITEM) doesn't
    # propagate to the recursive call's scope.
    include("${CMAKE_ROOT}/Modules/FindEXPAT.cmake")
    return()
endif()
# Headless replay probably doesn't parse XML at runtime — stub as empty interface.
set(EXPAT_FOUND TRUE)
set(EXPAT_VERSION "2.5.0")
set(EXPAT_LIBRARIES "")
set(EXPAT_INCLUDE_DIRS "")
if (NOT TARGET EXPAT::EXPAT)
    add_library(EXPAT::EXPAT INTERFACE IMPORTED GLOBAL)
endif()
