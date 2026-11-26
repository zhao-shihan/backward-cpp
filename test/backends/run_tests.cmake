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

if(DEFINED BACKWARD_TEST_UNWINDERS)
	string(REPLACE "," ";" _test_unwinders "${BACKWARD_TEST_UNWINDERS}")
else()
	set(_test_unwinders "")
endif()
if(DEFINED BACKWARD_TEST_SYMBOLIZERS)
	string(REPLACE "," ";" _test_symbolizers "${BACKWARD_TEST_SYMBOLIZERS}")
else()
	set(_test_symbolizers "")
endif()

# A libdwarf header that declares the modern API is expected to work with the
# current backend. Fail before running the (slow) matrix, so a broken modern
# libdwarf cannot be mistaken for an old one.
if(BACKWARD_TEST_MODERN_LIBDWARF)
	list(FIND _test_symbolizers dwarf _dwarf_index)
	if(_dwarf_index EQUAL -1)
		message(FATAL_ERROR
			"libdwarf declares dwarf_siblingof_c, but the dwarf backend did not probe as usable")
	endif()
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
	set(_foreign_walker libunwind)
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
	set(_foreign_walker dbghelp)
endif()

string(TOUPPER "${_minimal_unwinder}" _minimal_unwinder_upper)

# On Linux every real symbolizer can name the current function. Requiring this
# catches a consumer that was built with backend definitions that do not match
# the backend CMake selected. The Windows/macOS matrix keeps the weaker check
# because their symbolizers may depend on debug information that is not present.
if(BACKWARD_PLATFORM STREQUAL "linux")
	set(_program_ok "frames=[1-9] function_present=1")
else()
	set(_program_ok "frames=[1-9]")
endif()
set(_program_no_frames "frames=0 function_present=0")
set(_program_no_function "frames=[1-9] function_present=0")

# Checks that the selection written for packaging systems matches the status
# lines shown to the user.
function(check_selection_file case_bin output)
	set(selection_file "${case_bin}/backward_selection.txt")
	# When Backward is a subproject, CMAKE_CURRENT_BINARY_DIR inside its
	# CMakeLists is the subdirectory build tree.
	if(NOT EXISTS "${selection_file}")
		set(selection_file "${case_bin}/backward/backward_selection.txt")
	endif()
	if(NOT EXISTS "${selection_file}")
		message(FATAL_ERROR "missing backward_selection.txt under ${case_bin}")
	endif()
	file(READ "${selection_file}" contents)

	set(expected_unwinder "none")
	set(expected_symbolizer "none")
	if(output MATCHES "stack unwinder = ([a-z-]+)")
		set(expected_unwinder "${CMAKE_MATCH_1}")
	endif()
	if(output MATCHES "stack symbolizer = ([a-z-]+)")
		set(expected_symbolizer "${CMAKE_MATCH_1}")
	endif()

	if(NOT contents MATCHES "unwinder=([a-z-]+)")
		message(FATAL_ERROR "selection file has no unwinder entry:\n${contents}")
	endif()
	set(file_unwinder "${CMAKE_MATCH_1}")
	if(NOT contents MATCHES "symbolizer=([a-z-]+)")
		message(FATAL_ERROR "selection file has no symbolizer entry:\n${contents}")
	endif()
	set(file_symbolizer "${CMAKE_MATCH_1}")

	if(NOT file_unwinder STREQUAL expected_unwinder)
		message(FATAL_ERROR
			"selection file says unwinder=${file_unwinder}, output says ${expected_unwinder}")
	endif()
	if(NOT file_symbolizer STREQUAL expected_symbolizer)
		message(FATAL_ERROR
			"selection file says symbolizer=${file_symbolizer}, output says ${expected_symbolizer}")
	endif()
	if(NOT contents MATCHES "libraries=")
		message(FATAL_ERROR "selection file has no libraries entry:\n${contents}")
	endif()
	if(NOT contents MATCHES "include_dirs=")
		message(FATAL_ERROR "selection file has no include_dirs entry:\n${contents}")
	endif()
	if(NOT contents MATCHES "library_dirs=")
		message(FATAL_ERROR "selection file has no library_dirs entry:\n${contents}")
	endif()
endfunction()

