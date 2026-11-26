#
# BackwardDependencies.cmake
#
# Resolves Backward's optional external dependencies. This file is included by
# the build when Backward is built from source; it is not used by the installed
# package, whose exported targets already contain the selection.
#
# Each of the two independent capabilities (walking the stack and resolving
# symbols) is configured as an ordered preference list:
#
#   AUTO   Use the platform's recommended order, most capable backend first.
#   NONE   Do not use any backend for this capability.
#   <list> Try the listed backends from left to right; the first one that is
#          actually usable wins. Unknown names are configuration errors, and
#          an exhausted list is a configuration error as well.
#
# "Usable" means more than "the headers and the library exist": backward.hpp is
# compiled and linked once with the candidate backend. This keeps an installed
# but API-incompatible library (for example a libdwarf that changed its API) out
# of the build and lets the next candidate take over.

include_guard(GLOBAL)

set(_BACKWARD_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/..")
get_filename_component(_BACKWARD_SOURCE_DIR "${_BACKWARD_SOURCE_DIR}" ABSOLUTE)
set(_BACKWARD_HEADER "${_BACKWARD_SOURCE_DIR}/backward.hpp")
if(NOT EXISTS "${_BACKWARD_HEADER}")
	message(FATAL_ERROR
		"Backward: backward.hpp was not found at ${_BACKWARD_HEADER}")
endif()

###############################################################################
# PLATFORM AND CATALOG
###############################################################################

if(WIN32)
	set(_BACKWARD_PLATFORM windows)
elseif(APPLE)
	set(_BACKWARD_PLATFORM darwin)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "Android")
	set(_BACKWARD_PLATFORM linux)
else()
	set(_BACKWARD_PLATFORM unknown)
endif()

set(_BACKWARD_WALKERS libunwind unwind backtrace dbghelp)
set(_BACKWARD_SYMBOLIZERS dw bfd dwarf backtrace-symbol pdb)

if(_BACKWARD_PLATFORM STREQUAL "windows")
	set(_BACKWARD_WALKER_AUTO dbghelp)
	set(_BACKWARD_SYMBOLIZER_AUTO pdb)
elseif(_BACKWARD_PLATFORM STREQUAL "darwin")
	set(_BACKWARD_WALKER_AUTO libunwind unwind backtrace)
	set(_BACKWARD_SYMBOLIZER_AUTO backtrace-symbol)
elseif(_BACKWARD_PLATFORM STREQUAL "linux")
	set(_BACKWARD_WALKER_AUTO libunwind unwind backtrace)
	set(_BACKWARD_SYMBOLIZER_AUTO dw bfd dwarf backtrace-symbol)
else()
	set(_BACKWARD_WALKER_AUTO "")
	set(_BACKWARD_SYMBOLIZER_AUTO "")
endif()

set(BACKWARD_UNWINDER "AUTO" CACHE STRING
	"Library used to walk the stack: AUTO, NONE, or a ';'-separated preference list of libunwind, unwind, backtrace, dbghelp")
set_property(CACHE BACKWARD_UNWINDER PROPERTY STRINGS
	AUTO NONE libunwind unwind backtrace dbghelp)

set(BACKWARD_SYMBOLIZER "AUTO" CACHE STRING
	"Library used to resolve symbols: AUTO, NONE, or a ';'-separated preference list of dw, bfd, dwarf, backtrace-symbol, pdb")
set_property(CACHE BACKWARD_SYMBOLIZER PROPERTY STRINGS
	AUTO NONE dw bfd dwarf backtrace-symbol pdb)

###############################################################################
# DISCOVERY
###############################################################################

# Returns the macro suffix for a backend name: bfd -> BFD, backtrace-symbol ->
# BACKTRACE_SYMBOL.
function(_backward_backend_id backend out)
	string(TOUPPER "${backend}" id)
	string(REPLACE "-" "_" id "${id}")
	set(${out} "${id}" PARENT_SCOPE)
endfunction()

