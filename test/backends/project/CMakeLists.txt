cmake_minimum_required(VERSION 3.14)
project(backward_backends_test CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)

if(NOT DEFINED BACKWARD_SOURCE_DIR)
	message(FATAL_ERROR "BACKWARD_SOURCE_DIR is required")
endif()

# Pull in Backward with its normal CMake integration. The selected backends are
# visible in the configure output and are carried by Backward::Interface.
add_subdirectory("${BACKWARD_SOURCE_DIR}" backward)

add_executable(backends main.cpp)
target_link_libraries(backends PRIVATE Backward::Interface)

# Exercise the header-only path as well: no Backward target, no selection
# defines, just the header's own platform defaults.
add_executable(backends_manual main.cpp)
target_include_directories(backends_manual PRIVATE "${BACKWARD_SOURCE_DIR}")
if(WIN32)
	target_link_libraries(backends_manual PRIVATE dbghelp psapi)
endif()
