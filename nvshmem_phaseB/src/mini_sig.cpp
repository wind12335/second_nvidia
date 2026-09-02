// mini_sig.cu — putmem_signal 最小复现器（2026-09-02 A800 会话诊断用，非正式实验）
// 用法: mpirun -np 2 ./mini_sig <on_stream|blocking> <bytes>
// PE0 向 PE1 发 put+signal，PE1 wait 后校验 payload 首字。全 printf 到 stdout。
#include <cstdio>
#include <cstdint>
#include <cuda_runtime.h>
#include <nvshmem.h>
#include <nvshmemx.h>
#include <mpi.h>

#define CK(x) do { auto e_=(x); if(e_!=cudaSuccess){printf("[%d] CUDA fail %s @%d: %s\n",rank,#x,__LINE__,cudaGetErrorString(e_)); MPI_Abort(MPI_COMM_WORLD,1);} } while(0)

int main(int argc, char** argv) {
  int rank; MPI_Init(&argc,&argv); MPI_Comm_rank(MPI_COMM_WORLD,&rank);
  const char* mode = argc>1?argv[1]:"on_stream";
  size_t bytes = argc>2?strtoull(argv[2],nullptr,10):4096;

  MPI_Comm c = MPI_COMM_WORLD;
  nvshmemx_init_attr_t attr = NVSHMEMX_INIT_ATTR_INITIALIZER;
  attr.mpi_comm = &c;
  nvshmemx_init_attr(NVSHMEMX_INIT_WITH_MPI_COMM, &attr);
  int pe = nvshmem_my_pe(), npes = nvshmem_n_pes();
  CK(cudaSetDevice(nvshmem_team_my_pe(NVSHMEMX_TEAM_NODE)));
  if (rank==0) printf("init OK npes=%d mode=%s bytes=%zu\n", npes, mode, bytes);

  uint32_t* buf = (uint32_t*)nvshmem_malloc(bytes);
  uint64_t* sig = (uint64_t*)nvshmem_malloc(sizeof(uint64_t));
  CK(cudaMemset(buf, 0, bytes)); CK(cudaMemset(sig, 0, 8));
  nvshmem_barrier_all();

  cudaStream_t s; CK(cudaStreamCreateWithFlags(&s, cudaStreamNonBlocking));
  if (pe == 0) {
    CK(cudaMemset(buf, 0xA5, bytes));           // payload 标记
    uint32_t* rbuf = (uint32_t*)nvshmem_ptr(buf, 1);
    uint64_t*  rsig = (uint64_t*)nvshmem_ptr(sig, 1);
    printf("pe0 local buf=%p remote buf=%p remote sig=%p delta=%ld\n", buf, rbuf, rsig, (long)((char*)rbuf-(char*)buf));
    if (strcmp(mode,"self_on_stream")==0) {
      // 自发给自己：不跨 PE，检验 on_stream 机制本身
      nvshmemx_putmem_signal_on_stream(buf, buf, bytes, sig, 42, NVSHMEM_SIGNAL_SET, 0, s);
    } else {
      nvshmemx_putmem_signal_on_stream(rbuf, buf, bytes, rsig, 42, NVSHMEM_SIGNAL_SET, 1, s);
    }
    printf("pe0 issue done (mode=%s)\n", mode); fflush(stdout);
    nvshmemx_quiet_on_stream(s);
    CK(cudaStreamSynchronize(s));
  } else {
    // host 轮询代替 device wait_until
    uint64_t h = 0; int spins=0;
    do { CK(cudaMemcpy(&h, sig, 8, cudaMemcpyDeviceToHost)); if(++spins>1000000){printf("pe1 TIMEOUT\n");break;} } while (h != 42);
    uint32_t host_w = 0; CK(cudaMemcpy(&host_w, buf, 4, cudaMemcpyDeviceToHost));
    uint32_t expect = 0xA5A5A5A5u;
    printf("pe1 got signal, payload first word %08X expect %08X -> %s\n",
           host_w, expect, host_w==expect?"PASS":"FAIL");
    fflush(stdout);
  }
  nvshmem_barrier_all();
  if (pe==0) printf("mini_sig %s %zu DONE\n", mode, bytes);
  nvshmem_free(buf); nvshmem_free(sig);
  nvshmem_finalize(); MPI_Finalize();
  return 0;
}
