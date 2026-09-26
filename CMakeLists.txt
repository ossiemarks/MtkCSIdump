cmake_minimum_required(VERSION 3.10)
project(CSIdump CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)

set(SOURCES
  parsers/parser_mt76.cpp
  wifi_drv_api/mt76_api.cpp
  motion_detector.cpp
  md.cpp
)

include_directories(${CMAKE_SOURCE_DIR})

# libnl-tiny: headers live under <prefix>/include/libnl-tiny on OpenWrt.
# Override with -DLIBNL_TINY_INCLUDE_DIR=... / -DLIBNL_TINY_LIBRARY=... if needed.
find_path(LIBNL_TINY_INCLUDE_DIR unl.h PATH_SUFFIXES libnl-tiny)
find_library(LIBNL_TINY_LIBRARY NAMES nl-tiny)
if(NOT LIBNL_TINY_INCLUDE_DIR OR NOT LIBNL_TINY_LIBRARY)
  message(FATAL_ERROR "libnl-tiny not found (include: ${LIBNL_TINY_INCLUDE_DIR}, lib: ${LIBNL_TINY_LIBRARY})")
endif()
include_directories(${LIBNL_TINY_INCLUDE_DIR})

add_compile_options(-Wall -Wextra)

add_executable(CSIdump ${SOURCES} main.cpp)

find_package(Threads REQUIRED)
target_link_libraries(CSIdump PRIVATE Threads::Threads ${LIBNL_TINY_LIBRARY})

install(TARGETS CSIdump RUNTIME DESTINATION bin)
