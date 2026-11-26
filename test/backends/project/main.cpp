// Shared by the dependency-selection matrix tests. It prints the number of
// captured frames, whether the symbolizer produced a function name, and the name
// itself. A NONE walker must produce "frames=0"; a NONE symbolizer must keep
// "function_present=0"; real symbolizers normally resolve the current frame.

#include <backward.hpp>
#include <cstdio>
#include <string>

// These names come from the backend macros that Backward::Interface exports.
// Printing them verifies that the compile definitions used to build this
// consumer match the backend selection reported by CMake.
#if defined(BACKWARD_WALKER_LIBUNWIND)
#define BACKWARD_TEST_WALKER_NAME "libunwind"
#elif defined(BACKWARD_WALKER_UNWIND)
#define BACKWARD_TEST_WALKER_NAME "unwind"
#elif defined(BACKWARD_WALKER_BACKTRACE)
#define BACKWARD_TEST_WALKER_NAME "backtrace"
#elif defined(BACKWARD_WALKER_DBGHELP)
#define BACKWARD_TEST_WALKER_NAME "dbghelp"
#elif defined(BACKWARD_WALKER_NONE)
#define BACKWARD_TEST_WALKER_NAME "none"
#else
#define BACKWARD_TEST_WALKER_NAME "unknown"
#endif

#if defined(BACKWARD_SYMBOLIZER_DW)
#define BACKWARD_TEST_SYMBOLIZER_NAME "dw"
#elif defined(BACKWARD_SYMBOLIZER_BFD)
#define BACKWARD_TEST_SYMBOLIZER_NAME "bfd"
#elif defined(BACKWARD_SYMBOLIZER_DWARF)
#define BACKWARD_TEST_SYMBOLIZER_NAME "dwarf"
#elif defined(BACKWARD_SYMBOLIZER_BACKTRACE_SYMBOL)
#define BACKWARD_TEST_SYMBOLIZER_NAME "backtrace-symbol"
#elif defined(BACKWARD_SYMBOLIZER_PDB)
#define BACKWARD_TEST_SYMBOLIZER_NAME "pdb"
#elif defined(BACKWARD_SYMBOLIZER_NONE)
#define BACKWARD_TEST_SYMBOLIZER_NAME "none"
#else
#define BACKWARD_TEST_SYMBOLIZER_NAME "unknown"
#endif

#if defined(_MSC_VER)
#define BACKWARD_TEST_NOINLINE __declspec(noinline)
#else
#define BACKWARD_TEST_NOINLINE __attribute__((noinline))
#endif

BACKWARD_TEST_NOINLINE void capture() {
  backward::StackTrace stack_trace;
  stack_trace.load_here(8);
  backward::TraceResolver resolver;
  resolver.load_stacktrace(stack_trace);

  const size_t frames = stack_trace.size();
  int function_present = 0;
  std::string function;
  if (frames > 0) {
    backward::ResolvedTrace trace = resolver.resolve(stack_trace[0]);
    function = trace.object_function;
    function_present = function.empty() ? 0 : 1;
  }

  std::printf("walker=%s symbolizer=%s\n",
              BACKWARD_TEST_WALKER_NAME, BACKWARD_TEST_SYMBOLIZER_NAME);
  std::printf("frames=%zu function_present=%d\n", frames, function_present);
  if (frames > 0) {
    std::printf("function=%s\n", function.c_str());
  }
}

int main() {
  capture();
  return 0;
}
