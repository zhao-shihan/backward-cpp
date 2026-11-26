// Consumer for the installed-package test. It must build against the header and
// the compile definitions exported by the installed Backward package.

#include <backward.hpp>
#include <cstdio>

// Check that the installed targets export the backend definitions that were
// baked in when the package was built.
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
  std::printf("walker=%s symbolizer=%s\n",
              BACKWARD_TEST_WALKER_NAME, BACKWARD_TEST_SYMBOLIZER_NAME);
  std::printf("frames=%zu\n", stack_trace.size());
}

#ifdef BACKWARD_TEST_USE_SIGNAL_HANDLING
static backward::SignalHandling &signal_handling() {
  static backward::SignalHandling instance;
  return instance;
}
#endif

int main() {
#ifdef BACKWARD_TEST_USE_SIGNAL_HANDLING
  (void)signal_handling();
#endif
  capture();
  return 0;
}
