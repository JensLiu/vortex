`include "VX_define.vh"

module VX_cache_req_translator
  import VX_gpu_pkg::*;
#(
    parameter int unsigned XLEN = `XLEN
) (
    VX_mem_bus_if.slave virt_req,
    VX_mem_bus_if.master phys_req,
    VX_addr_trans_if.master addr_trans
);
  localparam int unsigned TRANS_ADDR_WIDTH = XLEN; // TODO: remove unused lsbs
  localparam int unsigned REQ_ADDR_WIDTH = $bits(virt_req.req_data.addr);
  localparam int unsigned PADDING_WIDTH = TRANS_ADDR_WIDTH - REQ_ADDR_WIDTH;

  // VX_mem_bus_if addresses are word/line addresses (DATA_SIZE granularity).
  // MMU expects a byte address, so we append the lower "page offset" zeros.
  assign addr_trans.va    = {virt_req.req_data.addr, {PADDING_WIDTH{1'b0}}};
  assign addr_trans.valid = virt_req.req_valid;
  assign addr_trans.store = virt_req.req_data.rw;

  // Only forward the cache request once the translation is ready (hit / bypass).
  assign phys_req.req_valid = virt_req.req_valid && addr_trans.ready;
  assign virt_req.req_ready = phys_req.req_ready && addr_trans.ready;

  always_comb begin
    phys_req.req_data = virt_req.req_data;
    // Convert translated byte address back into VX_mem_bus_if address granularity.
    phys_req.req_data.addr = addr_trans.pa[TRANS_ADDR_WIDTH-1:PADDING_WIDTH];
  end

endmodule
