if (APPLE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -undefined suppress -flat_namespace")
endif(APPLE)

if (${CMAKE_SYSTEM_NAME} STREQUAL "Linux")
    # man 3 dlsym:
    #
    #  | The _GNU_SOURCE feature test macro must be defined in
    #  | order to obtain the definitions of RTLD_DEFAULT and
    #  | RTLD_NEXT from <dlfcn.h>.
    add_definitions("-D_GNU_SOURCE")
endif()

# Add C library
add_library(lib SHARED lib.c smtpc.c)

# We MUST NOT add the curl library here.
#
# Note: The problem is described from the user perspective in [1].
# The text below is the long explanation how it was solved.
#
# The reason why we must avoid dynamic linking with system's
# libcurl is composition of several facts.
#
# The module uses system's libcurl.so when libcurl symbols that
# are exported from tarantool executable are not suitable for the
# module, in particular:
#
# 1. There are tarantool releases that do not export libcurl
#    symbols at all.
# 2. There are tarantool releases that export partial list of
#    libcurl public symbols (due to default visibility and lack
#    of an explicit export list).
# 3. There are tarantool releases, which offer libcurl without
#    smtp(s) support.
#
# See the affected tarantool releases list in [2].
#
# Anyway, the module calls dlopen() with RTLD_DEEPBIND (see
# smtpc_init()) for loading system's libcurl.so and everything
# should be fine? Sadly, no...
#
# System's libcurl.so is usually built without
# -Wl,-Bsymbolic-functions (the exception is Ubuntu -- it
# surprisingly differs here from Debian) and dynamic relocations
# are generated for exported libcurl functions that libcurl calls
# from its code. Those calls are dynamic and an application can
# retarget them just by exporting the target function from its
# executable. A user may retarget those calls using LD_PRELOAD.
# This mechanism aims to provide a way to extend or change a
# shared library functionality.
#
# However at least some of such calls (from libcurl's code to a
# libcurl's exported function) are internal by its nature and,
# AFAIU, must land to the same libcurl.so version / build. The
# example I found is calling of curl_multi_add_handle() from the
# curl_easy_perform() implementation. It fails for me when
# system's libcurl.so (7.75.0 with smtp(s) support) processes an
# smtp request and calls curl_multi_add_handle() from tarantool
# 2.5.3 (libcurl 7.71.1 without smtp(s) support). The error is
# CURLE_FAILED_INIT.
#
# Back to the main question. What is going on if we'll add curl
# library to the NEEDED entry of the module's dynamic library
# (using `ld <...> -lcurl` or so)?
#
# Tarantool is loaded and calls require('smtp'), the module's
# lib.so library starts to load. The dynamic linker find the
# NEEDED entry with system's libcurl.so and loads it. The
# libcurl.so library has dynamic relocations and they are resolved
# to the executable's symbols. The module checks executable's
# symbols and, say, find them unsuitable. It loads libcurl.so using
# dlopen() that just increases a reference counter of already
# loaded library. The resolved dynamic relocations remain resolved
# to the executable and the RTLD_DEEPBIND flag does not affect
# them. Due to differences in versions / supported protocols (I
# don't know a presice reason) curl_easy_perform() from the loaded
# libcurl.so becomes broken and always returns CURLE_FAILED_INIT.
#
# What if we'll not add the curl library here?
#
# If we're lucky and system's libcurl.so is not loaded without
# RTLD_DEEPBIND yet, our dlopen() with RTLD_DEEPBIND will work
# as expected and all symbols from the library will be resolved
# to the library itself.
#
# Sure, if another module has system's libcurl.so in the NEEDED
# entry or loads it without RTLD_DEEPBIND and this another module
# is loaded prior to this one we again in the trouble.
#
# There are several facts that more or less mitigate the problem:
#
# 1. I don't know any other tarantool's module that uses libcurl
#    (except built-in http.client, which uses built-in libcurl,
#    and so irrelevant here).
# 2. Tarantool offers suitable libcurl implementation since
#    1.10.10, 2.6.3, 2.7.2, 2.8.1 and in all 2.9+. The module
#    uses the built-in libcurl when possible.
#
# [1]: https://github.com/tarantool/smtp/issues/29
# [2]: https://github.com/tarantool/smtp/issues/24
target_link_libraries(lib ${CMAKE_DL_LIBS})

set_target_properties(lib PROPERTIES PREFIX "" OUTPUT_NAME "lib")

# Install module
install(FILES init.lua version.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/${PROJECT_NAME}/)
install(TARGETS lib LIBRARY DESTINATION ${TARANTOOL_INSTALL_LIBDIR}/${PROJECT_NAME}/)
