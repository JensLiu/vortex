`include "bsc_mmu/includes/mmu_pkg.sv"
`include "VX_gpu_pkg.sv"
`include "VX_define.vh"

module VX_core_bsc_tlb_adapter
  import mmu_pkg::*;
  import VX_gpu_pkg::*;
#(
    parameter int unsigned NUM_DTLB_PORTS = `NUM_LSU_BLOCKS * `NUM_LSU_LANES
) (
    // =============== BSC MMU Interface ===============
    // iTLB Interface
    output cache_tlb_comm_t core_itlb_comm,
    input  tlb_cache_comm_t itlb_core_comm,
    // dTLB Interface
    output cache_tlb_comm_t core_dtlb_comm  [NUM_DTLB_PORTS],
    input  tlb_cache_comm_t dtlb_core_comm  [NUM_DTLB_PORTS],

    // =============== Core Interface ===============
    // Translation Interface
    VX_addr_translation_if.slave itlb_if,
    VX_addr_translation_if.slave dtlb_if[NUM_DTLB_PORTS]
    // TODO: CSR Interface (pass satp, exception, etc.)
);

  assign core_itlb_comm.req.valid = itlb_if.valid;
  assign core_itlb_comm.req.asid = itlb_if.asid;
  assign core_itlb_comm.req.vpn = itlb_if.vpn;
  assign core_itlb_comm.req.passthrough = 0;
  assign core_itlb_comm.req.instruction = 1;
  assign core_itlb_comm.req.store = 0;  // < instruction fetch only
  assign core_itlb_comm.priv_lvl = 0;  // < always user mode for the GPU
  assign core_itlb_comm.vm_enable = 1;  // < always enabled for the GPU

  assign itlb_if.ppn = itlb_core_comm.resp.ppn;
  assign itlb_if.ready = itlb_core_comm.tlb_ready;
  // TODO: handle exceptions

  for (genvar i = 0; i < NUM_DTLB_PORTS; ++i) begin : g_dtlb_if
    assign core_dtlb_comm[i].req.valid = dtlb_if[i].valid;
    assign core_dtlb_comm[i].req.asid = dtlb_if[i].asid;
    assign core_dtlb_comm[i].req.vpn = dtlb_if[i].vpn;
    assign core_dtlb_comm[i].req.passthrough = 0;
    assign core_dtlb_comm[i].req.instruction = 1;
    assign core_dtlb_comm[i].req.store = dtlb_if[i].store;
    assign core_dtlb_comm[i].priv_lvl = 0;  // < always user mode for the GPU
    assign core_dtlb_comm[i].vm_enable = 1;  // < always enabled for the GPU

    assign dtlb_if[i].ppn = dtlb_core_comm[i].resp.ppn;
    assign dtlb_if[i].ready = dtlb_core_comm[i].tlb_ready;
  end

endmodule
