// Shared by the dependency-selection matrix tests. It prints the number of
// captured frames, whether the symbolizer produced a function name, and the name
// itself. A NONE walker must produce "frames=0"; a NONE symbolizer must keep
// "function_present=0"; real symbolizers normally resolve the current frame.

#include <backward.hpp>
#include <cstdio>
#include <string>

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

  std::printf("frames=%zu function_present=%d\n", frames, function_present);
  if (frames > 0) {
    std::printf("function=%s\n", function.c_str());
  }
}

int main() {
  capture();
  return 0;
}