function(run_case name)
	cmake_parse_arguments(CASE "EXPECT_FAIL;NO_MANUAL" "EXPECT;EXPECT2;PROGRAM" "" ${ARGN})
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
	if(CASE_EXPECT2 AND NOT output MATCHES "${CASE_EXPECT2}")
		message(FATAL_ERROR
			"[${name}] expected '${CASE_EXPECT2}' in the configure output.\n${output}")
	endif()
	check_selection_file("${case_bin}" "${output}")

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

	# The consumer prints the macros it was compiled with. They must match the
	# selection that CMake reported, otherwise the exported definitions are wrong
	# even though the configure step looked fine.
	set(expected_walker "none")
	set(expected_symbolizer "none")
	if(output MATCHES "stack unwinder = ([a-z-]+)")
		set(expected_walker "${CMAKE_MATCH_1}")
	endif()
	if(output MATCHES "stack symbolizer = ([a-z-]+)")
		set(expected_symbolizer "${CMAKE_MATCH_1}")
	endif()
	if(NOT run_output MATCHES "walker=([a-z-]+) symbolizer=([a-z-]+)")
		message(FATAL_ERROR
			"[${name}] the consumer did not report its selected backends:\n${run_output}")
	endif()
	set(program_walker "${CMAKE_MATCH_1}")
	set(program_symbolizer "${CMAKE_MATCH_2}")
	if(NOT program_walker STREQUAL expected_walker)
		message(FATAL_ERROR
			"[${name}] consumer was built with walker=${program_walker}, but CMake selected ${expected_walker}")
	endif()
	if(NOT program_symbolizer STREQUAL expected_symbolizer)
		message(FATAL_ERROR
			"[${name}] consumer was built with symbolizer=${program_symbolizer}, but CMake selected ${expected_symbolizer}")
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

	message(STATUS "[PASS] ${name}")
endfunction()

run_case(auto
	EXPECT "stack unwinder = (libunwind|unwind|backtrace|dbghelp)"
	PROGRAM "${_program_ok}")

# Forcing the pair chosen by AUTO verifies that the exported definitions and the
# explicit selection agree with each other.
if(DEFINED BACKWARD_SELECTED_UNWINDER AND DEFINED BACKWARD_SELECTED_SYMBOLIZER
		AND NOT BACKWARD_SELECTED_UNWINDER STREQUAL "none"
		AND NOT BACKWARD_SELECTED_SYMBOLIZER STREQUAL "none")
	run_case(explicit_selected
		EXPECT "stack unwinder = ${BACKWARD_SELECTED_UNWINDER}"
		EXPECT2 "stack symbolizer = ${BACKWARD_SELECTED_SYMBOLIZER}"
		PROGRAM "${_program_ok}"
		-DBACKWARD_UNWINDER=${BACKWARD_SELECTED_UNWINDER}
		-DBACKWARD_SYMBOLIZER=${BACKWARD_SELECTED_SYMBOLIZER})
endif()

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
	PROGRAM "${_program_no_function}"
	-DBACKWARD_SYMBOLIZER=NONE)

run_case(walker_none
	EXPECT "stack unwinder = none"
	PROGRAM "${_program_no_frames}"
	NO_MANUAL
	-DBACKWARD_UNWINDER=NONE)

# Backend names are case insensitive and NONE may be spelled in lower case.
run_case(case_insensitive
	EXPECT "stack unwinder = ${_minimal_unwinder}"
	EXPECT2 "stack symbolizer = none"
	PROGRAM "${_program_no_function}"
	-DBACKWARD_UNWINDER=${_minimal_unwinder_upper}
	-DBACKWARD_SYMBOLIZER=none)

# Empty entries and duplicates are skipped instead of rejected.
run_case(tolerant_list
	EXPECT "stack unwinder = ${_minimal_unwinder}"
	PROGRAM "${_program_ok}"
	-DBACKWARD_UNWINDER=,${_minimal_unwinder},${_minimal_unwinder},)

# A trailing separator must not turn a single keyword into a mixed list.
run_case(trailing_none
	EXPECT "stack symbolizer = none"
	PROGRAM "${_program_no_function}"
	-DBACKWARD_SYMBOLIZER=NONE,)

run_case(trailing_auto
	EXPECT "stack unwinder = (libunwind|unwind|backtrace|dbghelp)"
	PROGRAM "${_program_ok}"
	-DBACKWARD_UNWINDER=AUTO,)

# Spaces around comma-separated entries are ignored.
run_case(whitespace_comma
	EXPECT "stack unwinder = ${_fallback_unwinder_expected}"
	PROGRAM "${_program_ok}"
	"-DBACKWARD_UNWINDER= ${_fallback_unwinder} ")

# A backend that is installed but does not compile with backward must be
# skipped, and the next candidate must take over. The probe cache is preseeded
# so the test does not depend on libbfd being installed.
if(NOT BACKWARD_PLATFORM STREQUAL "windows")
	run_case(probe_failure
		EXPECT "stack symbolizer = backtrace-symbol"
		PROGRAM "${_program_ok}"
		-DBACKWARD_SYMBOLIZER=bfd,backtrace-symbol
		-DBACKWARD_PROBE_SYMBOLIZER_BFD=0)
endif()

