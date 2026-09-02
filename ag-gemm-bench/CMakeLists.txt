cmake_minimum_required(VERSION 3.22)

project(ag_gemm_bench LANGUAGES CXX CUDA)

find_package(CUDAToolkit REQUIRED)
find_package(MPI REQUIRED COMPONENTS CXX)

find_path(NCCL_INCLUDE_DIR nccl.h
  HINTS /usr/include /usr/local/cuda/include /usr/local/cuda/targets/x86_64-linux/include)
find_library(NCCL_LIBRARY nccl
  HINTS /usr/lib/x86_64-linux-gnu /usr/local/cuda/lib64 /usr/local/cuda/targets/x86_64-linux/lib)

if(NOT NCCL_INCLUDE_DIR OR NOT NCCL_LIBRARY)
  message(FATAL_ERROR "NCCL headers or libnccl were not found. Set NCCL_INCLUDE_DIR and NCCL_LIBRARY.")
endif()

add_executable(ag_gemm_bench src/ag_gemm_bench.cu)
target_compile_features(ag_gemm_bench PRIVATE cxx_std_17)
target_include_directories(ag_gemm_bench PRIVATE ${NCCL_INCLUDE_DIR})
target_link_libraries(ag_gemm_bench PRIVATE MPI::MPI_CXX CUDA::cudart CUDA::cublas ${NCCL_LIBRARY})
set_target_properties(ag_gemm_bench PROPERTIES
  CUDA_ARCHITECTURES "80;86;89"
  CUDA_SEPARABLE_COMPILATION ON)
