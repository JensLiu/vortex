#include <iostream>
#include <unistd.h>
#include <string.h>
#include <vector>
#include <chrono>
#include <vortex.h>
#include <cmath>
#include "common.h"
#include "espiral.h"

#define FLOAT_ULP 6

///////////////////////////////////////////////////////////////////////////////

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

template <>
class Comparator<float> {
public:
  static const char* type_str() {
    return "float";
  }
  static float generate() {
    return static_cast<float>(rand()) / RAND_MAX;
  }
  static bool compare(float a, float b, int index, int errors) {
    union fi_t { float f; int32_t i; };
    fi_t fa, fb;
    fa.f = a;
    fb.f = b;
    auto d = std::abs(fa.i - fb.i);
    if (d > FLOAT_ULP) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%f, actual=%f\n", index, b, a);
      }
      return false;
    }
    return true;
  }
};

static void convolution_cpu(TYPE *O, TYPE *I, TYPE *W, int32_t width, int32_t height) {
  int paddedWidth = width + 2;
  for (int32_t y = 0; y < height; ++y) {
    for (int32_t x = 0; x < width; ++x) {
      int paddedY = y + 1;
      int paddedX = x + 1;
      TYPE sum(0);
      for (int32_t ky = -1; ky <= 1; ++ky) {
        for (int32_t kx = -1; kx <= 1; ++kx) {
          int32_t iy = paddedY + ky;
          int32_t ix = paddedX + kx;
          TYPE value = I[iy * paddedWidth + ix];
          TYPE weight = W[(ky + 1) * 3 + (kx + 1)];
          sum += value * weight;
        }
      }
      O[y * width + x] = sum;
    }
  }
}

const char* kernel_file = "kernel.vxbin";
int size = 32;
bool use_lmem = false;

vx_device_h device = nullptr;
vx_buffer_h I_buffer = nullptr;
vx_buffer_h W_buffer = nullptr;
vx_buffer_h O_buffer = nullptr;
vx_buffer_h krnl_buffer = nullptr;
vx_buffer_h args_buffer = nullptr;
kernel_arg_t kernel_arg = {};

static void show_usage() {
   std::cout << "Vortex Test." << std::endl;
   std::cout << "Usage: [-k kernel] [-l: local memory] [-n size] [-h|?: help]" << std::endl;
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:k:lh")) != -1) {
    switch (c) {
    case 'n':
      size = atoi(optarg);
      break;
    case 'l':
      use_lmem = true;
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
    vx_mem_free(I_buffer);
    vx_mem_free(W_buffer);
    vx_mem_free(O_buffer);
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
  std::cout << "open device connection" << std::endl;
  espiral::Espiral espiral(espiral::backend::SIMX);
  const auto kid = espiral.allocate_kernel(kernel_file);

  std::cout << "data type: " << Comparator<TYPE>::type_str() << std::endl;
  std::cout << "matrix size: " << size << "x" << size << std::endl;

  kernel_arg.grid_dim[0] = size;
  kernel_arg.grid_dim[1] = size;
  kernel_arg.width = size;
  kernel_arg.use_lmem = use_lmem;

  uint32_t o_points = size * size;
  uint32_t i_points = (size+2) * (size+2);
  uint32_t w_points = 3 * 3;

  // allocate device memory
  std::cout << "allocate device memory" << std::endl;
  size_t i_nbytes = i_points * sizeof(TYPE);
  size_t w_nbytes = w_points * sizeof(TYPE);
  size_t o_nbytes = o_points * sizeof(TYPE);
  auto src0_buf = espiral.allocate_upload_buffer(kid, i_nbytes);
  auto src1_buf = espiral.allocate_upload_buffer(kid, w_nbytes);
  const auto dst_buf_devaddr = espiral.allocate_dev_buffer(kid, o_nbytes);
  kernel_arg.I_addr = src0_buf.get_va();
  kernel_arg.W_addr = src1_buf.get_va();
  kernel_arg.O_addr = dst_buf_devaddr;

  if (use_lmem) {
    uint64_t dev_local_mem_size;
    const auto local_mem_size = espiral.get_caps(VX_CAPS_LOCAL_MEM_SIZE).value();
    if (w_nbytes > dev_local_mem_size) {
      std::cout << "Error: Not enough local memory: needed=" << w_nbytes << ", available=" << dev_local_mem_size << std::endl;
      cleanup();
      exit(1);
    }
  }

  std::cout << "dev_argI=0x" << std::hex << kernel_arg.I_addr << std::endl;
  std::cout << "dev_argW=0x" << std::hex << kernel_arg.W_addr << std::endl;
  std::cout << "dev_argO=0x" << std::hex << kernel_arg.O_addr << std::endl;

  // Generate input values
  std::vector<TYPE> h_I(i_points);
  std::vector<TYPE> h_W(w_points);
  std::vector<TYPE> h_O(o_points);
  for (int32_t y = -1; y < size+1; ++y) {
    for (int32_t x = -1; x < size+1; ++x) {
      if (x >= 0 && x < size && y >= 0 && y < size) {
        h_I[(y+1) * (size+2) + (x+1)] = static_cast<TYPE>(rand()) / RAND_MAX;
      } else {
        h_I[(y+1) * (size+2) + (x+1)] = 0;
      }
    }
  }
  for (uint32_t i = 0; i < w_points; ++i) {
    h_W[i] = static_cast<TYPE>(rand()) / RAND_MAX;
  }

  // upload input buffer
  {
    std::cout << "upload source buffer" << std::endl;
    src0_buf.set_content(h_I.data(), i_nbytes);
    espiral.upload(kid, src0_buf);
  }

  // upload weight buffer
  {
    std::cout << "upload weight buffer" << std::endl;
    src1_buf.set_content(h_W.data(), w_nbytes);
    espiral.upload(kid, src1_buf);
  }

  // upload kernel argument
  std::cout << "upload kernel argument" << std::endl;
  espiral.upload_args<kernel_arg_t>(kid, &kernel_arg);

  auto time_start = std::chrono::high_resolution_clock::now();

  // start device
  std::cout << "start device" << std::endl;
  espiral.start_kernel(kid);

  // wait for completion
  std::cout << "wait for completion" << std::endl;
  espiral.wait_kernel(kid, VX_MAX_TIMEOUT);

  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  // download destination buffer
  std::cout << "download destination buffer" << std::endl;
  espiral::DownloadBuffer dst_download_buf(dst_buf_devaddr, o_nbytes, h_O.data());
  espiral.download(kid, dst_download_buf);

  // verify result
  std::cout << "verify result" << std::endl;
  int errors = 0;
  {
    std::vector<TYPE> h_ref(o_points);
    convolution_cpu(h_ref.data(), h_I.data(), h_W.data(), size, size);

    for (uint32_t i = 0; i < h_ref.size(); ++i) {
      auto ref = h_ref[i];
      auto cur = h_O[i];
      if (!Comparator<TYPE>::compare(cur, ref, i, errors)) {
        ++errors;
      }
    }
  }

  // cleanup
  std::cout << "cleanup" << std::endl;
  espiral.free_kernel(kid);
  cleanup();

  if (errors != 0) {
    std::cout << "Found " << std::dec << errors << " errors!" << std::endl;
    std::cout << "FAILED!" << std::endl;
    return errors;
  }

  std::cout << "PASSED!" << std::endl;

  return 0;
}