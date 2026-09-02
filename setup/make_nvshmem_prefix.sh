#!/usr/bin/env bash
# 为 pip wheel 版 NVSHMEM 3.6.5 构造 CMake 前缀（wheel 不带 CMake config，phaseb-nvidia-port 需要）。
# 用法：bash setup/make_nvshmem_prefix.sh [目标前缀目录，默认 <本仓库>/../nvshmem-3.6.5-wheel]
set -e
PREFIX=${1:-$(dirname "$0")/../../nvshmem-3.6.5-wheel}
WHEEL=$(python3 -c 'import nvidia.nvshmem as m, os; print(os.path.dirname(m.__file__))')
mkdir -p "$PREFIX/lib/cmake/nvshmem"
ln -sfn "$WHEEL/include" "$PREFIX/include"
for f in libnvshmem_host.so libnvshmem_host.so.3 libnvshmem_device.a \
         nvshmem_bootstrap_mpi.so.3 nvshmem_bootstrap_uid.so.3 nvshmem_bootstrap_shmem.so.3 nvshmem_bootstrap_pmi.so.3; do
  ln -sfn "$WHEEL/lib/$f" "$PREFIX/lib/$f"
done
cat > "$PREFIX/lib/cmake/nvshmem/nvshmem-config.cmake" <<'CMEOF'
if(NOT TARGET nvshmem::nvshmem_host)
  add_library(nvshmem::nvshmem_host SHARED IMPORTED)
  set_target_properties(nvshmem::nvshmem_host PROPERTIES
    IMPORTED_LOCATION "${NVSHMEM_PREFIX}/lib/libnvshmem_host.so"
    INTERFACE_INCLUDE_DIRECTORIES "${NVSHMEM_PREFIX}/include")
endif()
if(NOT TARGET nvshmem::nvshmem_device)
  add_library(nvshmem::nvshmem_device STATIC IMPORTED)
  set_target_properties(nvshmem::nvshmem_device PROPERTIES
    IMPORTED_LOCATION "${NVSHMEM_PREFIX}/lib/libnvshmem_device.a"
    INTERFACE_INCLUDE_DIRECTORIES "${NVSHMEM_PREFIX}/include")
endif()
CMEOF
echo "NVSHMEM_PREFIX=$PREFIX 就绪（wheel=$WHEEL）"
