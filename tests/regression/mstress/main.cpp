#include "common.h"
#include <assert.h>
#include <iostream>
#include <limits>
#include <math.h>
#include <string.h>
#include <unistd.h>
#include <vector>
#include <vortex.h>

#include "espiral.h"

#define RT_CHECK(_expr)                                      \
  do {                                                       \
    int _ret = _expr;                                        \
    if (0 == _ret)                                           \
      break;                                                 \
    printf("Error: '%s' returned %d!\n", #_expr, (int)_ret); \
    cleanup();                                               \
    exit(-1);                                                \
  } while (false)

///////////////////////////////////////////////////////////////////////////////

union Float_t {
  float f;
  int i;
  struct {
    uint32_t man : 23;
    uint32_t exp : 8;
    uint32_t sign : 1;
  } parts;
};

inline float fround(float x, int32_t precision = 8) {
  auto power_of_10 = std::pow(10, precision);
  return std::round(x * power_of_10) / power_of_10;
}

inline bool almost_equal_eps(float a, float b, int ulp = 128) {
  auto eps = std::numeric_limits<float>::epsilon() * (std::max(fabs(a), fabs(b)) * ulp);
  auto d = fabs(a - b);
  if (d > eps) {
    std::cout << "*** almost_equal_eps: d=" << d << ", eps=" << eps << std::endl;
    return false;
  }
  return true;
}

inline bool almost_equal_ulp(float a, float b, int32_t ulp = 6) {
  Float_t fa{a}, fb{b};
  auto d = std::abs(fa.i - fb.i);
  if (d > ulp) {
    std::cout << "*** almost_equal_ulp: a=" << a << ", b=" << b << ", ulp=" << d << ", ia=" << std::hex << fa.i << ", ib=" << fb.i << std::endl;
    return false;
  }
  return true;
}

inline bool almost_equal(float a, float b) {
  if (a == b)
    return true;
  /*if (almost_equal_eps(a, b))
    return true;*/
  return almost_equal_ulp(a, b);
}

///////////////////////////////////////////////////////////////////////////////

const char *kernel_file = "kernel.vxbin";
uint32_t count = 0;

vx_device_h device = nullptr;
vx_buffer_h src0_buffer = nullptr;
vx_buffer_h src1_buffer = nullptr;
vx_buffer_h dst_buffer = nullptr;
vx_buffer_h krnl_buffer = nullptr;
vx_buffer_h args_buffer = nullptr;
kernel_arg_t kernel_arg = {};

static void show_usage() {
  std::cout << "Vortex Test." << std::endl;
  std::cout << "Usage: [-k: kernel] [-n words] [-h: help]" << std::endl;
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:k:h")) != -1) {
    switch (c) {
    case 'n':
      count = atoi(optarg);
      break;
    case 'k':
      kernel_file = optarg;
      break;
    case 'h':
      show_usage();
      exit(0);
      break;
    default:
      show_usage();
      exit(-1);
    }
  }
}

void cleanup() {
  if (device) {
    vx_mem_free(src0_buffer);
    vx_mem_free(src1_buffer);
    vx_mem_free(dst_buffer);
    vx_mem_free(krnl_buffer);
    vx_mem_free(args_buffer);
    vx_dev_close(device);
  }
}

void gen_src_data(std::vector<float> &test_data,
                  std::vector<uint32_t> &addr_table,
                  uint32_t num_points,
                  uint32_t num_addrs) {
  test_data.resize(num_points);
  addr_table.resize(num_addrs);

  for (uint32_t i = 0; i < num_points; ++i) {
    float r = static_cast<float>(std::rand()) / RAND_MAX;
    test_data[i] = r;
  }

  for (uint32_t i = 0; i < num_addrs; ++i) {
    float r = static_cast<float>(std::rand()) / RAND_MAX;
    uint32_t index = static_cast<uint32_t>(r * num_points);
    assert(index < num_points);
    addr_table[i] = index;
  }
}

