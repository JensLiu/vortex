`include "bsc_mmu/includes/mmu_pkg.sv"
`include "../VX_gpu_pkg.sv"
`include "VX_define.vh"

module bsc_mmu_vortex_cache_adapter
  import mmu_pkg::*;
  import VX_gpu_pkg::*;
#(
    parameter int unsigned NUM_PTWS = 1,
    parameter int unsigned DATA_SIZE = 8,
    parameter int unsigned MEM_ADDR_WIDTH = `MEM_ADDR_WIDTH,
    parameter int unsigned OFFSET_BITS = `CLOG2(DATA_SIZE),
    parameter int unsigned ADDR_WIDTH = MEM_ADDR_WIDTH - OFFSET_BITS
) (
    output dmem_ptw_comm_t      dmem_ptw_comm_o[NUM_PTWS],
    input  ptw_dmem_comm_t      ptw_dmem_comm_i[NUM_PTWS],
    VX_mem_bus_if.master        mem_bus_if     [NUM_PTWS]
);

    localparam int unsigned DCACHE_WORD_SIZE	= `LSU_LINE_SIZE;
    localparam int unsigned DCACHE_ADDR_WIDTH	= (`MEM_ADDR_WIDTH - `CLOG2(DCACHE_WORD_SIZE));

  // NOTE: in the current implementation of MMU, we have in the request
  // - phys = 1: always physical address
  // - cmd = M_XRD: always read -> This is good because Vortex doesn't have atomic operations
  // - typ = MT_D: always data
  // - addr: virtual address
  // - data: data to be written
  // - byteen: byte enable
  // for (genvar i = 0; i < NUM_PTWS; i++) begin : g_ptw
  // address alignment
  logic [MEM_ADDR_WIDTH-1:0] addr;
  logic [ADDR_WIDTH-1:0] aligned_addr;
  logic [OFFSET_BITS-1:0] offset;

  always_comb begin
    addr = ptw_dmem_comm_i[0].req.addr;
    aligned_addr = ADDR_WIDTH'(addr >> $clog2(DATA_SIZE));
    offset = addr[OFFSET_BITS-1:0];
  end
  // NOTE: The MMU expect synchronous response

  // Request: PTW → dcache
  // NOTE: we don't need to check the offset because Vortex doesn't have atomic operations
  always_comb begin
    mem_bus_if[0].req_valid = ptw_dmem_comm_i[0].req.valid;
    mem_bus_if[0].req_data.rw = 0;
    mem_bus_if[0].req_data.addr = aligned_addr;
    mem_bus_if[0].req_data.byteen = '1;
    mem_bus_if[0].req_data.data = '0;
    mem_bus_if[0].req_data.flags = '0;  // < global memory access
    mem_bus_if[0].req_data.tag = {
      UUID_WIDTH'(0),
      MEM_CLIENT_ID_WIDTH'(MEM_CLIENT_PTW),  // < PTW Client ID
      (DCACHE_TAG_ID_BITS - MEM_CLIENT_ID_WIDTH)'(0)  // < Same layout as the LSU memory request tag
    };
  end

  // Response: dcache → PTW
  always_comb begin
    dmem_ptw_comm_o[0].dmem_ready      = mem_bus_if[0].req_ready;
    dmem_ptw_comm_o[0].resp.valid      = mem_bus_if[0].rsp_valid;
    dmem_ptw_comm_o[0].resp.nack       = '0;
    dmem_ptw_comm_o[0].resp.addr       = '0;
    dmem_ptw_comm_o[0].resp.tag_addr   = '0;
    dmem_ptw_comm_o[0].resp.cmd        = '0;
    dmem_ptw_comm_o[0].resp.typ        = '0;
    dmem_ptw_comm_o[0].resp.replay     = '0;
    dmem_ptw_comm_o[0].resp.has_data   = '0;
    dmem_ptw_comm_o[0].resp.data_subw  = '0;
    dmem_ptw_comm_o[0].resp.store_data = '0;
    dmem_ptw_comm_o[0].resp.rnvalid    = '0;
    dmem_ptw_comm_o[0].resp.rnext      = '0;
    dmem_ptw_comm_o[0].resp.xcpt_ma_ld = '0;
    dmem_ptw_comm_o[0].resp.xcpt_ma_st = '0;
    dmem_ptw_comm_o[0].resp.xcpt_pf_ld = '0;
    dmem_ptw_comm_o[0].resp.xcpt_pf_st = '0;
    dmem_ptw_comm_o[0].resp.ordered    = '0;
    dmem_ptw_comm_o[0].resp.data       = mem_bus_if[0].rsp_data.data[];
    mem_bus_if[0].rsp_ready            = 1'b1;  // < The MMU always accept the response
  end


endmodule
