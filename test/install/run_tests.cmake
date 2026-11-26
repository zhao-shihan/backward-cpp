# Installs the current build into a scratch prefix and verifies that a separate
# project can consume it through find_package(Backward).
#
# This covers the generated BackwardConfig.cmake, the exported targets, their
# baked compile definitions, and their link libraries.

cmake_minimum_required(VERSION 3.14)

foreach(required
		BACKWARD_BINARY_DIR BACKWARD_TEST_SOURCE_DIR BACKWARD_TEST_BINARY_DIR
		BACKWARD_INSTALL_PREFIX BACKWARD_INSTALL_LIBDIR BACKWARD_GENERATOR
		BACKWARD_CXX_COMPILER BACKWARD_EXE_SUFFIX)
	if(NOT DEFINED ${required})
		message(FATAL_ERROR "run_tests.cmake: ${required} is required")
	endif()
endforeach()

if(BACKWARD_BINARY_DIR STREQUAL "" OR BACKWARD_INSTALL_PREFIX STREQUAL "")
	message(FATAL_ERROR "run_tests.cmake: the install directories must not be empty")
endif()
if(BACKWARD_TEST_BINARY_DIR STREQUAL "/" OR BACKWARD_INSTALL_PREFIX STREQUAL "/")
	message(FATAL_ERROR "run_tests.cmake: refusing to use '/' as a test directory")
endif()

file(REMOVE_RECURSE "${BACKWARD_TEST_BINARY_DIR}" "${BACKWARD_INSTALL_PREFIX}")
file(MAKE_DIRECTORY "${BACKWARD_TEST_BINARY_DIR}")

set(install_script "${BACKWARD_BINARY_DIR}/cmake_install.cmake")
if(NOT EXISTS "${install_script}")
	message(FATAL_ERROR "missing install script ${install_script}; build the project first")
endif()

# cmake --install requires CMake 3.15, while Backward still supports 3.14.
set(install_command
	"${CMAKE_COMMAND}"
	"-DCMAKE_INSTALL_PREFIX=${BACKWARD_INSTALL_PREFIX}")
if(BACKWARD_MULTI_CONFIG)
	list(APPEND install_command "-DCMAKE_INSTALL_CONFIG_NAME=${BACKWARD_BUILD_CONFIG}")
endif()
list(APPEND install_command -P "${install_script}")
execute_process(COMMAND ${install_command}
	RESULT_VARIABLE install_result
	OUTPUT_VARIABLE install_output
	ERROR_VARIABLE install_error)
if(NOT install_result EQUAL 0)
	message(FATAL_ERROR "installation failed.\n${install_output}\n${install_error}")
endif()

set(backward_config_dir
	"${BACKWARD_INSTALL_PREFIX}/${BACKWARD_INSTALL_LIBDIR}/cmake/backward")
if(NOT EXISTS "${backward_config_dir}/BackwardConfig.cmake")
	message(FATAL_ERROR
		"the installed package has no BackwardConfig.cmake under ${backward_config_dir}")
endif()

set(configure_command
	"${CMAKE_COMMAND}"
	-S "${BACKWARD_TEST_SOURCE_DIR}"
	-B "${BACKWARD_TEST_BINARY_DIR}"
	-G "${BACKWARD_GENERATOR}"
	"-DCMAKE_CXX_COMPILER=${BACKWARD_CXX_COMPILER}"
	"-DCMAKE_PREFIX_PATH=${BACKWARD_INSTALL_PREFIX}"
	"-DBackward_DIR=${backward_config_dir}")
if(DEFINED BACKWARD_BUILD_TYPE AND NOT BACKWARD_BUILD_TYPE STREQUAL "")
	list(APPEND configure_command "-DCMAKE_BUILD_TYPE=${BACKWARD_BUILD_TYPE}")
endif()
if(DEFINED BACKWARD_TOOLCHAIN_FILE AND NOT BACKWARD_TOOLCHAIN_FILE STREQUAL "")
	list(APPEND configure_command "-DCMAKE_TOOLCHAIN_FILE=${BACKWARD_TOOLCHAIN_FILE}")
