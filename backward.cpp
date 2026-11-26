// Backward can use optional external libraries for two independent jobs:
//
//   * walking the stack                  BACKWARD_WALKER_*
//   * resolving symbols and debug info   BACKWARD_SYMBOLIZER_*
//
// When Backward is built with CMake, both are selected automatically (see the
// BACKWARD_UNWINDER and BACKWARD_SYMBOLIZER options, and the README). The
// exported CMake targets carry the matching compile definitions and link
// libraries, so this file needs no #define at all in that case.
//
// Without CMake, define exactly one BACKWARD_WALKER_* macro and one
// BACKWARD_SYMBOLIZER_* macro here (or in your build system), and link the
// corresponding library. For example, on GNU/Linux:
//
//   apt-get install libdw-dev libunwind-dev
//   g++/clang++ -ldw -lunwind ...
//   #define BACKWARD_WALKER_LIBUNWIND
//   #define BACKWARD_SYMBOLIZER_DW
//
// Without any definition, backward uses the portable defaults that need no
// third-party link flags: the compiler's unwinder plus backtrace_symbols, or
// dbghelp/PDB on Windows.

#include "backward.hpp"

namespace backward {

backward::SignalHandling sh;

} // namespace backward
