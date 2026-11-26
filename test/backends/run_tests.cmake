# Configures, builds and runs a matrix of consumer projects to verify the
# dependency-selection semantics of cmake/BackwardDependencies.cmake.
#
# Invoked by CTest with the outer build's toolchain information. Every case is a
# fully separate CMake configure, so the compile/link probes see the same
# environment as a real consumer.

cmake_minimum_required(VERSION 3.14)

foreach(required
		BACKWARD_SOURCE_DIR BACKWARD_TEST_SOURCE_DIR BACKWARD_TEST_BINARY_DIR
		BACKWARD_GENERATOR BACKWARD_CXX_COMPILER BACKWARD_PLATFORM
		BACKWARD_EXE_SUFFIX)
	if(NOT DEFINED ${required})
		message(FATAL_ERROR "run_tests.cmake: ${required} is required")
	endif()
endforeach()

if(NOT BACKWARD_PLATFORM MATCHES "^(linux|darwin|windows)$")
	message(STATUS "Skipping backend tests on unsupported platform '${BACKWARD_PLATFORM}'")
	return()
endif()

if(BACKWARD_TEST_BINARY_DIR STREQUAL "" OR BACKWARD_TEST_BINARY_DIR STREQUAL "/")
	message(FATAL_ERROR "run_tests.cmake: refusing to use '${BACKWARD_TEST_BINARY_DIR}' as the test build directory")
endif()

# BACKWARD_MULTI_CONFIG is passed by CTest as 0 or 1 from $<BOOL:...>.
if(NOT DEFINED BACKWARD_MULTI_CONFIG)
	set(BACKWARD_MULTI_CONFIG FALSE)
endif()

file(REMOVE_RECURSE "${BACKWARD_TEST_BINARY_DIR}")
file(MAKE_DIRECTORY "${BACKWARD_TEST_BINARY_DIR}")

if(BACKWARD_PLATFORM STREQUAL "windows")
	set(_minimal_unwinder dbghelp)
	set(_minimal_symbolizer pdb)
	set(_ordered_unwinder "dbghelp")
	set(_ordered_unwinder_expected dbghelp)
	set(_fallback_unwinder "libunwind,dbghelp")
	set(_fallback_unwinder_expected dbghelp)
	set(_fallback_symbolizer "dw,pdb")
	set(_fallback_symbolizer_expected pdb)
	set(_foreign_symbolizer dw)
else()
	set(_minimal_unwinder unwind)
	set(_minimal_symbolizer backtrace-symbol)
	set(_ordered_unwinder "backtrace,unwind")
	set(_ordered_unwinder_expected backtrace)
	set(_fallback_unwinder "dbghelp,backtrace")
	set(_fallback_unwinder_expected backtrace)
	set(_fallback_symbolizer "pdb,backtrace-symbol")
	set(_fallback_symbolizer_expected backtrace-symbol)
	set(_foreign_symbolizer pdb)
endif()

set(_program_ok "frames=[1-9]")

