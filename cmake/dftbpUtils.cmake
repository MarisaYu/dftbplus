# Replaces the extension of a given file
#
# Args:
#     oldext [in]: Old extension
#     newext [in]: New extension
#     fname [in]: File name in which extension should be replaced.
#     newfname [out]: File name after extension replacement.
#
function(dftbp_replace_extension oldext newext fname newfname)

  string(REGEX REPLACE "\\.${oldext}$" ".${newext}" _newfname ${fname})
  set(${newfname} ${_newfname} PARENT_SCOPE)

endfunction()


# Registers files for preprocessing
#
# Args:
#     preproc [in]: Preprocessor to use
#     preprocopts [in]:  Preprocessor command line arguments (but not in/out file)
#     oldext [in]: Extension of the unpreprocessed files.
#     newext [in]: Extension of the preprocessed files.
#     oldfiles [in]: List of unpreprocessed file names.
#     newfiles [out]: List of preprocessed file names.
#
function(dftbp_preprocess preproc preprocopts oldext newext oldfiles newfiles)

  set(_newfiles)
  foreach(oldfile IN LISTS oldfiles)
    dftbp_replace_extension(${oldext} ${newext} ${oldfile} newfile)
    add_custom_command(
      OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${newfile}
      COMMAND ${preproc} ${preprocopts} ${CMAKE_CURRENT_SOURCE_DIR}/${oldfile} ${CMAKE_CURRENT_BINARY_DIR}/${newfile}
      MAIN_DEPENDENCY ${CMAKE_CURRENT_SOURCE_DIR}/${oldfile})
    list(APPEND _newfiles ${CMAKE_CURRENT_BINARY_DIR}/${newfile})
  endforeach()
  set(${newfiles} ${_newfiles} PARENT_SCOPE)

endfunction()


# Build -D command line arguments for Fypp preprocessor based on current configuration
#
# Args:
#     fyppflags [inout]: Current Fypp flags on enter, with -D options extended flags on exit.
#
function (dftbp_add_fypp_defines fyppflags)

  set(_fyppflags "${${fyppflags}}")
  if(WITH_OMP)
    list(APPEND _fyppflags -DWITH_OMP)
  endif()

  if(WITH_ARPACK)
    list(APPEND _fyppflags -DWITH_ARPACK)
  endif()

  if(WITH_DFTD3)
    list(APPEND _fyppflags -DWITH_DFTD3)
  endif()

  if(WITH_MPI)
    list(APPEND _fyppflags -DWITH_MPI -DWITH_SCALAPACK)
  endif()

  if(WITH_SOCKETS)
    list(APPEND _fyppflags -DWITH_SOCKETS)
  endif()

  if(WITH_ELSI)
    list(APPEND _fyppflags -DWITH_ELSI)
  endif()

  if(ELSI_WITH_PEXSI)
    list(APPEND _fyppflags -DWITH_PEXSI)
  endif()

  if(WITH_GPU)
    list(APPEND _fyppflags -DWITH_GPU)
  endif()

  if(WITH_TRANSPORT)
    list(APPEND _fyppflags -DWITH_TRANSPORT)
  endif()

  set(${fyppflags} ${_fyppflags} PARENT_SCOPE)

endfunction()


# Gets DFTB+ release information.
#
# Args:
#   release [out]: Release string.
#
function(dftbp_get_release_name release)

  if(NOT EXISTS ${CMAKE_BINARY_DIR}/RELEASE)
    if(EXISTS ${CMAKE_SOURCE_DIR}/RELEASE)
      file(COPY ${CMAKE_SOURCE_DIR}/RELEASE DESTINATION ${CMAKE_BINARY_DIR})
    else()
      execute_process(
	COMMAND ${CMAKE_SOURCE_DIR}/utils/build/update_release ${CMAKE_BINARY_DIR}/RELEASE
	RESULT_VARIABLE exitcode)
      if(NOT exitcode EQUAL 0)
	file(WRITE ${CMAKE_BINARY_DIR}/RELEASE "(UNKNOWN RELEASE)")
      endif()
    endif()
  endif()
  file(READ ${CMAKE_BINARY_DIR}/RELEASE _release)
  separate_arguments(_release)
  set(${release} "${_release}" PARENT_SCOPE)

endfunction()


