cmake_minimum_required(VERSION 3.10)
project(yp-demo-cmake VERSION 0.1 LANGUAGES C)

set(YP_DEMO_VARIANT "default" CACHE STRING "Demo build-system variant")
add_executable(yp-demo-cmake demo.c)
target_compile_definitions(yp-demo-cmake PRIVATE YP_DEMO_VARIANT="${YP_DEMO_VARIANT}")
