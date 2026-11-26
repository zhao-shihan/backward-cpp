from conans import ConanFile, CMake
import os
import re

SELECTION_FILE = 'backward_selection.txt'


def read_selection(folder):
    """Reads the backend selection written by cmake/BackwardDependencies.cmake."""
    selection = {}
    if not folder:
        return selection
    path = os.path.join(folder, SELECTION_FILE)
    if not os.path.exists(path):
        return selection
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            key, _, value = line.strip().partition('=')
            if key:
                selection[key] = value
    return selection


def library_names(libraries):
    """Turns find_library() results into plain -l names for cpp_info."""
    names = []
    for library in libraries:
        library = library.strip()
        if not library or '$<' in library:
            continue
        name = os.path.basename(library)
        if name.startswith('lib'):
            name = name[3:]
        name = name.split('.')[0]
        if name and name not in names:
            names.append(name)
    return names


def selection_paths(selection, key):
    """Returns existing absolute paths from a selection file entry."""
    paths = []
    for path in selection.get(key, '').split(';'):
        path = path.strip()
        if path and '$<' not in path and os.path.isabs(path) and os.path.isdir(path):
            if path not in paths:
                paths.append(path)
    return paths


class BackwardCpp(ConanFile):
    settings = 'os', 'compiler', 'build_type', 'arch'
    name = 'backward'
    url = 'https://github.com/bombela/backward-cpp'
    license = 'MIT'
    options = {
        # Stack unwinder: 'AUTO', 'NONE', or a ';'-separated preference list
        # (libunwind, unwind, backtrace, dbghelp).
        'unwinder': 'ANY',
        # Symbolizer: 'AUTO', 'NONE', or a ';'-separated preference list
        # (dw, bfd, dwarf, backtrace-symbol, pdb).
        'symbolizer': 'ANY',
        'shared': [True, False]
    }
    default_options = (
        'unwinder=AUTO',
        'symbolizer=AUTO',
        'shared=False'
    )
    exports = 'backward.cpp', 'backward.hpp', 'test/*', 'cmake/*', 'CMakeLists.txt'
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
        cmake.configure(defs={
            'BACKWARD_UNWINDER': self.options.unwinder,
            'BACKWARD_SYMBOLIZER': self.options.symbolizer,
            'BACKWARD_SHARED': self.options.shared,
            'BACKWARD_TESTS': 'OFF',
        })
        cmake.build()

    def package(self):
        self.copy('backward.hpp', os.path.join('include', 'backward'))
        self.copy('*.a', dst='lib')
        self.copy('*.so', dst='lib')
        self.copy('*.lib', dst='lib')
        self.copy('*.dll', dst='lib')

        # Persist the resolved backends so that package_info() can give every
        # consumer the same compile definitions that the library was built with.
        selection = read_selection(self.build_folder)
        if selection:
            with open(os.path.join(self.package_folder, SELECTION_FILE), 'w',
                      encoding='utf-8') as handle:
                for key, value in sorted(selection.items()):
                    handle.write('%s=%s\n' % (key, value))

    def package_info(self):
        self.cpp_info.libs = ['backward']

        selection = read_selection(self.package_folder)
        for path in selection_paths(selection, 'include_dirs'):
            if path not in self.cpp_info.includedirs:
                self.cpp_info.includedirs.append(path)
        for path in selection_paths(selection, 'library_dirs'):
            if path not in self.cpp_info.libdirs:
                self.cpp_info.libdirs.append(path)

        defines = []
        for category, key in (('WALKER', 'unwinder'), ('SYMBOLIZER', 'symbolizer')):
            backend = selection.get(key, '')
            if backend == 'none':
                defines.append('BACKWARD_%s_NONE' % category)
            elif backend:
                defines.append('BACKWARD_%s_%s' %
                               (category, backend.upper().replace('-', '_')))
        if selection.get('libunwind_signal_frame') == '1':
            defines.append('BACKWARD_LIBUNWIND_HAS_SIGNAL_FRAME=1')
        self.cpp_info.defines = defines

        # The static library references the selected backend libraries, so
        # consumers have to link them too.
        libraries = selection.get('libraries', '')
        self.cpp_info.system_libs = library_names(libraries.split(';'))
