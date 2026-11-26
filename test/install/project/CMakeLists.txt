cmake_minimum_required(VERSION 3.14)
project(backward_install_test CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED True)

if(DEFINED BACKWARD_EXPECTED_VERSION AND NOT BACKWARD_EXPECTED_VERSION STREQUAL "")
	find_package(Backward ${BACKWARD_EXPECTED_VERSION} REQUIRED)
else()
	find_package(Backward REQUIRED)
endif()

# Header-only consumer, using the exported Backward::Interface target.
add_executable(consumer_interface main.cpp)
target_link_libraries(consumer_interface PRIVATE Backward::Interface)

# Compiled-library consumer, using the exported Backward::Backward target.
add_executable(consumer_backward main.cpp)
target_link_libraries(consumer_backward PRIVATE Backward::Backward)
# Reference a symbol from backward.cpp so the static library object is actually
# pulled in, and its backend link libraries are exercised.
target_compile_definitions(consumer_backward PRIVATE
	BACKWARD_TEST_USE_SIGNAL_HANDLING)
