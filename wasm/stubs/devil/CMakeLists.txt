# Stub DevIL for headless WASM Recoil build.
cmake_minimum_required(VERSION 3.10)
project(devil_stub C)
add_library(IL_stub STATIC src/il_stub.c)
target_include_directories(IL_stub PUBLIC include)
set_target_properties(IL_stub PROPERTIES OUTPUT_NAME IL)

# Recoil engine links against DevIL::IL (namespaced). Provide the alias.
if (NOT TARGET DevIL::IL)
    add_library(DevIL::IL ALIAS IL_stub)
endif()
