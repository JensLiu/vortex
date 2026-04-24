`include "VX_config.vh"

module VX_bsc_mmu #(
    parameter int unsigned NUM_CORES             = 1,
    parameter int unsigned NUM_CHANNELS_PER_CORE = 1,
    // One dTLB port per translated data request (PTW requests are already physical).
    parameter int unsigned NUM_DTLB_PORTS        = NUM_CORES * NUM_CHANNELS_PER_CORE,
    parameter int unsigned NUM_PTW_PORTS         = 1
) (
    input logic clk,
    input logic reset,

    VX_addr_trans_if.slave iaddr_if     [     NUM_CORES],
    VX_addr_trans_if.slave daddr_if     [NUM_DTLB_PORTS],
    VX_csr_mmu_if.slave    csr_mmu_if,
    VX_mem_bus_if.master   dcache_bus_if[ NUM_PTW_PORTS]
);

    // iTLB Interface (one port per core)
    mmu_pkg::cache_tlb_comm_t icache_itlb_comm_i[     NUM_CORES];
    mmu_pkg::tlb_cache_comm_t itlb_icache_comm_o[     NUM_CORES];
    // dTLB interface
    mmu_pkg::cache_tlb_comm_t core_dtlb_comm_i  [NUM_DTLB_PORTS];
    mmu_pkg::tlb_cache_comm_t dtlb_core_comm_o  [NUM_DTLB_PORTS];
    // CSR Interface
    mmu_pkg::csr_ptw_comm_t   csr_ptw_comm_i;
    // TODO: currently only support RV32
    assign csr_ptw_comm_i.satp    = {{(64 - `XLEN) {1'b0}}, csr_mmu_if.satp};  // < zero-extend satp
    assign csr_ptw_comm_i.flush   = csr_mmu_if.flush_tlb;
    assign csr_ptw_comm_i.mstatus = mmu_pkg::csr_mstatus_t'(csr_mmu_if.mstatus);

    // PTW - Memory Interface
    mmu_pkg::ptw_dmem_comm_t ptw_dmem_comm_o[NUM_PTW_PORTS];
    mmu_pkg::dmem_ptw_comm_t dmem_ptw_comm_i[NUM_PTW_PORTS];

    bsc_mmu #(
        .NUM_DTLB_PORTS(NUM_DTLB_PORTS),
        .NUM_CORES     (NUM_CORES),
        .XLEN          (`XLEN)
    ) bsc_mmu_inst (
        .clk_i             (clk),
        .rstn_i            (~reset),
        .icache_itlb_comm_i(icache_itlb_comm_i),
        .itlb_icache_comm_o(itlb_icache_comm_o),
        .core_dtlb_comm_i  (core_dtlb_comm_i),
        .dtlb_core_comm_o  (dtlb_core_comm_o),
        .csr_ptw_comm_i    (csr_ptw_comm_i),
        // currently, we only support 1 PTW port
        .ptw_dmem_comm_o   (ptw_dmem_comm_o[0]),
        .dmem_ptw_comm_i   (dmem_ptw_comm_i[0])
    );

    bsc_tlb_vxcore_adapter #(
        .NUM_ITLB_PORTS(NUM_CORES),
        .NUM_DTLB_PORTS(NUM_DTLB_PORTS)
    ) tlb_adapter (
        .core_itlb_comm(icache_itlb_comm_i),
        .itlb_core_comm(itlb_icache_comm_o),
        .core_dtlb_comm(core_dtlb_comm_i),
        .dtlb_core_comm(dtlb_core_comm_o),
        .itlb_if       (iaddr_if),
        .dtlb_if       (daddr_if),
        .csr_mmu_if    (csr_mmu_if)
    );

    bsc_ptw_vxdcache_adapter #(
        .NUM_PTWS(NUM_PTW_PORTS)
    ) ptw_adapter (
        .clk            (clk),
        .reset          (reset),
        .dmem_ptw_comm_o(dmem_ptw_comm_i),
        .ptw_dmem_comm_i(ptw_dmem_comm_o),
        .mem_bus_if     (dcache_bus_if)
    );

    always @(posedge clk) begin
        // if (iaddr_if.valid) begin
        //   `TRACE(0, ("%t: %s iTLB req: va=%08x, vm_en=%b\n", $time, INSTANCE_ID, iaddr_if.va, icache_itlb_comm_i.vm_enable));
        //   if (iaddr_if.ready) begin
        //     `TRACE(0, ("%t: %s iTLB rsp: va=%08x pa=%08x\n", $time, INSTANCE_ID, iaddr_if.va, iaddr_if.pa));
        //   end else begin
        //     `TRACE(0, ("%t: %s iTLB waiting for response\n", $time, INSTANCE_ID));
        //   end
        // end
        // if (daddr_if[0].valid) begin
        //   `TRACE(0, ("%t: %s dTLB req: va=%08x, vm_en=%b\n", $time, INSTANCE_ID, daddr_if[0].va, core_dtlb_comm_i[0].vm_enable));
        //   if (daddr_if[0].ready) begin
        //     `TRACE(0, ("%t: %s dTLB rsp: va=%08x pa=%08x\n", $time, INSTANCE_ID, daddr_if[0].va, daddr_if[0].pa));
        //   end else begin
        //     `TRACE(0, ("%t: %s dTLB waiting for response\n", $time, INSTANCE_ID));
        //   end
        // end
        //    if (dcache_bus_if[0].req_valid) begin
        //        `TRACE(0,
        //               ("%t: %s PTW side request: valid=%b addr=%08x cmd=%b typ=%b kill=%b phys=%b data=%08x\n", $time, INSTANCE_ID, ptw_dmem_comm_o[0].req.valid, ptw_dmem_comm_o[0].req.addr, ptw_dmem_comm_o[0].req.cmd, ptw_dmem_comm_o[0].req.typ, ptw_dmem_comm_o[0].req.kill, ptw_dmem_comm_o[0].req.phys, ptw_dmem_comm_o[0].req.data));
        //        `TRACE(0,
        //               ("%t: %s PTW req initiated: tag=%08x pgtbl_pa=%08x\n", $time, INSTANCE_ID, dcache_bus_if[0].req_data.tag, dcache_bus_if[0].req_data.addr));
        //        if (dcache_bus_if[0].req_ready) begin
        //            `TRACE(0,
        //                   ("%t: %s PTW req queued: tag=%08x pgtbl_pa=%08x\n", $time, INSTANCE_ID, dcache_bus_if[0].req_data.tag, dcache_bus_if[0].req_data.addr));
        //        end
        //    end
        //    if (dcache_bus_if[0].rsp_valid) begin
        //        `TRACE(0,
        //               ("%t: %s PTW rsp: tag=%08x pte=%08x\n", $time, INSTANCE_ID, dcache_bus_if[0].rsp_data.tag, dcache_bus_if[0].rsp_data.data));
        //    end
    end

endmodule