# Checks that a backend exists on this platform and finds its headers and
# libraries. This does not compile anything yet; see _backward_probe_backend().
function(_backward_find_backend kind backend out_found out_includes out_libraries out_reason)
	set(found FALSE)
	set(includes "")
	set(libraries "")
	set(reason "")

	if(_BACKWARD_PLATFORM STREQUAL "unknown")
		set(${out_found} FALSE PARENT_SCOPE)
		set(${out_includes} "" PARENT_SCOPE)
		set(${out_libraries} "" PARENT_SCOPE)
		set(${out_reason} "Backward does not support this platform" PARENT_SCOPE)
		return()
	endif()

	if(kind STREQUAL "WALKER")
		if(backend STREQUAL "dbghelp" AND NOT WIN32)
			set(reason "this stack walker is only available on Windows")
		elseif(backend MATCHES "^(libunwind|unwind|backtrace)$" AND WIN32)
			set(reason "this stack walker is not available on Windows")
		endif()
	else()
		if(backend STREQUAL "pdb" AND NOT WIN32)
			set(reason "the PDB symbolizer is only available on Windows")
		elseif(backend MATCHES "^(dw|bfd|dwarf)$" AND NOT _BACKWARD_PLATFORM STREQUAL "linux")
			set(reason "this symbolizer is only available on Linux")
		elseif(backend STREQUAL "backtrace-symbol" AND NOT _BACKWARD_PLATFORM MATCHES "^(linux|darwin)$")
			set(reason "backtrace_symbols is not available on this platform")
		endif()
	endif()

	if(NOT reason STREQUAL "")
		set(${out_found} FALSE PARENT_SCOPE)
		set(${out_includes} "" PARENT_SCOPE)
		set(${out_libraries} "" PARENT_SCOPE)
		set(${out_reason} "${reason}" PARENT_SCOPE)
		return()
	endif()

	if(backend STREQUAL "libunwind")
		if(APPLE)
			# libunwind is part of the system on macOS.
			set(found TRUE)
		else()
			find_path(LIBUNWIND_INCLUDE_DIR NAMES libunwind.h)
			find_library(LIBUNWIND_LIBRARY NAMES unwind)
			mark_as_advanced(LIBUNWIND_INCLUDE_DIR LIBUNWIND_LIBRARY)
			if(LIBUNWIND_INCLUDE_DIR AND LIBUNWIND_LIBRARY)
				set(found TRUE)
				set(includes "${LIBUNWIND_INCLUDE_DIR}")
				set(libraries "${LIBUNWIND_LIBRARY}")
			else()
				set(reason "libunwind.h or the libunwind library was not found")
			endif()
		endif()
	elseif(backend STREQUAL "unwind" OR backend STREQUAL "backtrace")
		# Provided by the C++ runtime or the C library; the probe decides.
		set(found TRUE)
	elseif(backend STREQUAL "dw")
		find_path(LIBDW_INCLUDE_DIR NAMES elfutils/libdw.h elfutils/libdwfl.h)
		find_library(LIBDW_LIBRARY dw)
		if(LIBDW_INCLUDE_DIR AND LIBDW_LIBRARY)
			set(found TRUE)
			set(includes "${LIBDW_INCLUDE_DIR}")
			set(libraries "${LIBDW_LIBRARY}")
			get_filename_component(_backward_dw_ext "${LIBDW_LIBRARY}" EXT)
			if(_backward_dw_ext STREQUAL "${CMAKE_STATIC_LIBRARY_SUFFIX}")
				# A static libdw needs all of these.
				find_library(LIBELF_LIBRARY elf)
				find_library(LIBPTHREAD_LIBRARY pthread)
				find_library(LIBZ_LIBRARY z)
				find_library(LIBBZ2_LIBRARY bz2)
				find_library(LIBLZMA_LIBRARY lzma)
				find_library(LIBZSTD_LIBRARY zstd)
				foreach(_backward_lib
						LIBELF_LIBRARY LIBPTHREAD_LIBRARY LIBZ_LIBRARY LIBBZ2_LIBRARY
						LIBLZMA_LIBRARY LIBZSTD_LIBRARY)
					if(${_backward_lib})
						list(APPEND libraries "${${_backward_lib}}")
					endif()
				endforeach()
				mark_as_advanced(LIBELF_LIBRARY LIBPTHREAD_LIBRARY LIBZ_LIBRARY
					LIBBZ2_LIBRARY LIBLZMA_LIBRARY LIBZSTD_LIBRARY)
			endif()
		else()
			set(reason "elfutils/libdw.h or the libdw library was not found")
		endif()
	elseif(backend STREQUAL "bfd")
		find_path(LIBBFD_INCLUDE_DIR NAMES bfd.h)
		find_library(LIBBFD_LIBRARY bfd)
		if(LIBBFD_INCLUDE_DIR AND LIBBFD_LIBRARY)
			set(found TRUE)
			set(includes "${LIBBFD_INCLUDE_DIR}")
			set(libraries "${LIBBFD_LIBRARY}" ${CMAKE_DL_LIBS})
			get_filename_component(_backward_bfd_ext "${LIBBFD_LIBRARY}" EXT)
			if(_backward_bfd_ext STREQUAL "${CMAKE_STATIC_LIBRARY_SUFFIX}")
				# A static libbfd needs its own dependencies.
				find_library(LIBSFRAME_LIBRARY sframe)
				if(LIBSFRAME_LIBRARY)
					list(APPEND libraries "${LIBSFRAME_LIBRARY}")
				endif()
				list(APPEND libraries iberty z)
				mark_as_advanced(LIBSFRAME_LIBRARY)
			endif()
			mark_as_advanced(LIBBFD_INCLUDE_DIR LIBBFD_LIBRARY)
		else()
			set(reason "bfd.h or the libbfd library was not found")
		endif()
	elseif(backend STREQUAL "dwarf")
		find_path(LIBDWARF_INCLUDE_DIR NAMES libdwarf.h PATH_SUFFIXES libdwarf libdwarf-0)
		find_path(LIBELF_INCLUDE_DIR NAMES libelf.h)
		find_library(LIBDWARF_LIBRARY dwarf)
		find_library(LIBELF_LIBRARY elf)
		if(LIBDWARF_INCLUDE_DIR AND LIBELF_INCLUDE_DIR AND LIBDWARF_LIBRARY AND LIBELF_LIBRARY)
			set(found TRUE)
			set(includes "${LIBDWARF_INCLUDE_DIR}" "${LIBELF_INCLUDE_DIR}")
			set(libraries "${LIBDWARF_LIBRARY}" "${LIBELF_LIBRARY}" ${CMAKE_DL_LIBS})
			mark_as_advanced(LIBDWARF_INCLUDE_DIR LIBDWARF_LIBRARY
				LIBELF_INCLUDE_DIR LIBELF_LIBRARY)
		else()
			set(reason "libdwarf.h/libelf.h or the libdwarf/libelf libraries were not found")
		endif()
	elseif(backend STREQUAL "backtrace-symbol")
		set(found TRUE)
	elseif(backend STREQUAL "dbghelp" OR backend STREQUAL "pdb")
		set(found TRUE)
		set(libraries dbghelp psapi)
	endif()

	set(${out_found} ${found} PARENT_SCOPE)
	set(${out_includes} "${includes}" PARENT_SCOPE)
	set(${out_libraries} "${libraries}" PARENT_SCOPE)
	set(${out_reason} "${reason}" PARENT_SCOPE)
