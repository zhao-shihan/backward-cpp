// Shared by the dependency-selection matrix tests. It prints the number of
// captured frames and, when a frame is available, the resolved function name.
// A NONE walker must produce "frames=0"; a NONE symbolizer is allowed to produce
// an empty function name but still has to capture frames.

#include <backward.hpp>
#include <cstdio>

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

  std::printf("frames=%zu\n", stack_trace.size());
  if (stack_trace.size() > 0) {
    backward::ResolvedTrace trace = resolver.resolve(stack_trace[0]);
    std::printf("function=%s\n", trace.object_function.c_str());
  }
}

int main() {
  capture();
  return 0;
}
