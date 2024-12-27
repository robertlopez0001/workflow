include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(workflow_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(workflow_setup_options)
  option(workflow_ENABLE_HARDENING "Enable hardening" ON)
  option(workflow_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    workflow_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    workflow_ENABLE_HARDENING
    OFF)

  workflow_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR workflow_PACKAGING_MAINTAINER_MODE)
    option(workflow_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(workflow_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(workflow_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(workflow_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(workflow_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(workflow_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(workflow_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(workflow_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(workflow_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(workflow_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(workflow_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(workflow_ENABLE_PCH "Enable precompiled headers" OFF)
    option(workflow_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(workflow_ENABLE_IPO "Enable IPO/LTO" ON)
    option(workflow_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(workflow_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(workflow_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(workflow_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(workflow_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(workflow_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(workflow_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(workflow_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(workflow_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(workflow_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(workflow_ENABLE_PCH "Enable precompiled headers" OFF)
    option(workflow_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      workflow_ENABLE_IPO
      workflow_WARNINGS_AS_ERRORS
      workflow_ENABLE_USER_LINKER
      workflow_ENABLE_SANITIZER_ADDRESS
      workflow_ENABLE_SANITIZER_LEAK
      workflow_ENABLE_SANITIZER_UNDEFINED
      workflow_ENABLE_SANITIZER_THREAD
      workflow_ENABLE_SANITIZER_MEMORY
      workflow_ENABLE_UNITY_BUILD
      workflow_ENABLE_CLANG_TIDY
      workflow_ENABLE_CPPCHECK
      workflow_ENABLE_COVERAGE
      workflow_ENABLE_PCH
      workflow_ENABLE_CACHE)
  endif()

  workflow_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (workflow_ENABLE_SANITIZER_ADDRESS OR workflow_ENABLE_SANITIZER_THREAD OR workflow_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(workflow_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(workflow_global_options)
  if(workflow_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    workflow_enable_ipo()
  endif()

  workflow_supports_sanitizers()

  if(workflow_ENABLE_HARDENING AND workflow_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR workflow_ENABLE_SANITIZER_UNDEFINED
       OR workflow_ENABLE_SANITIZER_ADDRESS
       OR workflow_ENABLE_SANITIZER_THREAD
       OR workflow_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${workflow_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${workflow_ENABLE_SANITIZER_UNDEFINED}")
    workflow_enable_hardening(workflow_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(workflow_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(workflow_warnings INTERFACE)
  add_library(workflow_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  workflow_set_project_warnings(
    workflow_warnings
    ${workflow_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(workflow_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    workflow_configure_linker(workflow_options)
  endif()

  include(cmake/Sanitizers.cmake)
  workflow_enable_sanitizers(
    workflow_options
    ${workflow_ENABLE_SANITIZER_ADDRESS}
    ${workflow_ENABLE_SANITIZER_LEAK}
    ${workflow_ENABLE_SANITIZER_UNDEFINED}
    ${workflow_ENABLE_SANITIZER_THREAD}
    ${workflow_ENABLE_SANITIZER_MEMORY})

  set_target_properties(workflow_options PROPERTIES UNITY_BUILD ${workflow_ENABLE_UNITY_BUILD})

  if(workflow_ENABLE_PCH)
    target_precompile_headers(
      workflow_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(workflow_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    workflow_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(workflow_ENABLE_CLANG_TIDY)
    workflow_enable_clang_tidy(workflow_options ${workflow_WARNINGS_AS_ERRORS})
  endif()

  if(workflow_ENABLE_CPPCHECK)
    workflow_enable_cppcheck(${workflow_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(workflow_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    workflow_enable_coverage(workflow_options)
  endif()

  if(workflow_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(workflow_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(workflow_ENABLE_HARDENING AND NOT workflow_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR workflow_ENABLE_SANITIZER_UNDEFINED
       OR workflow_ENABLE_SANITIZER_ADDRESS
       OR workflow_ENABLE_SANITIZER_THREAD
       OR workflow_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    workflow_enable_hardening(workflow_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
