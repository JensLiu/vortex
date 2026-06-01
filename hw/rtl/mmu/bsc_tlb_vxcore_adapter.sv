`include "VX_define.vh"

module bsc_tlb_vxcore_adapter #(
    parameter int unsigned NUM_ITLB_PORTS = 1,
    parameter int unsigned NUM_DTLB_PORTS = `NUM_LSU_BLOCKS * `NUM_LSU_LANES
) (
    // =============== BSC MMU Interface ===============
    // iTLB Interface
    output mmu_pkg::core_tlb_comm_t core_itlb_comm[NUM_ITLB_PORTS],
    input  mmu_pkg::tlb_core_comm_t itlb_core_comm[NUM_ITLB_PORTS],
    // dTLB Interface
    output mmu_pkg::core_tlb_comm_t core_dtlb_comm[NUM_DTLB_PORTS],
    input  mmu_pkg::tlb_core_comm_t dtlb_core_comm[NUM_DTLB_PORTS],

    // =============== Core Interface ===============
    // Translation Interface
    VX_addr_trans_if.slave itlb_if[NUM_ITLB_PORTS],
    VX_addr_trans_if.slave dtlb_if[NUM_DTLB_PORTS],

    // =============== CSR Interface ================
    // NOTE: satp is currently unused here; it drives bsc_mmu's csr_ptw_comm_t in VX_core
    VX_csr_mmu_if.slave csr_mmu_if
);

    // ---------------------------------------------------------------------------
    // Address translation helpers
    // ---------------------------------------------------------------------------

    // Extract virtual page number from a full VA.
    // BSC req.vpn is [VPN_SIZE:0] = 28 bits (SV39-sized).
    // Vortex SV32 VPN = VA[31:12] = 20 bits; SV39 VPN = VA[38:12] = 27 bits.
    // Upper bits are zero-padded via a local variable initialised to '0.
    /* verilator lint_off UNUSEDSIGNAL */  // in case VPN_SIZE+1 is not a multiple of 4
    function automatic logic [mmu_pkg::VPN_SIZE:0] va2vpn(input logic [`XLEN-1:0] va);
        logic [mmu_pkg::VPN_SIZE:0] vpn;
        vpn                                = '0;
        vpn[`XLEN-`MEM_PAGE_LOG2_SIZE-1:0] = va[`XLEN-1:`MEM_PAGE_LOG2_SIZE];
        return vpn;
    endfunction

    // Extract the 12-bit page offset from a VA.
    function automatic logic [`MEM_PAGE_LOG2_SIZE-1:0] va2off(input logic [`XLEN-1:0] va);
        return va[`MEM_PAGE_LOG2_SIZE-1:0];
    endfunction

    // Reconstruct a physical address from the BSC PPN response and the page offset.
    // BSC PPN is PPN_SIZE=44 bits; Vortex only uses the low
    // (MEM_ADDR_WIDTH - MEM_PAGE_LOG2_SIZE) bits (20 bits for XLEN=32, 36 for XLEN=64).
    function automatic logic [`MEM_ADDR_WIDTH-1:0] ppn2pa(
        input logic [mmu_pkg::PPN_SIZE-1:0] ppn, input logic [`MEM_PAGE_LOG2_SIZE-1:0] offset);
        return {ppn[`MEM_ADDR_WIDTH-`MEM_PAGE_LOG2_SIZE-1:0], offset};
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // vm_enable: SATP MODE bit controls whether address translation is active.
    // SV32 (XLEN=32): satp[31]=1 enables paging. SV39/SV48 (XLEN=64): satp[63]!=0.
    // Must be a named wire (not inline in genvar loops) to avoid Verilator issues.
    logic vm_enable;
    assign vm_enable = csr_mmu_if.satp[`XLEN-1];

    // NOTE: Even if there's no TLB request, i.e. core_tlb_comm_t::valid = FALSE
    //       the response is still valid, i.e. tlb_core_comm_t::ready = TRUE See FSM in tlb.sv.
    //       The VX_addr_if interface is synchronous, hence we need to assert ready if there is actually response

    // ---------------------------------------------------------------------------
    // iTLB (one port per core)
    // ---------------------------------------------------------------------------

    for (genvar i = 0; i < NUM_ITLB_PORTS; ++i) begin : g_itlb_if
        assign core_itlb_comm[i].req.valid = itlb_if[i].valid;
        assign core_itlb_comm[i].req.asid = '0;  // GPU: single shared address space
        assign core_itlb_comm[i].req.vpn = va2vpn(itlb_if[i].va);
        assign core_itlb_comm[i].req.passthrough = ~vm_enable;
        assign core_itlb_comm[i].req.instruction = 1;  // instruction access
        assign core_itlb_comm[i].req.store = 0;  // not a store access
        assign core_itlb_comm[i].priv_lvl = 0;  // always user mode for the GPU
        assign core_itlb_comm[i].vm_enable = vm_enable;

        assign itlb_if[i].pa = ppn2pa(itlb_core_comm[i].resp.ppn, va2off(itlb_if[i].va));
        assign itlb_if[i].ready = itlb_if[i].valid && !itlb_core_comm[i].resp.miss;
        assign itlb_if[i].fault = itlb_if[i].valid
                 && !itlb_core_comm[i].resp.miss
                 && itlb_core_comm[i].resp.xcpt.fetch;
    end

    // ---------------------------------------------------------------------------
    // dTLB (one port per LSU lane)
    // ---------------------------------------------------------------------------

    for (genvar i = 0; i < NUM_DTLB_PORTS; ++i) begin : g_dtlb_if
        assign core_dtlb_comm[i].req.valid = dtlb_if[i].valid;
        assign core_dtlb_comm[i].req.asid = '0;  // GPU: single shared address space
        assign core_dtlb_comm[i].req.vpn = va2vpn(dtlb_if[i].va);
        assign core_dtlb_comm[i].req.passthrough = ~vm_enable;
        assign core_dtlb_comm[i].req.instruction = 0;  // data access
        assign core_dtlb_comm[i].req.store = dtlb_if[i].store;
        assign core_dtlb_comm[i].priv_lvl = 0;  // always user mode for the GPU
        assign core_dtlb_comm[i].vm_enable = vm_enable;

        assign dtlb_if[i].pa = ppn2pa(dtlb_core_comm[i].resp.ppn, va2off(dtlb_if[i].va));
        assign dtlb_if[i].ready = dtlb_if[i].valid && !dtlb_core_comm[i].resp.miss;
        assign dtlb_if[i].fault = dtlb_if[i].valid
                 && !dtlb_core_comm[i].resp.miss
                 && (dtlb_core_comm[i].resp.xcpt.load
                 || dtlb_core_comm[i].resp.xcpt.store);
    end

endmodule