endif()
if(DEFINED BACKWARD_MAKE_PROGRAM AND NOT BACKWARD_MAKE_PROGRAM STREQUAL "")
	list(APPEND configure_command "-DCMAKE_MAKE_PROGRAM=${BACKWARD_MAKE_PROGRAM}")
endif()
if(DEFINED BACKWARD_VERSION AND NOT BACKWARD_VERSION STREQUAL "")
	list(APPEND configure_command "-DBACKWARD_EXPECTED_VERSION=${BACKWARD_VERSION}")
endif()

execute_process(COMMAND ${configure_command}
	RESULT_VARIABLE configure_result
	OUTPUT_VARIABLE configure_output
	ERROR_VARIABLE configure_error)
if(NOT configure_result EQUAL 0)
	message(FATAL_ERROR
		"the installed package could not be configured.\n${configure_output}\n${configure_error}")
endif()

set(build_command "${CMAKE_COMMAND}" --build "${BACKWARD_TEST_BINARY_DIR}")
if(BACKWARD_MULTI_CONFIG)
	list(APPEND build_command --config "${BACKWARD_BUILD_CONFIG}")
endif()
execute_process(COMMAND ${build_command}
	RESULT_VARIABLE build_result
	OUTPUT_VARIABLE build_output
	ERROR_VARIABLE build_error)
if(NOT build_result EQUAL 0)
	message(FATAL_ERROR "the installed package consumer failed to build.\n${build_output}\n${build_error}")
endif()

set(exe_dir "${BACKWARD_TEST_BINARY_DIR}")
if(BACKWARD_MULTI_CONFIG)
	set(exe_dir "${BACKWARD_TEST_BINARY_DIR}/${BACKWARD_BUILD_CONFIG}")
endif()

# A shared Backward library is installed into bin/ on Windows, so make sure the
# runtime loader can find it.
if(WIN32)
	set(_path_separator ";")
else()
	set(_path_separator ":")
endif()
set(_run_environment "PATH=${BACKWARD_INSTALL_PREFIX}/bin${_path_separator}$ENV{PATH}")

if(BACKWARD_SELECTED_UNWINDER STREQUAL "none")
	set(_frames_regex "frames=0")
else()
	set(_frames_regex "frames=[1-9]")
endif()

foreach(executable consumer_interface consumer_backward)
	set(path "${exe_dir}/${executable}${BACKWARD_EXE_SUFFIX}")
	execute_process(COMMAND "${CMAKE_COMMAND}" -E env "${_run_environment}" "${path}"
		RESULT_VARIABLE run_result
		OUTPUT_VARIABLE run_output
		ERROR_VARIABLE run_error)
	if(NOT run_result EQUAL 0)
		message(FATAL_ERROR "${path} failed with ${run_result}.\n${run_output}\n${run_error}")
	endif()
	if(NOT run_output MATCHES "${_frames_regex}")
		message(FATAL_ERROR "${path} produced unexpected output:\n${run_output}")
	endif()
	if(NOT run_output MATCHES "walker=([a-z-]+) symbolizer=([a-z-]+)")
		message(FATAL_ERROR "${path} did not report its selected backends:\n${run_output}")
	endif()
	set(_program_walker "${CMAKE_MATCH_1}")
	set(_program_symbolizer "${CMAKE_MATCH_2}")
	if(NOT _program_walker STREQUAL BACKWARD_SELECTED_UNWINDER)
		message(FATAL_ERROR
			"${path} was built with walker=${_program_walker}, but the package selected ${BACKWARD_SELECTED_UNWINDER}")
	endif()
	if(NOT _program_symbolizer STREQUAL BACKWARD_SELECTED_SYMBOLIZER)
		message(FATAL_ERROR
			"${path} was built with symbolizer=${_program_symbolizer}, but the package selected ${BACKWARD_SELECTED_SYMBOLIZER}")
	endif()
	message(STATUS "[PASS] installed consumer ${executable}")
endforeach()

message(STATUS "Installed package test passed")