# Exercise every optional backend that the outer build found usable. The other
# dimension uses a built-in backend so each case isolates one backend.
foreach(backend IN LISTS _test_unwinders)
	run_case(walker_${backend}
		EXPECT "stack unwinder = ${backend}"
		PROGRAM "${_program_ok}"
		-DBACKWARD_UNWINDER=${backend}
		-DBACKWARD_SYMBOLIZER=${_minimal_symbolizer})
endforeach()
foreach(backend IN LISTS _test_symbolizers)
	run_case(symbolizer_${backend}
		EXPECT "stack symbolizer = ${backend}"
		PROGRAM "${_program_ok}"
		-DBACKWARD_UNWINDER=${_minimal_unwinder}
		-DBACKWARD_SYMBOLIZER=${backend})
endforeach()

run_case(none
	EXPECT "stack walking and symbol resolution are disabled"
	PROGRAM "${_program_no_frames}"
	NO_MANUAL
	-DBACKWARD_UNWINDER=NONE
	-DBACKWARD_SYMBOLIZER=NONE)

run_case(invalid_name
	EXPECT_FAIL
	EXPECT "is not a valid symbolizer backend"
	-DBACKWARD_SYMBOLIZER=not-a-backend)

run_case(invalid_walker
	EXPECT_FAIL
	EXPECT "is not a valid walker backend"
	-DBACKWARD_UNWINDER=not-a-walker)

run_case(unavailable
	EXPECT_FAIL
	EXPECT "none of the requested stack symbolizer backends is usable"
	-DBACKWARD_SYMBOLIZER=${_foreign_symbolizer})

run_case(unavailable_walker
	EXPECT_FAIL
	EXPECT "none of the requested stack walker backends is usable"
	-DBACKWARD_UNWINDER=${_foreign_walker})

run_case(empty
	EXPECT_FAIL
	EXPECT "is empty"
	-DBACKWARD_SYMBOLIZER=)

run_case(mixed_with_none
	EXPECT_FAIL
	EXPECT "cannot be combined"
	-DBACKWARD_SYMBOLIZER=none,bfd)

run_case(mixed_with_auto
	EXPECT_FAIL
	EXPECT "cannot be combined"
	-DBACKWARD_UNWINDER=auto,unwind)

# The header rejects invalid combinations even without CMake. This only uses
# GNU/Clang style flags, so the MSVC and clang-cl builds skip it.
if(NOT BACKWARD_PLATFORM STREQUAL "windows"
		AND DEFINED BACKWARD_COMPILER_ID
		AND BACKWARD_COMPILER_ID MATCHES "^(GNU|Clang|AppleClang)$")
	function(expect_compile_failure name expected)
		set(command
			"${BACKWARD_CXX_COMPILER}"
			-std=c++11
			"-I${BACKWARD_SOURCE_DIR}"
			-fsyntax-only
			${ARGN}
			"${BACKWARD_SOURCE_DIR}/backward.cpp")
		execute_process(COMMAND ${command}
			RESULT_VARIABLE result
			OUTPUT_VARIABLE output
			ERROR_VARIABLE error)
		set(output "${output}\n${error}")
		if(result EQUAL 0)
			message(FATAL_ERROR "[${name}] compilation succeeded but should have failed.\n${output}")
		endif()
		if(NOT output MATCHES "${expected}")
			message(FATAL_ERROR "[${name}] expected '${expected}' in the compiler output.\n${output}")
		endif()
		message(STATUS "[PASS] ${name}: rejected")
	endfunction()

	expect_compile_failure(multiple_walkers
		"select at most one BACKWARD_WALKER"
		-DBACKWARD_WALKER_UNWIND
		-DBACKWARD_WALKER_BACKTRACE)
	expect_compile_failure(multiple_symbolizers
		"select at most one BACKWARD_SYMBOLIZER"
		-DBACKWARD_SYMBOLIZER_DW
		-DBACKWARD_SYMBOLIZER_BFD)
	if(BACKWARD_PLATFORM STREQUAL "linux")
		expect_compile_failure(pdb_on_linux
			"only available on Windows"
			-DBACKWARD_SYMBOLIZER_PDB)
		expect_compile_failure(dbghelp_on_linux
			"only available on Windows"
			-DBACKWARD_WALKER_DBGHELP)
	elseif(BACKWARD_PLATFORM STREQUAL "darwin")
		expect_compile_failure(dw_on_macos
			"not available on macOS"
			-DBACKWARD_SYMBOLIZER_DW)
	endif()
else()
	message(STATUS "Skipping header validation tests for '${BACKWARD_COMPILER_ID}' on '${BACKWARD_PLATFORM}'")
endif()

message(STATUS "All backward backend selection tests passed")
