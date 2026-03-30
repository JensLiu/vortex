`include "VX_define.vh"

module VX_dcache_req_hub
  import VX_gpu_pkg::*;
#(
    parameter NUM_LSU_REQS = 1,
    parameter NUM_PTW_REQS = 1
) (
    input wire clk,
    input wire reset,
    VX_mem_bus_if.slave lsu_mem_if[NUM_LSU_REQS],
    VX_mem_bus_if.slave ptw_mem_if[NUM_PTW_REQS],
    VX_mem_bus_if.master client_mem_if[NUM_LSU_REQS + NUM_PTW_REQS]
);

  if (NUM_PTW_REQS == 0) begin : g_lsu_bypass
    for (genvar i = 0; i < NUM_LSU_REQS; ++i) begin : g_client_mem_if
      // TAG is not augmented with client ID
      assign client_mem_if[i].req_valid = lsu_mem_if[i].req_valid;
      assign client_mem_if[i].req_data = lsu_mem_if[i].req_data;
      assign lsu_mem_if[i].req_ready = client_mem_if[i].req_ready;
      assign lsu_mem_if[i].rsp_valid = client_mem_if[i].rsp_valid;
      assign lsu_mem_if[i].rsp_data = client_mem_if[i].rsp_data;
      assign client_mem_if[i].rsp_ready = lsu_mem_if[i].rsp_ready;
    end
  end else begin : g_ptw_injection
    for (genvar i = 0; i < NUM_LSU_REQS; ++i) begin : g_lsu_reqs
      // pushing the client ID after the UUID in the LSU memory request identifier
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
      // removing the client ID from the LSU memory response identifier
      assign lsu_mem_if[i].rsp_valid = client_mem_if[i].rsp_valid;
      assign lsu_mem_if[i].rsp_data.tag.uuid = client_mem_if[i].rsp_data.tag.uuid;
      /* verilator lint_off WIDTHEXPAND */
      assign lsu_mem_if[i].rsp_data.tag.value = client_mem_if[i].rsp_data.tag.value[DCACHE_TAG_ID_BITS-1:0];
      /* verilator lint_on WIDTHEXPAND */
      assign lsu_mem_if[i].rsp_data.data = client_mem_if[i].rsp_data.data;
      assign client_mem_if[i].rsp_ready = lsu_mem_if[i].rsp_ready;
    end
    for (genvar i = 0; i < NUM_PTW_REQS; ++i) begin : g_ptw_reqs
      assign client_mem_if[NUM_LSU_REQS + i].req_valid = ptw_mem_if[i].req_valid;
      assign client_mem_if[NUM_LSU_REQS + i].req_data.tag.uuid = ptw_mem_if[i].req_data.tag.uuid;
      /* verilator lint_off WIDTHTRUNC */
      assign client_mem_if[NUM_LSU_REQS + i].req_data.tag.value = {
        MEM_CLIENT_ID_WIDTH'(MEM_CLIENT_PTW), ptw_mem_if[i].req_data.tag.value
      };
      /* verilator lint_on WIDTHTRUNC */
      assign client_mem_if[NUM_LSU_REQS + i].req_data.rw = ptw_mem_if[i].req_data.rw;
      assign client_mem_if[NUM_LSU_REQS + i].req_data.byteen = ptw_mem_if[i].req_data.byteen;
      assign client_mem_if[NUM_LSU_REQS + i].req_data.addr = ptw_mem_if[i].req_data.addr;
      assign client_mem_if[NUM_LSU_REQS + i].req_data.flags = ptw_mem_if[i].req_data.flags;
      assign client_mem_if[NUM_LSU_REQS + i].req_data.data = ptw_mem_if[i].req_data.data;
      assign ptw_mem_if[i].req_ready = client_mem_if[NUM_LSU_REQS + i].req_ready;
      // removing the client ID from the LSU memory request identifier
      assign ptw_mem_if[i].rsp_valid = client_mem_if[NUM_LSU_REQS + i].rsp_valid;
      assign ptw_mem_if[i].rsp_data.tag.uuid = client_mem_if[NUM_LSU_REQS + i].rsp_data.tag.uuid;
      /* verilator lint_off WIDTHEXPAND */
      assign ptw_mem_if[i].rsp_data.tag.value = client_mem_if[NUM_LSU_REQS + i].rsp_data.tag.value[DCACHE_TAG_ID_BITS-1:0];
      /* verilator lint_on WIDTHEXPAND */
      assign ptw_mem_if[i].rsp_data.data = client_mem_if[NUM_LSU_REQS + i].rsp_data.data;
      assign client_mem_if[NUM_LSU_REQS + i].rsp_ready = ptw_mem_if[i].rsp_ready;
    end
  end

endmodule
