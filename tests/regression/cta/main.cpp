#include <iostream>
#include <unistd.h>
#include <string.h>
#include <vector>
#include <vortex.h>
#include "common.h"
#include "download_buffer.h"
#include "espiral.h"

template <typename Type>
class Comparator {};

template <>
class Comparator<int> {
public:
  static const char* type_str() {
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

const char* kernel_file = "kernel.vxbin";
uint32_t grd_x = 4;
uint32_t grd_y = 4;
uint32_t grd_z = 1;
uint32_t blk_x = 1;
uint32_t blk_y = 1;
uint32_t blk_z = 1;

kernel_arg_t kernel_arg = {};

static void show_usage() {
   std::cout << "Vortex Test." << std::endl;
   std::cout << "Usage: [-k: kernel] [-x grid.x] [-y grid.y] [-z grid.z] [-a block.x] [-b block.y] [-c block.z] [-h: help]" << std::endl;
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "k:x:y:z:a:b:c:h")) != -1) {
    switch (c) {
    case 'a':
      blk_x = atoi(optarg);
      break;
    case 'b':
      blk_y = atoi(optarg);
      break;
    case 'c':
      blk_z = atoi(optarg);
      break;
    case 'x':
      grd_x = atoi(optarg);
      break;
    case 'y':
      grd_y = atoi(optarg);
      break;
    case 'z':
      grd_z = atoi(optarg);
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

int main(int argc, char *argv[]) {
  // parse command arguments
  parse_args(argc, argv);

  std::srand(50);

  // open device connection
  std::cout << "open device connection" << std::endl;
  auto espiral = espiral::Espiral(espiral::backend::VERILATOR);
  const auto kid = espiral.allocate_kernel(kernel_file);

  uint32_t cta_size = blk_x * blk_y * blk_z;
  uint32_t cta_count = grd_x * grd_y * grd_z;
  uint32_t total_threads  = cta_count * cta_size;
  uint32_t src_buf_size = cta_size * sizeof(int);
  uint32_t dst_buf_size = total_threads * sizeof(int);

  std::cout << "CTA size: " << cta_size << std::endl;
  std::cout << "number of CTAs: " << cta_count << std::endl;
  std::cout << "number of threads: " << total_threads << std::endl;
  std::cout << "source buffer size: " << src_buf_size << " bytes" << std::endl;
  std::cout << "destination buffer size: " << dst_buf_size << " bytes" << std::endl;

  kernel_arg.block_dim[0] = blk_x;
  kernel_arg.block_dim[1] = blk_y;
  kernel_arg.block_dim[2] = blk_z;
  kernel_arg.grid_dim[0]  = grd_x;
  kernel_arg.grid_dim[1]  = grd_y;
  kernel_arg.grid_dim[2]  = grd_z;

  // allocate device memory
  std::cout << "allocate device memory" << std::endl;
  auto src_buffer = espiral.allocate_upload_buffer(kid, src_buf_size);
  kernel_arg.src_addr = src_buffer.get_va();
  kernel_arg.dst_addr = espiral.allocate_dev_buffer(kid, dst_buf_size);

  std::cout << "src_dst=0x" << std::hex << kernel_arg.src_addr << std::endl;
  std::cout << "dev_dst=0x" << std::hex << kernel_arg.dst_addr << std::endl;

  // allocate host buffers
  std::cout << "allocate host buffers" << std::endl;
  std::vector<int> h_src(cta_size);
  std::vector<int> h_dst(total_threads);

  for (uint32_t i = 0; i < cta_size; ++i) {
    h_src[i] = Comparator<int>::generate();
  }

  // upload source buffer0
  std::cout << "upload source buffer0" << std::endl;
  src_buffer.set_content(h_src.data(), src_buf_size);
  espiral.upload(kid, src_buffer);

  // upload kernel argument
  std::cout << "upload kernel argument" << std::endl;
  espiral.upload_args(kid, &kernel_arg);
  
  // start device
  std::cout << "start device" << std::endl;
  espiral.start_kernel(kid);
  
  // wait for completion
  std::cout << "wait for completion" << std::endl;
  espiral.wait_kernel(kid, VX_MAX_TIMEOUT);

  // download destination buffer
  std::cout << "download destination buffer" << std::endl;
  espiral::DownloadBuffer dst_buf(kernel_arg.dst_addr, dst_buf_size, h_dst.data());
  espiral.download(kid, dst_buf);

  // verify result
  std::cout << "verify result" << std::endl;
  int errors = 0;
  for (uint32_t i = 0; i < total_threads; ++i) {
    auto ref = i + h_src[i % cta_size];
    auto cur = h_dst[i];
    if (!Comparator<int>::compare(cur, ref, i, errors)) {
      ++errors;
    }
  }

  // cleanup
  std::cout << "cleanup" << std::endl;
  espiral.free_kernel(kid);

  if (errors != 0) {
    std::cout << "Found " << std::dec << errors << " errors!" << std::endl;
    std::cout << "FAILED!" << std::endl;
    return 1;
  }

  std::cout << "PASSED!" << std::endl;

  return 0;
}