from conans import ConanFile, CMake
import os
import re

class BackwardCpp(ConanFile):
    settings = 'os', 'compiler', 'build_type', 'arch'
    name = 'backward'
    url = 'https://github.com/bombela/backward-cpp'
    license = 'MIT'
    options = {
        'stack_walking_unwind': [True, False],
        'stack_walking_backtrace': [True, False],
        'stack_details_auto_detect': [True, False],
        'stack_details_backtrace_symbol': [True, False],
        'stack_details_dw': [True, False],
        'stack_details_bfd': [True, False],
        'shared': [True, False]
    }
    default_options = (
        'stack_walking_unwind=True',
        'stack_walking_backtrace=False',
        'stack_details_auto_detect=True',
        'stack_details_backtrace_symbol=False',
        'stack_details_dw=False',
        'stack_details_bfd=False',
        'shared=False'
    )
    exports = 'backward.cpp', 'backward.hpp', 'test/*', 'CMakeLists.txt', 'BackwardConfig.cmake'
    generators = 'cmake'

    def set_version(self):
        # Keep the version in one place: the CMake project declaration.
        cmake_lists = os.path.join(self.recipe_folder, 'CMakeLists.txt')
        with open(cmake_lists, encoding='utf-8') as handle:
            match = re.search(
                r'^\s*project\s*\(\s*backward\s+VERSION\s+([0-9]+(?:\.[0-9]+)*)',
                handle.read(),
                re.MULTILINE,
            )
        if match is None:
            raise ValueError('Could not read the version from CMakeLists.txt')
        self.version = match.group(1)

    def build(self):
        cmake = CMake(self)

        cmake.configure(defs={'BACKWARD_' + name.upper(): value for name, value in self.options.values.as_list()})
        cmake.build()

    def package(self):
        self.copy('backward.hpp', os.path.join('include', 'backward'))
        self.copy('*.a', dst='lib')
        self.copy('*.so', dst='lib')
        self.copy('*.lib', dst='lib')
        self.copy('*.dll', dst='lib')

    def package_info(self):
        self.cpp_info.libs = ['backward']
