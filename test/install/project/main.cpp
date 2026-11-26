// Consumer for the installed-package test. It must build against the header and
// the compile definitions exported by the installed Backward package.

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
}

int main() {
  capture();
  return 0;
}
