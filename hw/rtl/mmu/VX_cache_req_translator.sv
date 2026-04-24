`include "VX_define.vh"

module VX_cache_req_translator
  import VX_gpu_pkg::*;
#(
    parameter int unsigned DATA_SIZE = DCACHE_WORD_SIZE,
    parameter int unsigned MEM_ADDR_WIDTH = `MEM_ADDR_WIDTH,
    parameter int unsigned ADDR_WIDTH = MEM_ADDR_WIDTH - `CLOG2(DATA_SIZE)
) (
    VX_mem_bus_if.slave virt_req,
    VX_mem_bus_if.master phys_req,
    VX_addr_trans_if.master addr_trans
);
  assign addr_trans.va = {
    virt_req.req_data.addr, {`CLOG2(DATA_SIZE) {1'b0}}
  };  // < zero-extend page offset
  assign addr_trans.valid = virt_req.req_valid;

  assign phys_req.req_valid = addr_trans.ready;
  assign virt_req.req_ready = phys_req.req_ready;

  always_comb begin
    phys_req.req_data = virt_req.req_data;
    phys_req.req_data.addr = addr_trans.pa[MEM_ADDR_WIDTH-1:
    `CLOG2(DATA_SIZE)
    ];  // < truncate page offset
  end

endmodule
