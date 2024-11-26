#include "kittens.cuh"
using namespace kittens;
#define NUM_THREADS (kittens::WARP_THREADS) // use 1 warp

#define _row 16
#define _col 32

struct micro_globals {
    using _gl  = gl<float, -1, -1, -1, -1, st_fl<_row, _col>>;
    _gl x, o;
};

__global__ __launch_bounds__(NUM_THREADS, 1)
void micro_tk(const __grid_constant__ micro_globals g) {

    // shared memory
    extern __shared__ alignment_dummy __shm[];
    shared_allocator al((int*)&__shm[0]);
    st_fl<_row, _col> (&x_s) = al.allocate<st_fl<_row, _col>>();
    st_fl<_row, _col> (&o_s) = al.allocate<st_fl<_row, _col>>();

    // register memory 
    rt_fl<_row, _col> x_reg_fl;

    // load from HBM to shared
    load(x_s, g.x, {0, 0, 0, 0});
    __syncthreads();

    // load from shared to register
    load(x_reg_fl, x_s);
    __syncthreads();

    // x (dst) = x (src b) + x (src a)
    add(x_reg_fl, x_reg_fl, x_reg_fl);
    __syncthreads();

    // store from register to shared
    store(o_s, x_reg_fl);
    __syncthreads();

    // store from shared to HBM
    store(g.o, o_s, {0, 0, 0, 0});
    __syncthreads();
}

void dispatch_micro( float *d_x, float *d_o ) {
    using _gl = gl<float, -1, -1, -1, -1, st_fl<_row, _col>>;
    using globals = micro_globals;
    _gl  x_arg{d_x, 1, 1, _row, _col};
    _gl  o_arg{d_o, 1, 1, _row, _col};
    globals g{x_arg, o_arg};
    unsigned long mem_size = 50480; 
    cudaFuncSetAttribute(
        micro_tk,
        cudaFuncAttributeMaxDynamicSharedMemorySize,
        mem_size
    );
    micro_tk<<<1,32,mem_size>>>(g);
    cudaDeviceSynchronize();
}
#include "harness.impl"