int main(int argc, char *argv[]) {
  // parse command arguments
  parse_args(argc, argv);

  if (count == 0) {
    count = 1;
  }

  std::srand(50);

  // open device connection
  std::cout << "========== We are using espiral ==========" << std::endl;
  std::cout << "open device connection" << std::endl;
  espiral::Espiral espiral(espiral::backend::SIMX);

  uint64_t num_cores, num_warps, num_threads;
  num_cores = espiral.get_caps(VX_CAPS_NUM_CORES).value();
  num_warps = espiral.get_caps(VX_CAPS_NUM_WARPS).value();
  num_threads = espiral.get_caps(VX_CAPS_NUM_THREADS).value();

  uint32_t total_threads = num_cores * num_warps * num_threads;
  uint32_t num_points = count * total_threads;
  uint32_t num_addrs = num_points + NUM_LOADS - 1;

  uint32_t addr_buf_size = num_addrs * sizeof(int32_t);
  uint32_t src_buf_size = num_points * sizeof(int32_t);
  uint32_t dst_buf_size = num_points * sizeof(int32_t);

  std::cout << "number of points: " << num_points << std::endl;
  std::cout << "addr buffer size: " << addr_buf_size << " bytes" << std::endl;
  std::cout << "src buffer size: " << src_buf_size << " bytes" << std::endl;
  std::cout << "dst buffer size: " << dst_buf_size << " bytes" << std::endl;

  kernel_arg.num_tasks = total_threads;
  kernel_arg.stride = count;

  // create kernel
  const auto kid = espiral.allocate_kernel(kernel_file);

  // allocate device memory
  std::cout << "allocate device memory" << std::endl;
  auto src0_buf = espiral.allocate_upload_buffer(kid, addr_buf_size);
  auto src1_buf = espiral.allocate_upload_buffer(kid, src_buf_size);
  auto dst_buf_devaddr = espiral.allocate_dev_buffer(kid, dst_buf_size);
  kernel_arg.src0_addr = src0_buf.get_va();
  kernel_arg.src1_addr = src1_buf.get_va();
  kernel_arg.dst_addr = dst_buf_devaddr;

  std::cout << "dev_addr=0x" << std::hex << kernel_arg.src0_addr << std::endl;
  std::cout << "dev_src=0x" << std::hex << kernel_arg.src1_addr << std::endl;
  std::cout << "dev_dst=0x" << std::hex << kernel_arg.dst_addr << std::endl;

  // allocate host buffers
  std::cout << "allocate host buffers" << std::endl;
  std::vector<uint32_t> h_addr;
  std::vector<float> h_src;
  std::vector<float> h_dst(num_points);
  gen_src_data(h_src, h_addr, num_points, num_addrs);

  // upload source buffer0
  std::cout << "upload address buffer" << std::endl;
  src0_buf.set_content(h_addr.data(), addr_buf_size);
  espiral.upload(kid, src0_buf);

  // upload source buffer1
  std::cout << "upload source buffer" << std::endl;
  src1_buf.set_content(h_src.data(), src_buf_size);
  espiral.upload(kid, src1_buf);

  // upload kernel argument
  std::cout << "upload kernel argument" << std::endl;
  espiral.upload_args<kernel_arg_t>(kid, &kernel_arg);

  // start device
  std::cout << "start device" << std::endl;
  espiral.start_kernel(kid);

  // wait for completion
  std::cout << "wait for completion" << std::endl;
  espiral.wait_kernel(kid, VX_MAX_TIMEOUT);

  // download destination buffer
  std::cout << "download destination buffer" << std::endl;
  espiral::DownloadBuffer dst_download_buf(dst_buf_devaddr, dst_buf_size, h_dst.data());
  espiral.download(kid, dst_download_buf);

  // verify result
  std::cout << "verify result" << std::endl;
  int errors = 0;
  for (uint32_t i = 0; i < num_points; ++i) {
    float ref = 0.0f;
    for (uint32_t j = 0; j < NUM_LOADS; ++j) {
      uint32_t addr = i + j;
      uint32_t index = h_addr[addr];
      float value = h_src[index];
      // printf("*** [%d] addr=%d, index=%d, value=%f\n", i, addr, index, value);
      ref *= value;
    }

    float cur = h_dst[i];
    if (!almost_equal(cur, ref)) {
      std::cout << "error at result #" << std::dec << i
                << ": actual " << cur << ", expected " << ref << std::endl;
      ++errors;
    }
  }

  // cleanup
  std::cout << "cleanup" << std::endl;
  espiral.free_kernel(kid);
  cleanup();

  if (errors != 0) {
    std::cout << "Found " << std::dec << errors << " errors!" << std::endl;
    std::cout << "FAILED!" << std::endl;
    return 1;
  }

  std::cout << "PASSED!" << std::endl;

  return 0;
}