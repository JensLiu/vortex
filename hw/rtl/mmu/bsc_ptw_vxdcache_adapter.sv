`include "VX_define.vh"

module bsc_ptw_vxdcache_adapter #(
    parameter int unsigned NUM_PTWS = 1
) (
    input logic clk,
    output mmu_pkg::dmem_ptw_comm_t dmem_ptw_comm_o[NUM_PTWS],
    input mmu_pkg::ptw_dmem_comm_t ptw_dmem_comm_i[NUM_PTWS],

    VX_mem_bus_if.master mem_bus_if[NUM_PTWS]
);
  // the adapter assumes atomic request/response
  //  - during PTW request, the address must be stable until the response is received
  //  - the response must be consumed immediately by the PTW (i.e., the adapter won't buffer the response for the next request)
  //  - the memory response must be corresponsedingly aligned with the request

  // localparam int unsigned UUID_WIDTH = VX_gpu_pkg::UUID_WIDTH;
  // localparam int unsigned DCACHE_TAG_ID_BITS = VX_gpu_pkg::DCACHE_TAG_ID_BITS;
  // localparam int unsigned MEM_CLIENT_ID_WIDTH = VX_gpu_pkg::MEM_CLIENT_ID_WIDTH;
  localparam int unsigned DCACHE_WORD_SIZE = VX_gpu_pkg::DCACHE_WORD_SIZE;
  localparam int unsigned DCACHE_ADDR_WIDTH = VX_gpu_pkg::DCACHE_ADDR_WIDTH;
  // Byte-offset bits within one dcache word (= log2 of word size in bytes).
  localparam int unsigned DCACHE_ADDR_OFFSET_BITS = $clog2(DCACHE_WORD_SIZE);
  // dmem_ptw_resp_t::data is always 64 bits (BSC MMU is hardcoded SV39).
  // PTE width in the host ISA: XLEN bits (32 for SV32, 64 for SV39).
  localparam int unsigned PTW_DATA_WIDTH = 64;  // < see dmem_ptw_resp_t::data
  // in the mmu, pte_addr is declared as [SIZE_VADDR:0], is this a bug?
  // localparam int unsigned PTW_ADDR_WIDTH = mmu_pkg::SIZE_VADDR + 1;  // < see ptw_dmem_comm_t::addr

  // NOTE: in the current implementation of MMU, we have in the request
  // - phys = 1: always physical address
  // - cmd = M_XRD: always read -> This is good because Vortex doesn't have atomic operations
  // - typ = MT_D: always data
  // - addr: virtual address
  // - data: data to be written
  // - byteen: byte enable

  // Word address sent to the dcache (DCACHE_ADDR_WIDTH bits).
  // DCACHE_ADDR_WIDTH is already a word-address width (byte offset stripped).
  // Extract from the PTW byte address by dropping the low DCACHE_ADDR_OFFSET_BITS bits:
  //   word_addr = byte_addr[DCACHE_ADDR_WIDTH+DCACHE_ADDR_OFFSET_BITS-1 : DCACHE_ADDR_OFFSET_BITS]
  //             = byte_addr[MEM_ADDR_WIDTH-1 : log2(DCACHE_WORD_SIZE)]
  logic [DCACHE_ADDR_WIDTH-1:0] aligned_addr;
  // Byte offset within the dcache word (selects which PTE inside the cache word).
  logic [DCACHE_ADDR_OFFSET_BITS-1:0] word_offset;

  always_comb begin
    // Strip low DCACHE_ADDR_OFFSET_BITS (byte offset within word) to get word address.
    aligned_addr = DCACHE_ADDR_WIDTH'(ptw_dmem_comm_i[0].req.addr >> DCACHE_ADDR_OFFSET_BITS);
    word_offset  = ptw_dmem_comm_i[0].req.addr[DCACHE_ADDR_OFFSET_BITS-1:0];
  end
  // NOTE: The MMU expect synchronous response

  // Request: PTW → dcache
  // NOTE: we don't need to check the offset because Vortex doesn't have atomic operations
  always_ff @(posedge clk) begin
    mem_bus_if[0].req_valid <= ptw_dmem_comm_i[0].req.valid;
    mem_bus_if[0].req_data.rw <= 0;
    mem_bus_if[0].req_data.addr <= aligned_addr;
    mem_bus_if[0].req_data.byteen <= '1;
    mem_bus_if[0].req_data.data <= '0;
    mem_bus_if[0].req_data.flags <= '0;  // < global memory access
    // Tag is all zeros: UUID=0 (debug only), ClientID=0 (injected by VX_dcache_req_hub), rest=0.
    mem_bus_if[0].req_data.tag.uuid <= '0;
    mem_bus_if[0].req_data.tag.value <= '0;
  end

  // Response: dcache → PTW
  always_ff @(posedge clk) begin
    dmem_ptw_comm_o[0].dmem_ready <= mem_bus_if[0].req_ready;
    dmem_ptw_comm_o[0].resp.valid <= mem_bus_if[0].rsp_valid;
    dmem_ptw_comm_o[0].resp.nack <= '0;
    dmem_ptw_comm_o[0].resp.addr <= '0;
    dmem_ptw_comm_o[0].resp.tag_addr <= '0;
    dmem_ptw_comm_o[0].resp.cmd <= '0;
    dmem_ptw_comm_o[0].resp.typ <= '0;
    dmem_ptw_comm_o[0].resp.replay <= '0;
    dmem_ptw_comm_o[0].resp.has_data <= '0;
    dmem_ptw_comm_o[0].resp.data_subw <= '0;
    dmem_ptw_comm_o[0].resp.store_data <= '0;
    dmem_ptw_comm_o[0].resp.rnvalid <= '0;
    dmem_ptw_comm_o[0].resp.rnext <= '0;
    dmem_ptw_comm_o[0].resp.xcpt_ma_ld <= '0;
    dmem_ptw_comm_o[0].resp.xcpt_ma_st <= '0;
    dmem_ptw_comm_o[0].resp.xcpt_pf_ld <= '0;
    dmem_ptw_comm_o[0].resp.xcpt_pf_st <= '0;
    dmem_ptw_comm_o[0].resp.ordered <= '0;
    // Extract one PTE (XLEN bits) at the byte offset within the cache word,
    // then zero-extend to PTW_DATA_WIDTH (64b). For SV32: 32b→64b; SV39: 64b→64b.
    dmem_ptw_comm_o[0].resp.data <=
        PTW_DATA_WIDTH'(mem_bus_if[0].rsp_data.data[word_offset*8+:`XLEN]);
    mem_bus_if[0].rsp_ready <= 1'b1;  // < The MMU always accept the response
  end


endmodule