endfunction()

# Compiles and links backward.hpp with the backend selected. The result is
# cached by check_cxx_source_compiles(), so reconfiguring is cheap. A user who
# knows better can preseed the cache variable.
function(_backward_probe_backend kind id includes libraries out)
	string(TOUPPER "${kind}" kind_upper)
	set(probe_var "BACKWARD_PROBE_${kind_upper}_${id}")
	if(DEFINED ${probe_var})
		set(${out} ${${probe_var}} PARENT_SCOPE)
		return()
	endif()

	include(CMakePushCheckState)
	include(CheckCXXSourceCompiles)
	cmake_push_check_state(RESET)
	set(CMAKE_REQUIRED_INCLUDES "${includes}" "${_BACKWARD_SOURCE_DIR}")
	set(CMAKE_REQUIRED_LIBRARIES "${libraries}")
	# Disable the other capability so that this probe tests exactly one backend,
	# and include backward.cpp so that SignalHandling is checked as well.
	if(kind STREQUAL "WALKER")
		set(_backward_other_category "BACKWARD_SYMBOLIZER_NONE")
	else()
		set(_backward_other_category "BACKWARD_WALKER_NONE")
	endif()
	check_cxx_source_compiles("
#define ${_backward_other_category}
#define BACKWARD_${kind_upper}_${id}
#include \"${_BACKWARD_SOURCE_DIR}/backward.cpp\"
int main() {
	backward::StackTrace stack_trace;
	stack_trace.load_here(4);
	backward::TraceResolver resolver;
	resolver.load_stacktrace(stack_trace);
	backward::ResolvedTrace trace;
	if (stack_trace.size() > 0) {
		trace = resolver.resolve(stack_trace[0]);
	} else {
		trace = resolver.resolve(trace);
	}
	(void)trace;
	return 0;
}" ${probe_var})
	cmake_pop_check_state()
	set(${out} ${${probe_var}} PARENT_SCOPE)
endfunction()

# Walks a preference list and returns the first usable backend. On failure,
# failures contains one human readable line per candidate.
function(_backward_pick kind candidates out_selected out_includes out_libraries out_failures)
	set(selected "")
	set(includes "")
	set(libraries "")
	set(failures "")

	foreach(backend IN LISTS candidates)
		_backward_backend_id("${backend}" id)
		_backward_find_backend(${kind} "${backend}" found incs libs reason)
		if(NOT found)
			list(APPEND failures "${backend}: ${reason}")
			continue()
		endif()
		_backward_probe_backend(${kind} ${id} "${incs}" "${libs}" usable)
		if(usable)
			set(selected "${backend}")
			set(includes "${incs}")
			set(libraries "${libs}")
			break()
		endif()
		message(STATUS "Backward: skipping ${backend}: it is installed, but backward does not compile and link with it")
		list(APPEND failures "${backend}: installed, but backward does not compile and link with it")
	endforeach()

	set(${out_selected} "${selected}" PARENT_SCOPE)
	set(${out_includes} "${includes}" PARENT_SCOPE)
	set(${out_libraries} "${libraries}" PARENT_SCOPE)
	set(${out_failures} "${failures}" PARENT_SCOPE)
endfunction()

###############################################################################
# SELECTION
###############################################################################

function(_backward_resolve kind valid_names auto_order option_value)
	string(TOLOWER "${kind}" kind_lower)
	string(TOUPPER "${kind}" kind_upper)

	string(STRIP "${option_value}" option_value)
	string(TOUPPER "${option_value}" value_upper)
	if(value_upper STREQUAL "NONE")
		set(selected "none")
		set(includes "")
		set(libraries "")
	elseif(value_upper STREQUAL "AUTO")
		_backward_pick(${kind_upper} "${auto_order}" selected includes libraries failures)
		if(selected STREQUAL "")
			if(auto_order STREQUAL "")
				set(selected "none")
			else()
				string(REPLACE ";" "\n  " failures_text "${failures}")
				message(FATAL_ERROR
					"Backward: no usable stack ${kind_lower} was found on this system.\n"
					"Tried:\n  ${failures_text}\n"
					"Set BACKWARD_${kind_upper} to a preference list, or to NONE to disable it.")
			endif()
		endif()
	else()
		string(REPLACE "," ";" option_value "${option_value}")
		set(candidates "")
		foreach(entry IN LISTS option_value)
			string(STRIP "${entry}" entry)
			string(TOLOWER "${entry}" entry)
			if(entry STREQUAL "")
				continue()
			endif()
			if(entry STREQUAL "auto" OR entry STREQUAL "none")
				message(FATAL_ERROR
					"Backward: \"${entry}\" cannot be combined with other backends in BACKWARD_${kind_upper}.")
			endif()
			list(FIND valid_names "${entry}" index)
			if(index EQUAL -1)
				message(FATAL_ERROR
					"Backward: \"${entry}\" is not a valid ${kind_lower} backend for BACKWARD_${kind_upper}.\n"
					"Valid names are: ${valid_names}")
			endif()
			list(APPEND candidates "${entry}")
		endforeach()
		if(candidates STREQUAL "")
			message(FATAL_ERROR
				"Backward: BACKWARD_${kind_upper} is empty. Set it to AUTO, NONE, or a list of ${valid_names}.")
		endif()
		_backward_pick(${kind_upper} "${candidates}" selected includes libraries failures)
		if(selected STREQUAL "")
			string(REPLACE ";" "\n  " failures_text "${failures}")
			message(FATAL_ERROR
				"Backward: none of the requested stack ${kind_lower} backends is usable.\n"
				"Tried:\n  ${failures_text}")
		endif()
	endif()

	set(_BACKWARD_${kind_upper}_SELECTED "${selected}" PARENT_SCOPE)
	set(_BACKWARD_${kind_upper}_INCLUDE_DIRS "${includes}" PARENT_SCOPE)
	set(_BACKWARD_${kind_upper}_LIBRARIES "${libraries}" PARENT_SCOPE)
endfunction()

_backward_resolve(WALKER "${_BACKWARD_WALKERS}" "${_BACKWARD_WALKER_AUTO}" "${BACKWARD_UNWINDER}")
_backward_resolve(SYMBOLIZER "${_BACKWARD_SYMBOLIZERS}" "${_BACKWARD_SYMBOLIZER_AUTO}" "${BACKWARD_SYMBOLIZER}")

set(BACKWARD_SELECTED_UNWINDER "${_BACKWARD_WALKER_SELECTED}")
set(BACKWARD_SELECTED_SYMBOLIZER "${_BACKWARD_SYMBOLIZER_SELECTED}")

###############################################################################
# RESULTS
###############################################################################

set(BACKWARD_DEFINITIONS "")
set(BACKWARD_INCLUDE_DIRS "")
set(BACKWARD_LIBRARIES "")

foreach(_backward_kind WALKER SYMBOLIZER)
	if(_BACKWARD_${_backward_kind}_SELECTED STREQUAL "none")
		list(APPEND BACKWARD_DEFINITIONS "BACKWARD_${_backward_kind}_NONE")
	else()
		_backward_backend_id("${_BACKWARD_${_backward_kind}_SELECTED}" _backward_id)
		list(APPEND BACKWARD_DEFINITIONS "BACKWARD_${_backward_kind}_${_backward_id}")
		list(APPEND BACKWARD_INCLUDE_DIRS ${_BACKWARD_${_backward_kind}_INCLUDE_DIRS})
		list(APPEND BACKWARD_LIBRARIES ${_BACKWARD_${_backward_kind}_LIBRARIES})
	endif()
endforeach()

set(BACKWARD_RESOLVED_LIBUNWIND_SIGNAL_FRAME 0)
if(BACKWARD_SELECTED_UNWINDER STREQUAL "libunwind")
	include(CMakePushCheckState)
	include(CheckCXXSourceCompiles)
	cmake_push_check_state(RESET)
	set(CMAKE_REQUIRED_INCLUDES ${_BACKWARD_WALKER_INCLUDE_DIRS})
	set(CMAKE_REQUIRED_LIBRARIES ${_BACKWARD_WALKER_LIBRARIES})
	check_cxx_source_compiles("
#define UNW_LOCAL_ONLY
#include <libunwind.h>
int main() {
	unw_context_t context;
	unw_cursor_t cursor;
	return unw_init_local2(&cursor, &context, UNW_INIT_SIGNAL_FRAME);
}" BACKWARD_PROBE_LIBUNWIND_SIGNAL_FRAME)
	cmake_pop_check_state()
	if(BACKWARD_PROBE_LIBUNWIND_SIGNAL_FRAME)
		set(BACKWARD_RESOLVED_LIBUNWIND_SIGNAL_FRAME 1)
		list(APPEND BACKWARD_DEFINITIONS "BACKWARD_LIBUNWIND_HAS_SIGNAL_FRAME=1")
	else()
		message(STATUS "Backward: libunwind cannot unwind from signal handler frames")
	endif()
endif()

# Windows needs extra compiler/linker flags for PDB debug information.
if(WIN32 AND NOT BACKWARD_SELECTED_SYMBOLIZER STREQUAL "none")
	if(MINGW)
		include(CheckCXXCompilerFlag)
		check_cxx_compiler_flag(-gcodeview SUPPORT_WINDOWS_DEBUG_INFO)
		if(SUPPORT_WINDOWS_DEBUG_INFO)
			set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--pdb=")
			add_compile_options(-gcodeview)
		else()
			set(MINGW_MSVCR_LIBRARY "msvcr90$<$<CONFIG:DEBUG>:d>"
				CACHE STRING "Mingw MSVC runtime import library")
			list(APPEND BACKWARD_LIBRARIES ${MINGW_MSVCR_LIBRARY})
		endif()
	endif()
endif()

list(REMOVE_DUPLICATES BACKWARD_LIBRARIES)
list(REMOVE_DUPLICATES BACKWARD_INCLUDE_DIRS)

if(NOT DEFINED CMAKE_INSTALL_INCLUDEDIR)
	set(CMAKE_INSTALL_INCLUDEDIR include)
endif()
list(INSERT BACKWARD_INCLUDE_DIRS 0
	"$<BUILD_INTERFACE:${_BACKWARD_SOURCE_DIR}>"
	"$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")

if(BACKWARD_SELECTED_UNWINDER STREQUAL "none" AND
		BACKWARD_SELECTED_SYMBOLIZER STREQUAL "none")
	message(STATUS "Backward: stack walking and symbol resolution are disabled")
else()
	message(STATUS "Backward: stack unwinder = ${BACKWARD_SELECTED_UNWINDER}")
	message(STATUS "Backward: stack symbolizer = ${BACKWARD_SELECTED_SYMBOLIZER}")
endif()

# Persist the selection for packaging systems that cannot consume the exported
# CMake targets (the Conan recipe, for example). This file is not installed.
set(BACKWARD_SELECTION_FILE "${CMAKE_CURRENT_BINARY_DIR}/backward_selection.txt")
file(WRITE "${BACKWARD_SELECTION_FILE}"
	"unwinder=${BACKWARD_SELECTED_UNWINDER}\n"
	"symbolizer=${BACKWARD_SELECTED_SYMBOLIZER}\n"
	"libunwind_signal_frame=${BACKWARD_RESOLVED_LIBUNWIND_SIGNAL_FRAME}\n"
	"libraries=${BACKWARD_LIBRARIES}\n")