# Finds libraries and turns them into imported library targets
#
# Args:
#     libraries [in]: List of the library names to look for.
#     libpaths [in]: List of the paths to be used as hints when looking for the libraries.
#
function (dftbp_create_library_targets libraries libpaths)
  foreach(lib IN LISTS libraries)
    if(NOT (TARGET ${lib}))
      find_library(LIBPATH ${lib} HINTS ${libpaths})
      if(LIBPATH)
	message(STATUS "Found library ${LIBPATH}")
	if(EXPORT_EXTLIBS_WITH_PATH)
	  add_library(${lib} INTERFACE)
	  target_link_libraries(${lib} INTERFACE ${LIBPATH})
	  install(TARGETS ${lib} EXPORT dftbplus-targets)
	else()
          add_library(${lib} IMPORTED UNKNOWN)
          set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION ${LIBPATH})
	endif()
      else()
        message(FATAL_ERROR
	  "Could not find library '${lib}' using library path hints '${libpaths}'")
      endif()
      unset(LIBPATH CACHE)
    endif()
  endforeach()
endfunction()


# Converts a space separated string into a list.
#
# Args:
#     * [in]: Name of the variables to convert. On exit the variables contain
#         the converted values.
#
function (dftbp_convert_to_list)
  foreach(varname IN LISTS ARGN)
    set(buffer "${${varname}}")
    separate_arguments(buffer)
    set(${varname} "${buffer}" PARENT_SCOPE)
  endforeach()
endfunction()


# Checks the build configuration on consistency and stops in case of inconsistencies
function (dftbp_ensure_config_consistency)

  if(WITH_ELSI AND NOT WITH_MPI)
    message(FATAL_ERROR "Buliding with ELSI requires MPI-parallel build enabled")
  endif()

  if(WITH_PEXSI AND (NOT WITH_MPI OR NOT WITH_ELSI))
    message(FATAL_ERROR "Building with PEXSI requires MPI-parallel build and ELSI enabled")
  endif()

  if(WITH_ARPACK AND WITH_MPI)
    message(FATAL_ERROR "Building with ARPACK requires MPI-parallel build disabled")
  endif()

  if(BUILD_SHARED_LIBS AND WITH_TRANSPORT)
    message(FATAL_ERROR "Transport is currently only possible with static libraries")
  endif()

  if(("${CMAKE_Fortran_COMPILER_ID}" STREQUAL "NAG") AND WITH_OMP)
    message(FATAL_ERROR
      "NAG compiler usually creates crashing binary with OpenMP-parallelisation in debug mode. \
Disable OpenMP (WITH_OMP) when compiling in debug mode")
  endif()

  if("${CMAKE_Fortran_COMPILER_ID}" STREQUAL "Intel")
    string(FIND "${CMAKE_Fortran_FLAGS}" "-standard-semantics" pos1)
    string(FIND "${CMAKE_Fortran_FLAGS}" "realloc_lhs" pos2)
    string(FIND "${CMAKE_Fortran_FLAGS}" "norealloc_lhs" pos3)
    if(NOT ((NOT pos1 EQUAL -1) OR ((NOT pos2 EQUAL -1) AND (pos3 EQUAL -1))))
      message(FATAL_ERROR "Intel compiler needs either the '-standard-semantics' or the '-assume \
realloc_lhs' option to produce correctly behaving (Fortran standard complying) code")
    endif()
  endif()

  set(pkgconfig_languages C Fortran)
  list(FIND pkgconfig_languages "${PKGCONFIG_LANGUAGE}" pos)
  if(pos EQUAL -1)
    string(REPLACE ";" "\", \"" pkgconfig_languages_str "${pkgconfig_languages}")
    set(pkgconfig_languages_str "\"${pkgconfig_languages_str}\"")
    message(FATAL_ERROR
      "Invalid language \"${PKGCONFIG_LANGUAGE}\" for PKGCONFIG_LANGUAGE (possible choices: ${pkgconfig_languages_str})")
  endif()

endfunction()


# Prepends a given prefix to a list of items.
#
# Args:
#     result [out]: Variable containing the results
#     prefix [in]: Prefix to add to each item
#     * [in]: List of items to be prefixed
#
function(dftbp_add_prefix prefix itemlist result)
  set(_result)
  foreach(var IN LISTS itemlist)
    list(APPEND _result "${prefix}${var}")
  endforeach()
  set(${result} "${_result}" PARENT_SCOPE)
endfunction()


