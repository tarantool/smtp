cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(smtp C)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}" ${CMAKE_MODULE_PATH})

# Find Tarantool and Lua dependecies
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)

# Two directories are added into the header search paths:
#
# - ${TARANTOOL_DIR}${PREFIX}/include
# - ${TARANTOOL_DIR}${PREFIX}/include/tarantool
#
# So `#include <curl/curl.h>` will prefer libcurl headers shipped
# by tarantool packages if exists and will fallback to the system
# ones otherwise.
#
# (`-I <dir>` directories are scanned before system ones as for
# `#include "foo.h"` as well as for `#include <foo.h>`.)
include_directories(${TARANTOOL_INCLUDE_DIRS})

# Set CFLAGS
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu99")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Wall -Wextra")

# Build module
add_subdirectory(smtp)

enable_testing()

set (LUA_PATH "LUA_PATH=${PROJECT_SOURCE_DIR}/?.lua\\;${PROJECT_SOURCE_DIR}/?/init.lua\\;;")

add_test(smtp ${CMAKE_SOURCE_DIR}/test/smtp.test.lua)
set_tests_properties(smtp PROPERTIES ENVIRONMENT "${LUA_PATH}")

# Add `make check`
add_custom_target(check
    WORKING_DIRECTORY ${PROJECT_BUILD_DIR}
    COMMAND ctest -V)
