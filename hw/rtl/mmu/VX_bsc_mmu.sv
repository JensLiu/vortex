`include "VX_config.vh"

module VX_bsc_mmu #(
    parameter int unsigned NUM_CORES             = 1,
    parameter int unsigned NUM_CHANNELS_PER_CORE = 1,
    // One dTLB port per translated data request (PTW requests are already physical).
    parameter int unsigned NUM_DTLB_PORTS        = NUM_CORES * NUM_CHANNELS_PER_CORE,
    parameter int unsigned NUM_ITLB_PORTS        = NUM_CORES,
    parameter int unsigned NUM_PTW_PORTS         = 1
) (
    input logic clk,
    input logic reset,

    VX_addr_trans_if.slave iaddr_if      [NUM_ITLB_PORTS],
    VX_addr_trans_if.slave daddr_if      [NUM_DTLB_PORTS],
    VX_csr_mmu_if.slave    csr_mmu_if,
    VX_mem_bus_if.master   ptw_mem_bus_if[ NUM_PTW_PORTS]
);

    // iTLB Interface (one port per core)
    mmu_pkg::core_tlb_comm_t core_itlb_comm_i[NUM_ITLB_PORTS];
    mmu_pkg::tlb_core_comm_t itlb_core_comm_o[NUM_ITLB_PORTS];
    // dTLB interface
    mmu_pkg::core_tlb_comm_t core_dtlb_comm_i[NUM_DTLB_PORTS];
    mmu_pkg::tlb_core_comm_t dtlb_core_comm_o[NUM_DTLB_PORTS];
    // CSR Interface
    mmu_pkg::csr_ptw_comm_t  csr_ptw_comm_i;
    // TODO: currently only support RV32
    assign csr_ptw_comm_i.satp    = {{(64 - `XLEN) {1'b0}}, csr_mmu_if.satp};  // < zero-extend satp
    assign csr_ptw_comm_i.flush   = csr_mmu_if.flush_tlb;
    assign csr_ptw_comm_i.mstatus = mmu_pkg::csr_mstatus_t'(csr_mmu_if.mstatus);

    // PTW - Memory Interface
    mmu_pkg::ptw_dmem_comm_t ptw_dmem_comm_o[NUM_PTW_PORTS];
    mmu_pkg::dmem_ptw_comm_t dmem_ptw_comm_i[NUM_PTW_PORTS];

    bsc_mmu #(
        .NUM_DTLBS_PER_CORE(NUM_CHANNELS_PER_CORE),
        .NUM_CORES         (NUM_CORES),
        .XLEN              (`XLEN)
    ) bsc_mmu_inst (
        .clk_i           (clk),
        .rstn_i          (~reset),
        .core_itlb_comm_i(core_itlb_comm_i),
        .itlb_core_comm_o(itlb_core_comm_o),
        .core_dtlb_comm_i(core_dtlb_comm_i),
        .dtlb_core_comm_o(dtlb_core_comm_o),
        .csr_ptw_comm_i  (csr_ptw_comm_i),
        // currently, we only support 1 PTW port
        .ptw_dmem_comm_o (ptw_dmem_comm_o[0]),
        .dmem_ptw_comm_i (dmem_ptw_comm_i[0])
    );

    bsc_tlb_vxcore_adapter #(
        .NUM_ITLB_PORTS(NUM_ITLB_PORTS),
        .NUM_DTLB_PORTS(NUM_DTLB_PORTS)
    ) tlb_adapter (
        .core_itlb_comm(core_itlb_comm_i),
        .itlb_core_comm(itlb_core_comm_o),
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
        .mem_bus_if     (ptw_mem_bus_if)
    );

    //    for (genvar i = 0; i < NUM_ITLB_PORTS; i++) begin : g_itlb_trace
    //        localparam int unsigned IDX = i;
    //        always @(posedge clk) begin
    //            if (iaddr_if[IDX].valid) begin
    //                `TRACE(0,
    //                       ("%t: %s Core %0d iTLB req: va=%08x, vm_en=%b\n",
    //     $time, INSTANCE_ID, IDX, iaddr_if[IDX].va,
    //     core_itlb_comm_i[IDX].vm_enable));
    //                if (iaddr_if[IDX].ready) begin
    //                    `TRACE(0,
    //                           ("%t: %s Core %0d iTLB rsp: va=%08x pa=%08x\n",
    //     $time, INSTANCE_ID, IDX, iaddr_if[IDX].va,
    //     iaddr_if[IDX].pa));
    //                end else begin
    //                    `TRACE(0, ("%t: %s Core %0d iTLB waiting for response\n",
    //                           $time, INSTANCE_ID, IDX));
    //                end
    //            end
    //        end
    //    end
    //    for (genvar i = 0; i < NUM_DTLB_PORTS; i++) begin : g_dtlb_trace
    //        localparam int unsigned IDX = i;
    //        always @(posedge clk) begin
    //            if (daddr_if[IDX].valid) begin
    //                `TRACE(0,
    //                       ("%t: %s dTLB req: va=%08x, vm_en=%b\n",
    //     $time, INSTANCE_ID, IDX, daddr_if[IDX].va,
    //     core_dtlb_comm_i[IDX].vm_enable));
    //                if (daddr_if[IDX].ready) begin
    //                    `TRACE(0,
    //                           ("%t: %s dTLB rsp: va=%08x pa=%08x\n",
    //     $time, INSTANCE_ID, daddr_if[IDX].va,
    //     daddr_if[IDX].pa));
    //                end else begin
    //                    `TRACE(0, ("%t: %s dTLB waiting for response\n", $time, INSTANCE_ID));
    //                end
    //            end
    //        end
    //    end
    //
    // localparam `STRING INSTANCE_ID = "BSC_MMU";
    // for (genvar i = 0; i < NUM_PTW_PORTS; i++) begin : g_ptw_trace
    //     always @(posedge clk) begin
    //         if (ptw_mem_bus_if[i].req_valid) begin
    //             `TRACE(0,
    //                    (
    //                    "%t: %s PTW side request: valid=%b addr=%08x cmd=%b typ=%b kill=%b phys=%b data=%08x\n"
    //                    , $time, INSTANCE_ID, ptw_dmem_comm_o[i].req.valid,
    //                        ptw_dmem_comm_o[i].req.addr, ptw_dmem_comm_o[i].req.cmd,
    //                        ptw_dmem_comm_o[i].req.typ, ptw_dmem_comm_o[i].req.kill,
    //                        ptw_dmem_comm_o[i].req.phys, ptw_dmem_comm_o[i].req.data));
    //             `TRACE(0,
    //                    ("%t: %s PTW req initiated: tag=%08x pgtbl_pa=%08x\n",
    //       $time, INSTANCE_ID,
    //       ptw_mem_bus_if[i].req_data.tag,
    //       ptw_mem_bus_if[i].req_data.addr));
    //             if (ptw_mem_bus_if[i].req_ready) begin
    //                 `TRACE(0,
    //                        ("%t: %s PTW req queued: tag=%08x pgtbl_pa=%08x\n",
    //       $time, INSTANCE_ID,
    //       ptw_mem_bus_if[i].req_data.tag,
    //       ptw_mem_bus_if[i].req_data.addr));
    //             end
    //         end
    //         if (ptw_mem_bus_if[i].rsp_valid) begin
    //             `TRACE(0,
    //                    ("%t: %s PTW rsp: tag=%08x pte=%08x\n",
    //       $time, INSTANCE_ID,
    //       ptw_mem_bus_if[i].rsp_data.tag,
    //       ptw_mem_bus_if[i].rsp_data.data));
    //         end
    //     end
    // end

endmodule
