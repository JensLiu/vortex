interface VX_addr_trans_if #(
    parameter ADDRESS_WIDTH = 32,
    parameter ASID_SIZE = 1
) ();

  logic valid;
  logic [VPN_SIZE:0] vpn;
  logic [PPN_SIZE-1:0] ppn;
  logic [ASID_SIZE-1:0] asid;
  //   logic [1:0] priv_lvl;
  //   logic vm_enabled;
  //   logic passthrough;
  logic store;
  logic ready;

  modport master(
      output valid,
      output vpn,
      input ppn,
      output asid,
      //   output priv_lvl,
      //   output vm_enabled,
      output store,
      input ready
  );

  modport slave(
      input valid,
      input vpn,
      output ppn,
      input asid,
      //   input priv_lvl,
      //   input vm_enabled,
      input store,
      output ready
  );

endinterface
