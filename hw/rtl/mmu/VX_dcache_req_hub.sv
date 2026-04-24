`include "VX_define.vh"

module VX_dcache_req_hub
    import VX_gpu_pkg::*;
#(
    parameter int unsigned NUM_LSU_REQS     = DCACHE_NUM_LSU_REQS,
    parameter int unsigned NUM_PTW_REQS     = DCACHE_NUM_PTW_REQS,
    parameter int unsigned NUM_MERGED_PORTS = NUM_LSU_REQS
) (
    input logic clk,
    input logic reset,

    VX_mem_bus_if.slave  lsu_mem_if   [    NUM_LSU_REQS],
    VX_mem_bus_if.slave  ptw_mem_if   [    NUM_PTW_REQS],
    // PTW requests are injected into the LSU request space (no extra output ports).
    VX_mem_bus_if.master client_mem_if[NUM_MERGED_PORTS]
);

    `UNUSED_VAR(clk)
    `UNUSED_VAR(reset)

    `STATIC_ASSERT(NUM_PTW_REQS <= 1, ("Only support up to 1 PTW request for now"));

    if (NUM_PTW_REQS == 0) begin : g_bypass
        for (genvar i = 0; i < NUM_LSU_REQS; ++i) begin : g_lsu_fmt
            assign client_mem_if[i].req_valid = lsu_mem_if[i].req_valid;
            assign client_mem_if[i].req_data  = lsu_mem_if[i].req_data;
            assign lsu_mem_if[i].req_ready    = client_mem_if[i].req_ready;

            assign lsu_mem_if[i].rsp_valid    = client_mem_if[i].rsp_valid;
            assign lsu_mem_if[i].rsp_data     = client_mem_if[i].rsp_data;
            assign client_mem_if[i].rsp_ready = lsu_mem_if[i].rsp_ready;
        end
    end else if (NUM_MERGED_PORTS == NUM_LSU_REQS && NUM_PTW_REQS == 1) begin : g_mux_merge
        localparam int unsigned INJECT_IDX = (NUM_LSU_REQS == 0) ? 0 : (NUM_LSU_REQS - 1);
        // TODO: use adaptive policy, find the first available slot instead of always using the last channel
        // Non-injection LSU ports
        for (genvar i = 0; i < NUM_LSU_REQS; ++i) begin : g_ports
            if (i != INJECT_IDX) begin : g_lsu
                // LSU request formatting (client-id augmentation)
                assign client_mem_if[i].req_valid = lsu_mem_if[i].req_valid;
                assign client_mem_if[i].req_data.tag.uuid = lsu_mem_if[i].req_data.tag.uuid;
                /* verilator lint_off WIDTHTRUNC */
                assign client_mem_if[i].req_data.tag.value = {
                    MEM_CLIENT_ID_WIDTH'(MEM_CLIENT_LSU), lsu_mem_if[i].req_data.tag.value
                };
                /* verilator lint_on WIDTHTRUNC */
                assign client_mem_if[i].req_data.rw = lsu_mem_if[i].req_data.rw;
                assign client_mem_if[i].req_data.addr = lsu_mem_if[i].req_data.addr;
                assign client_mem_if[i].req_data.data = lsu_mem_if[i].req_data.data;
                assign client_mem_if[i].req_data.byteen = lsu_mem_if[i].req_data.byteen;
                assign client_mem_if[i].req_data.flags = lsu_mem_if[i].req_data.flags;
                assign lsu_mem_if[i].req_ready = client_mem_if[i].req_ready;

                // LSU response de-augmentation
                assign lsu_mem_if[i].rsp_valid = client_mem_if[i].rsp_valid;
                assign lsu_mem_if[i].rsp_data.tag.uuid = client_mem_if[i].rsp_data.tag.uuid;
                /* verilator lint_off WIDTHEXPAND */
                assign lsu_mem_if[i].rsp_data.tag.value  = client_mem_if[i].rsp_data.tag.value[DCACHE_TAG_ID_BITS-1:0];
                /* verilator lint_on WIDTHEXPAND */
                assign lsu_mem_if[i].rsp_data.data = client_mem_if[i].rsp_data.data;
                assign client_mem_if[i].rsp_ready = lsu_mem_if[i].rsp_ready;
            end
        end

        // Injection port mux logic
        logic ptw_outstanding;
        logic ptw_fire = ptw_mem_if[0].req_valid && client_mem_if[INJECT_IDX].req_ready && !ptw_outstanding;
        // TODO: make sure this is the correct memory response
        logic ptw_ready = ptw_mem_if[0].rsp_valid && ptw_mem_if[0].rsp_ready;
        always_ff @(posedge clk) begin
            if (reset) begin
                ptw_outstanding <= 1'b0;
            end else begin
                if (ptw_fire) begin
                    ptw_outstanding <= 1'b1;
                end
                if (ptw_outstanding && ptw_ready) begin
                    // TODO: check client ID is PTW
                    ptw_outstanding <= 1'b0;
                end
            end
        end

        logic use_ptw = ptw_mem_if[0].req_valid && !ptw_outstanding;
        assign client_mem_if[INJECT_IDX].req_valid = use_ptw ? ptw_mem_if[0].req_valid : lsu_mem_if[INJECT_IDX].req_valid;
        assign client_mem_if[INJECT_IDX].req_data.tag.uuid = use_ptw ? ptw_mem_if[0].req_data.tag.uuid : lsu_mem_if[INJECT_IDX].req_data.tag.uuid;
        /* verilator lint_off WIDTHTRUNC */
        // Request Client ID injection
        assign client_mem_if[INJECT_IDX].req_data.tag.value = use_ptw
            ? {MEM_CLIENT_ID_WIDTH'(MEM_CLIENT_PTW), ptw_mem_if[0].req_data.tag.value}
            : {MEM_CLIENT_ID_WIDTH'(MEM_CLIENT_LSU), lsu_mem_if[INJECT_IDX].req_data.tag.value};
        /* verilator lint_on WIDTHTRUNC */
        assign client_mem_if[INJECT_IDX].req_data.rw     = use_ptw ? ptw_mem_if[0].req_data.rw     : lsu_mem_if[INJECT_IDX].req_data.rw;
        assign client_mem_if[INJECT_IDX].req_data.addr   = use_ptw ? ptw_mem_if[0].req_data.addr   : lsu_mem_if[INJECT_IDX].req_data.addr;
        assign client_mem_if[INJECT_IDX].req_data.data   = use_ptw ? ptw_mem_if[0].req_data.data   : lsu_mem_if[INJECT_IDX].req_data.data;
        assign client_mem_if[INJECT_IDX].req_data.byteen = use_ptw ? ptw_mem_if[0].req_data.byteen : lsu_mem_if[INJECT_IDX].req_data.byteen;
        assign client_mem_if[INJECT_IDX].req_data.flags  = use_ptw ? ptw_mem_if[0].req_data.flags  : lsu_mem_if[INJECT_IDX].req_data.flags;

        // PTW handshake
        assign ptw_mem_if[0].req_ready = use_ptw ? client_mem_if[INJECT_IDX].req_ready : 1'b0;
        assign lsu_mem_if[INJECT_IDX].req_ready = use_ptw ? 1'b0 : client_mem_if[INJECT_IDX].req_ready;
        // Response Client ID removal
        assign ptw_mem_if[0].rsp_valid           = ptw_outstanding ? client_mem_if[INJECT_IDX].rsp_valid : 1'b0;
        assign ptw_mem_if[0].rsp_data.tag.uuid = client_mem_if[INJECT_IDX].rsp_data.tag.uuid;
        assign ptw_mem_if[0].rsp_data.tag.value = ptw_outstanding ? client_mem_if[INJECT_IDX].rsp_data.tag.value[DCACHE_TAG_ID_BITS-1:0] : '0;
        assign ptw_mem_if[0].rsp_data.data      = ptw_outstanding ? client_mem_if[INJECT_IDX].rsp_data.data : '0;

        assign lsu_mem_if[INJECT_IDX].rsp_valid           = ptw_outstanding ? 1'b0 : client_mem_if[INJECT_IDX].rsp_valid;
        assign lsu_mem_if[INJECT_IDX].rsp_data.tag.uuid   = client_mem_if[INJECT_IDX].rsp_data.tag.uuid;
        assign lsu_mem_if[INJECT_IDX].rsp_data.tag.value  = client_mem_if[INJECT_IDX].rsp_data.tag.value[DCACHE_TAG_ID_BITS-1:0];
        assign lsu_mem_if[INJECT_IDX].rsp_data.data = client_mem_if[INJECT_IDX].rsp_data.data;

        assign client_mem_if[INJECT_IDX].rsp_ready = ptw_outstanding ? ptw_mem_if[0].rsp_ready : lsu_mem_if[INJECT_IDX].rsp_ready;

    end

endmodule