# Returns the parameters needed to create a pkg-config export file
#
# Args:
#     pkgconfig_requires [out]: Value for the Requires field.
#     pkgconfig_libs [out]: Value for the Libs field.
#     pkgconfig_libs_private [out]: Value for the Libs.private field.
#     pkgconfig_c_flags [out]: value for the cflags field.
#
function(dftbp_get_pkgconfig_params pkgconfig_requires pkgconfig_libs pkgconfig_libs_private
    pkgconfig_c_flags)

  set(_pkgconfig_libs "-L${INSTALL_LIB_DIR} -ldftbplus")
  set(_pkgconfig_libs_private)

  dftbp_add_prefix("-l" "${EXPORTED_COMPILED_LIBRARIES}" complibs)
  list(APPEND _pkgconfig_libs "${complibs}")

  dftbp_add_prefix("-L" "${EXPORTED_EXTERNAL_LIBRARY_DIRS}" extlibdirs)
  list(APPEND _pkgconfig_libs_private "${extlibdirs}")

  dftbp_add_prefix("-l" "${EXPORTED_EXTERNAL_LIBRARIES}" extlibs)
  list(APPEND _pkgconfig_libs_private "${extlibs}")

  if(PKGCONFIG_LANGUAGE STREQUAL "C")

    set(implibdirs "${CMAKE_Fortran_IMPLICIT_LINK_DIRECTORIES}")
    list(REMOVE_ITEM implibdirs ${CMAKE_C_IMPLICIT_LINK_DIRECTORIES})
    dftbp_add_prefix("-L" "${implibdirs}" implibdirs)
    list(APPEND _pkgconfig_libs_private "${implibdirs}")

    set(implibs "${CMAKE_Fortran_IMPLICIT_LINK_LIBRARIES}")
    list(REMOVE_ITEM implibs ${CMAKE_C_IMPLICIT_LINK_LIBRARIES})
    dftbp_library_linking_flags("${implibs}" implibs)
    list(APPEND _pkgconfig_libs_private "${implibs}")

    set(_pkgconfig_c_flags "-I${INSTALL_INC_DIR} ${CMAKE_C_FLAGS}")

  else()

    set(implibdirs "${CMAKE_C_IMPLICIT_LINK_DIRECTORIES}")
    list(REMOVE_ITEM implibdirs ${CMAKE_Fortran_IMPLICIT_LINK_DIRECTORIES})
    dftbp_add_prefix("-L" "${implibdirs}" implibdirs)
    list(APPEND _pkgconfig_libs_private "${implibdirs}")

    set(implibs "${CMAKE_C_IMPLICIT_LINK_LIBRARIES}")
    list(REMOVE_ITEM implibs ${CMAKE_Fortran_IMPLICIT_LINK_LIBRARIES})
    dftbp_library_linking_flags("${implibs}" implibs)
    list(APPEND _pkgconfig_libs_private "${implibs}")

    set(_pkgconfig_c_flags "-I${INSTALL_MOD_DIR} ${CMAKE_Fortran_FLAGS}")

  endif()

  string(REPLACE ";" " " _pkgconfig_libs "${_pkgconfig_libs}")
  string(REPLACE ";" " " _pkgconfig_libs_private "${_pkgconfig_libs_private}")

  set(_pkgconfig_libs_private "${_pkgconfig_libs_private} ${CMAKE_EXE_LINKER_FLAGS}")
  string(REPLACE ";" " " _pkgconfig_requires "${EXPORTED_EXTERNAL_PACKAGES}")

  set(${pkgconfig_requires} "${_pkgconfig_requires}" PARENT_SCOPE)
  set(${pkgconfig_libs} "${_pkgconfig_libs}" PARENT_SCOPE)
  set(${pkgconfig_libs_private} "${_pkgconfig_libs_private}" PARENT_SCOPE)
  set(${pkgconfig_c_flags} "${_pkgconfig_c_flags}" PARENT_SCOPE)

endfunction()


# Returns library linking flags for given libraries.
#
# If the library is a full path, it is linked directly, otherwise with the "-l" option
#
# Args:
#     libraries [in]: List of libraries to check.
#     linkflags [out]: List of flags to link the libraries
#
function(dftbp_library_linking_flags libraries linkflags)
  set(_linkflags)
  foreach(library IN LISTS libraries)
    if(IS_ABSOLUTE "${library}" AND EXISTS "${library}")
      list(APPEND _linkflags "${library}")
    else()
      list(APPEND _linkflags "-l${library}")
    endif()
  endforeach()
  set(${linkflags} "${_linkflags}" PARENT_SCOPE)
endfunction()
