if (APPLE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -undefined suppress -flat_namespace")
endif(APPLE)

# Add C library
add_library(lib SHARED lib.c smtpc.c)

find_path(TARANTOOL_CURL_INCLUDE_DIR
          NAMES curl/curl.h
          PATH_SUFFIXES tarantool)
if (TARANTOOL_CURL_INCLUDE_DIR AND USE_TARANTOOL_CURL)
    message(STATUS "Link against tarantool's bundled lubCURL.")
    set(CURL_LIBRARIES)
    set(CURL_INCLUDE_DIRS "${TARANTOOL_CURL_INCLUDE_DIR}")
elseif (TARANTOOL_CURL_REQUIRED)
    message(FATAL_ERROR "Your Tarantool version doesn't have bundled lubCURL. "
            "The minimum required version is 1.10.9 or 2.8.1.")
else()
    message(WARNING "Installed tarantool version does not ship lubCURL headers."
            " Fallback to linking with system lubCURL.")
    set(CURL_LIBRARIES curl)
    set(CURL_INCLUDE_DIRS)
endif()
target_include_directories(lib PRIVATE ${CURL_INCLUDE_DIRS})
target_link_libraries(lib PRIVATE ${CURL_LIBRARIES})

set_target_properties(lib PROPERTIES PREFIX "" OUTPUT_NAME "lib")

# Install module
install(FILES init.lua DESTINATION ${TARANTOOL_INSTALL_LUADIR}/${PROJECT_NAME}/)
install(TARGETS lib LIBRARY DESTINATION ${TARANTOOL_INSTALL_LIBDIR}/${PROJECT_NAME}/)