function(run_case name)
	cmake_parse_arguments(CASE "EXPECT_FAIL;NO_MANUAL" "EXPECT;PROGRAM" "" ${ARGN})
	if(NOT CASE_EXPECT)
		message(FATAL_ERROR "run_case(${name}): EXPECT is required")
	endif()

	set(case_bin "${BACKWARD_TEST_BINARY_DIR}/${name}")
	set(configure_command
		"${CMAKE_COMMAND}"
		-S "${BACKWARD_TEST_SOURCE_DIR}"
		-B "${case_bin}"
		-G "${BACKWARD_GENERATOR}"
		"-DBACKWARD_SOURCE_DIR=${BACKWARD_SOURCE_DIR}"
		"-DBACKWARD_TESTS=OFF"
		"-DBACKWARD_INSTALL=OFF"
		"-DCMAKE_CXX_COMPILER=${BACKWARD_CXX_COMPILER}"
		${CASE_UNPARSED_ARGUMENTS})

	if(DEFINED BACKWARD_BUILD_TYPE AND NOT BACKWARD_BUILD_TYPE STREQUAL "")
		list(APPEND configure_command "-DCMAKE_BUILD_TYPE=${BACKWARD_BUILD_TYPE}")
	endif()
	if(DEFINED BACKWARD_TOOLCHAIN_FILE AND NOT BACKWARD_TOOLCHAIN_FILE STREQUAL "")
		list(APPEND configure_command "-DCMAKE_TOOLCHAIN_FILE=${BACKWARD_TOOLCHAIN_FILE}")
	endif()
	if(DEFINED BACKWARD_MAKE_PROGRAM AND NOT BACKWARD_MAKE_PROGRAM STREQUAL "")
		list(APPEND configure_command "-DCMAKE_MAKE_PROGRAM=${BACKWARD_MAKE_PROGRAM}")
	endif()

	execute_process(COMMAND ${configure_command}
		RESULT_VARIABLE configure_result
		OUTPUT_VARIABLE configure_output
		ERROR_VARIABLE configure_error)
	set(output "${configure_output}\n${configure_error}")

	if(CASE_EXPECT_FAIL)
		if(configure_result EQUAL 0)
			message(FATAL_ERROR "[${name}] configuration succeeded but should have failed.\n${output}")
		endif()
		if(NOT output MATCHES "${CASE_EXPECT}")
			message(FATAL_ERROR
				"[${name}] configuration failed without the expected message '${CASE_EXPECT}'.\n${output}")
		endif()
		message(STATUS "[PASS] ${name}: rejected as expected")
		return()
	endif()

	if(NOT configure_result EQUAL 0)
		message(FATAL_ERROR "[${name}] configuration failed.\n${output}")
	endif()
	if(NOT output MATCHES "${CASE_EXPECT}")
		message(FATAL_ERROR
			"[${name}] expected '${CASE_EXPECT}' in the configure output.\n${output}")
	endif()

	set(build_command "${CMAKE_COMMAND}" --build "${case_bin}")
	if(BACKWARD_MULTI_CONFIG)
		list(APPEND build_command --config "${BACKWARD_BUILD_CONFIG}")
	endif()
	execute_process(COMMAND ${build_command}
		RESULT_VARIABLE build_result
		OUTPUT_VARIABLE build_output
		ERROR_VARIABLE build_error)
	if(NOT build_result EQUAL 0)
		message(FATAL_ERROR
			"[${name}] build failed.\n${build_output}\n${build_error}")
	endif()

	set(exe_dir "${case_bin}")
	if(BACKWARD_MULTI_CONFIG)
		set(exe_dir "${case_bin}/${BACKWARD_BUILD_CONFIG}")
	endif()

	set(exe "${exe_dir}/backends${BACKWARD_EXE_SUFFIX}")
	execute_process(COMMAND "${exe}"
		RESULT_VARIABLE run_result
		OUTPUT_VARIABLE run_output
		ERROR_VARIABLE run_error)
	if(NOT run_result EQUAL 0)
		message(FATAL_ERROR
			"[${name}] ${exe} failed with ${run_result}.\n${run_output}\n${run_error}")
	endif()
	if(CASE_PROGRAM AND NOT run_output MATCHES "${CASE_PROGRAM}")
		message(FATAL_ERROR
			"[${name}] expected program output '${CASE_PROGRAM}', got:\n${run_output}")
	endif()

	if(NOT CASE_NO_MANUAL)
		set(manual_exe "${exe_dir}/backends_manual${BACKWARD_EXE_SUFFIX}")
		execute_process(COMMAND "${manual_exe}"
			RESULT_VARIABLE manual_result
			OUTPUT_VARIABLE manual_output
			ERROR_VARIABLE manual_error)
		if(NOT manual_result EQUAL 0 OR NOT manual_output MATCHES "${_program_ok}")
			message(FATAL_ERROR
				"[${name}] the header-only build did not behave as expected.\n"
				"result: ${manual_result}\n${manual_output}\n${manual_error}")
		endif()
	endif()

	message(STATUS "[PASS] ${name}: ${CASE_EXPECT}")
endfunction()

run_case(auto
	EXPECT "stack unwinder = (libunwind|unwind|backtrace|dbghelp)"
	PROGRAM "${_program_ok}")

run_case(minimal
	EXPECT "stack unwinder = ${_minimal_unwinder}"
	PROGRAM "${_program_ok}"
	-DBACKWARD_UNWINDER=${_minimal_unwinder}
	-DBACKWARD_SYMBOLIZER=${_minimal_symbolizer})

run_case(order_is_respected
	EXPECT "stack unwinder = ${_ordered_unwinder_expected}"
	PROGRAM "${_program_ok}"
	-DBACKWARD_UNWINDER=${_ordered_unwinder})

run_case(fallback
	EXPECT "stack unwinder = ${_fallback_unwinder_expected}"
	PROGRAM "${_program_ok}"
	-DBACKWARD_UNWINDER=${_fallback_unwinder})

run_case(fallback_symbolizer
	EXPECT "stack symbolizer = ${_fallback_symbolizer_expected}"
	PROGRAM "${_program_ok}"
	-DBACKWARD_SYMBOLIZER=${_fallback_symbolizer})

run_case(symbolizer_none
	EXPECT "stack symbolizer = none"
	PROGRAM "${_program_ok}"
	-DBACKWARD_SYMBOLIZER=NONE)

run_case(none
	EXPECT "stack walking and symbol resolution are disabled"
	PROGRAM "frames=0"
	NO_MANUAL
	-DBACKWARD_UNWINDER=NONE
	-DBACKWARD_SYMBOLIZER=NONE)

run_case(invalid_name
	EXPECT_FAIL
	EXPECT "is not a valid symbolizer backend"
	-DBACKWARD_SYMBOLIZER=not-a-backend)

run_case(unavailable
	EXPECT_FAIL
	EXPECT "none of the requested stack symbolizer backends is usable"
	-DBACKWARD_SYMBOLIZER=${_foreign_symbolizer})

run_case(empty
	EXPECT_FAIL
	EXPECT "is empty"
	-DBACKWARD_SYMBOLIZER=)

run_case(mixed_with_none
	EXPECT_FAIL
	EXPECT "cannot be combined"
	-DBACKWARD_SYMBOLIZER=none,bfd)

message(STATUS "All backward backend selection tests passed")
