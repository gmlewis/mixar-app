# SPDX-FileCopyrightText: 2026 Adeveda Enterprises Private Limited
#
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is loaded *before* any project() call
# You can override ANY cache variable in Blender.

# Only set CMP0167 policy if it's available (CMake 3.30+)
if(POLICY CMP0167)
  cmake_policy(SET CMP0167 OLD)
endif()

# Windows/MSVC: Base compiler flags.
if(CMAKE_HOST_WIN32)
  set(CMAKE_CXX_FLAGS "/DWIN32 /D_WINDOWS /W3 /GR /EHsc" CACHE STRING "C++ compiler flags" FORCE)
  set(CMAKE_C_FLAGS "/DWIN32 /D_WINDOWS /W3" CACHE STRING "C compiler flags" FORCE)
endif()

# Cycles GPU backend is platform-specific:
#  - macOS / Apple Silicon: Metal (CUDA/OptiX are NVIDIA-only and unavailable here;
#    forcing WITH_CYCLES_CUDA_BINARIES would require nvcc and fail the build).
#  - Windows / Linux with NVIDIA: CUDA + OptiX when the CUDA toolkit and OptiX SDK
#    are available; otherwise fall back to CPU-only Cycles.
if(APPLE)
  set(WITH_CYCLES_DEVICE_METAL ON CACHE BOOL "Enable Cycles Metal GPU compute support" FORCE)
else()
  # Enable CUDA support for Cycles rendering when the CUDA toolkit is present.
  # WITH_CUDA_DYNLOAD allows Cycles to dlopen libcuda at runtime, so the build
  # succeeds even without nvcc — but CUDA kernels won't be pre-compiled.
  find_program(CUDA_NVCC NAMES nvcc
    PATHS
      ENV CUDA_PATH
      ENV MIXAR_CUDA_PATH
      /usr/local/cuda
      /usr/local/cuda-12
      /usr
    PATH_SUFFIXES bin
  )
  if(CUDA_NVCC)
    set(WITH_CYCLES_DEVICE_CUDA ON CACHE BOOL "Enable Cycles NVIDIA CUDA compute support" FORCE)
    set(WITH_CYCLES_CUDA_BINARIES ON CACHE BOOL "Build Cycles NVIDIA CUDA binaries" FORCE)
    set(WITH_CUDA_DYNLOAD ON CACHE BOOL "Dynamically load CUDA libraries at runtime" FORCE)
    message(STATUS "CUDA toolkit found: ${CUDA_NVCC} — enabling CUDA + OptiX")
  else()
    set(WITH_CYCLES_DEVICE_CUDA ON CACHE BOOL "Enable Cycles NVIDIA CUDA compute support" FORCE)
    set(WITH_CYCLES_CUDA_BINARIES OFF CACHE BOOL "Build Cycles NVIDIA CUDA binaries" FORCE)
    set(WITH_CUDA_DYNLOAD ON CACHE BOOL "Dynamically load CUDA libraries at runtime" FORCE)
    message(STATUS "CUDA toolkit NOT found — Cycles CUDA enabled (dynload) but kernels not pre-compiled. "
      "Install nvidia-cuda-toolkit (or set CUDA_PATH/MIXAR_CUDA_PATH) to enable CUDA kernels.")
  endif()

  # Enable OptiX support when the OptiX SDK is present.
  # Search paths (in order):
  #   MIXAR_OPTIX_ROOT / OPTIX_ROOT_PATH env vars
  #   Common install locations
  #   User home directory (NVIDIA SDK default extract path)
  find_path(OPTIX_INCLUDE_DIR NAMES optix.h PATHS
    ENV MIXAR_OPTIX_ROOT
    ENV OPTIX_ROOT_PATH
    /opt/NVIDIA/OptiX
    /usr/local/NVIDIA/OptiX
    $ENV{HOME}/NVIDIA-OptiX
    $ENV{HOME}/src/github.com/nvidia/NVIDIA-OptiX-SDK-7.3.0-linux64-x86_64
    PATH_SUFFIXES include
  )
  if(OPTIX_INCLUDE_DIR)
    set(WITH_CYCLES_DEVICE_OPTIX ON CACHE BOOL "Enable Cycles NVIDIA OptiX support" FORCE)
    message(STATUS "OptiX SDK found at ${OPTIX_INCLUDE_DIR} — enabling OptiX")
  else()
    set(WITH_CYCLES_DEVICE_OPTIX OFF CACHE BOOL "Enable Cycles NVIDIA OptiX support" FORCE)
    message(STATUS "OptiX SDK NOT found — disabling OptiX. "
      "Install from https://developer.nvidia.com/optix/downloads and set "
      "MIXAR_OPTIX_ROOT or OPTIX_ROOT_PATH to enable.")
  endif()
endif()

# sccache compiler launcher - auto-enabled when sccache is on PATH.
# On Windows, Blender's platform_win32.cmake handles /Z7 and compiler launcher
# when WITH_WINDOWS_SCCACHE is ON. On other platforms, we set the launcher directly.
find_program(SCCACHE_PROGRAM sccache)
if(SCCACHE_PROGRAM)
  message(STATUS "sccache found: ${SCCACHE_PROGRAM}")
  if(CMAKE_HOST_WIN32)
    # Use Blender's native sccache support (handles /Z7, compiler launcher, PDB)
    set(WITH_WINDOWS_SCCACHE ON CACHE BOOL "" FORCE)
  else()
    set(CMAKE_C_COMPILER_LAUNCHER   "${SCCACHE_PROGRAM}" CACHE STRING "" FORCE)
    set(CMAKE_CXX_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}" CACHE STRING "" FORCE)
  endif()
else()
  message(STATUS "sccache not found - building without compiler cache")
endif()
