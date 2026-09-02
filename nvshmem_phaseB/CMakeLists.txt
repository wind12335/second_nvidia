cmake_minimum_required(VERSION 3.22)

project(nvshmem_phaseb_admission LANGUAGES CXX CUDA)

if(NOT DEFINED NVSHMEM_PREFIX)
  if(DEFINED ENV{NVSHMEM_PREFIX})
    set(NVSHMEM_PREFIX "$ENV{NVSHMEM_PREFIX}")
  else()
    set(NVSHMEM_PREFIX "/root/comm-study/install/nvshmem")
  endif()
endif()

find_package(CUDAToolkit REQUIRED)
find_package(MPI REQUIRED COMPONENTS CXX)
find_package(NVSHMEM REQUIRED HINTS "${NVSHMEM_PREFIX}/lib/cmake/nvshmem")

add_executable(nvshmem_admission src/nvshmem_admission.cu)
target_compile_features(nvshmem_admission PRIVATE cxx_std_17)
target_compile_definitions(nvshmem_admission PRIVATE
  __STDC_LIMIT_MACROS __STDC_CONSTANT_MACROS)
target_include_directories(nvshmem_admission PRIVATE
  "${NVSHMEM_PREFIX}/include")
target_link_libraries(nvshmem_admission PRIVATE
  MPI::MPI_CXX
  CUDA::cudart
  CUDA::cuda_driver
  nvshmem::nvshmem_host
  nvshmem::nvshmem_device)
# 2026-09-02 A800 会话：默认 sm_80（A800/GA100）；4090 时代为 89。可用 -DCUDA_ARCH_OVERRIDE=89 覆盖
if(NOT CUDA_ARCH_OVERRIDE)
  set(CUDA_ARCH_OVERRIDE 80)
endif()
set_target_properties(nvshmem_admission PROPERTIES
  CUDA_ARCHITECTURES "${CUDA_ARCH_OVERRIDE}"
  CUDA_SEPARABLE_COMPILATION ON
  POSITION_INDEPENDENT_CODE ON
  BUILD_RPATH "${NVSHMEM_PREFIX}/lib"
  INSTALL_RPATH "${NVSHMEM_PREFIX}/lib")

