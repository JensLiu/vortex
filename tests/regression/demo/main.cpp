#include "common.h"
#include <iostream>
#include <string.h>
#include <unistd.h>
#include <vector>
#include <vortex.h>

#include "host_accelerator_interface.hpp"
#include "simx_backend.hpp"
#include "spinner.hpp"

#define FLOAT_ULP 6

#if 0
#define RT_CHECK(_expr)                                      \
  do {                                                       \
    int _ret = _expr;                                        \
    if (0 == _ret)                                           \
      break;                                                 \
    printf("Error: '%s' returned %d!\n", #_expr, (int)_ret); \
    cleanup();                                               \
    exit(-1);                                                \
  } while (false)
#endif

///////////////////////////////////////////////////////////////////////////////

template <typename Type>
class Comparator {};

template <>
class Comparator<int> {
public:
  static const char *type_str() {
    return "integer";
  }
  static int generate() {
    return rand();
  }
  static bool compare(int a, int b, int index, int errors) {
    if (a != b) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%d, actual=%d\n", index, b, a);
      }
      return false;
    }
    return true;
  }
};

template <>
class Comparator<float> {
private:
  union Float_t {
    float f;
    int i;
  };

public:
  static const char *type_str() {
    return "float";
  }
  static float generate() {
    return static_cast<float>(rand()) / RAND_MAX;
  }
  static bool compare(float a, float b, int index, int errors) {
    union fi_t {
      float f;
      int32_t i;
    };
    fi_t fa, fb;
    fa.f = a;
    fb.f = b;
    auto d = std::abs(fa.i - fb.i);
    if (d > FLOAT_ULP) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%f(0x%x), actual=%f(0x%x), ulp=%d\n", index, b, fb.i, a, fa.i, d);
      }
      return false;
    }
    return true;
  }
};

const char *kernel_file = "kernel.vxbin";
uint32_t count = 16;

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
    case 'h': {
      show_usage();
      exit(0);
    } break;
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

int main(int argc, char *argv[]) {
  // parse command arguments
  parse_args(argc, argv);

  std::srand(50);

  // open device connection
  std::cout << "========== We are using espiral ==========" << std::endl;
  std::cout << "open device connection" << std::endl;
  // RT_CHECK(vx_dev_open(&device));
  espiral::HostAcceleratorInterface *dev = new espiral::SimXDevice();
  espiral::Spinner spinner(dev);

  uint64_t num_cores, num_warps, num_threads;
  // RT_CHECK(vx_dev_caps(device, VX_CAPS_NUM_CORES, &num_cores));
  // RT_CHECK(vx_dev_caps(device, VX_CAPS_NUM_WARPS, &num_warps));
  // RT_CHECK(vx_dev_caps(device, VX_CAPS_NUM_THREADS, &num_threads));
  num_cores = dev->get_caps(VX_CAPS_NUM_CORES).value();
  num_warps = dev->get_caps(VX_CAPS_NUM_WARPS).value();
  num_threads = dev->get_caps(VX_CAPS_NUM_THREADS).value();

  uint32_t total_threads = num_cores * num_warps * num_threads;
  uint32_t num_points = count * total_threads;
  uint32_t buf_size = num_points * sizeof(TYPE);

  std::cout << "data type: " << Comparator<TYPE>::type_str() << std::endl;
  std::cout << "number of points: " << num_points << std::endl;
  std::cout << "buffer size: " << buf_size << " bytes" << std::endl;

  kernel_arg.num_tasks = total_threads;
  kernel_arg.task_size = count;

  // create kernel
  const auto kid = spinner.allocate_kernel(kernel_file);

  // allocate device memory
  std::cout << "allocate device memory" << std::endl;
  // RT_CHECK(vx_mem_alloc(device, buf_size, VX_MEM_READ, &src0_buffer));
  // RT_CHECK(vx_mem_address(src0_buffer, &kernel_arg.src0_addr));
  // RT_CHECK(vx_mem_alloc(device, buf_size, VX_MEM_READ, &src1_buffer));
  // RT_CHECK(vx_mem_address(src1_buffer, &kernel_arg.src1_addr));
  // RT_CHECK(vx_mem_alloc(device, buf_size, VX_MEM_WRITE, &dst_buffer));
  // RT_CHECK(vx_mem_address(dst_buffer, &kernel_arg.dst_addr));
  auto src0_buf = spinner.allocate_upload_buffer(kid, buf_size);
  auto src1_buf = spinner.allocate_upload_buffer(kid, buf_size);
  auto dst_buf_devaddr = spinner.allocate_dev_buffer(kid, buf_size);
  kernel_arg.src0_addr = src0_buf.get_va();
  kernel_arg.src1_addr = src1_buf.get_va();
  kernel_arg.dst_addr = dst_buf_devaddr;
  

  std::cout << "dev_src0=0x" << std::hex << kernel_arg.src0_addr << std::endl;
  std::cout << "dev_src1=0x" << std::hex << kernel_arg.src1_addr << std::endl;
  std::cout << "dev_dst=0x" << std::hex << kernel_arg.dst_addr << std::endl;

  // allocate host buffers
  std::cout << "allocate host buffers" << std::endl;
  std::vector<TYPE> h_src0(num_points);
  std::vector<TYPE> h_src1(num_points);
  std::vector<TYPE> h_dst(num_points);

  // generate source data
  for (uint32_t i = 0; i < num_points; ++i) {
    h_src0[i] = Comparator<TYPE>::generate();
    h_src1[i] = Comparator<TYPE>::generate();
  }

  // upload source buffer0
  std::cout << "upload source buffer0" << std::endl;
  // RT_CHECK(vx_copy_to_dev(src0_buffer, h_src0.data(), 0, buf_size));
  src0_buf.set_content(h_src0.data(), buf_size);
  spinner.upload(kid, src0_buf);

  // upload source buffer1
  std::cout << "upload source buffer1" << std::endl;
  // RT_CHECK(vx_copy_to_dev(src1_buffer, h_src1.data(), 0, buf_size));
  src1_buf.set_content(h_src1.data(), buf_size);
  spinner.upload(kid, src1_buf);

  // Upload kernel binary
  // std::cout << "Upload kernel binary" << std::endl;
  // RT_CHECK(vx_upload_kernel_file(device, kernel_file, &krnl_buffer));

  // upload kernel argument
  std::cout << "upload kernel argument" << std::endl;
  // RT_CHECK(vx_upload_bytes(device, &kernel_arg, sizeof(kernel_arg_t), &args_buffer));
  spinner.upload_args<kernel_arg_t>(kid, &kernel_arg);

  // start device
  std::cout << "start device" << std::endl;
  // RT_CHECK(vx_start(device, krnl_buffer, args_buffer));
  spinner.start_kernel(kid);

  // wait for completion
  std::cout << "wait for completion" << std::endl;
  // RT_CHECK(vx_ready_wait(device, VX_MAX_TIMEOUT));
  spinner.wait_kernel(kid, VX_MAX_TIMEOUT);

  // download destination buffer
  std::cout << "download destination buffer" << std::endl;
  // RT_CHECK(vx_copy_from_dev(h_dst.data(), dst_buffer, 0, buf_size));
  espiral::DownloadBuffer dst_download_buf(dst_buf_devaddr, buf_size, h_dst.data());
  spinner.download(kid, dst_download_buf);

  // verify result
  std::cout << "verify result" << std::endl;
  int errors = 0;
  for (uint32_t i = 0; i < num_points; ++i) {
    auto ref = h_src0[i] + h_src1[i];
    auto cur = h_dst[i];
    if (!Comparator<TYPE>::compare(cur, ref, i, errors)) {
      ++errors;
    }
  }

  // cleanup
  std::cout << "cleanup" << std::endl;
  spinner.free_kernel(kid);
  cleanup();

  if (errors != 0) {
    std::cout << "Found " << std::dec << errors << " errors!" << std::endl;
    std::cout << "FAILED!" << std::endl;
    return errors;
  }

  std::cout << "PASSED!" << std::endl;

  return 0;
}