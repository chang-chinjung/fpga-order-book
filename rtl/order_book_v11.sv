`timescale 1ns / 1ps

// v1.1: 1,024-level book with bitmap best-price lookup.
//
// Ladder quantities live in block RAM (synchronous read, one cycle), so the
// path is:
//   E1: write ladder + update occupancy bitmap
//   E2: register best index and read its quantity
// Latency: 2 cycles, independent of LEVELS.
module order_book_v11 #(
    parameter int LEVELS = 1024,
    parameter int QTY_W  = 16,
    parameter int LW     = (LEVELS <= 2) ? 1 : $clog2(LEVELS)
) (
    input  logic          clk,
    input  logic          rst_n,

    input  logic          cmd_valid,
    input  logic [1:0]    cmd_op,     // 0=ADD, 1=CANCEL, 2=TRADE
    input  logic          cmd_side,
    input  logic [LW-1:0] cmd_level,
    input  logic [QTY_W-1:0] cmd_qty,

    output logic          bid_valid,
    output logic [LW-1:0] best_bid,
    output logic [QTY_W-1:0] best_bid_qty,
    output logic          ask_valid,
    output logic [LW-1:0] best_ask,
    output logic [QTY_W-1:0] best_ask_qty
);

    (* ram_style = "block" *) logic [QTY_W-1:0] bid_q [LEVELS];
    (* ram_style = "block" *) logic [QTY_W-1:0] ask_q [LEVELS];

    wire [QTY_W-1:0] cur_q = cmd_side ? ask_q[cmd_level] : bid_q[cmd_level];
    wire [QTY_W-1:0] new_q = (cmd_op == 2'd0)
                             ? (cur_q + cmd_qty)
                             : ((cur_q > cmd_qty) ? (cur_q - cmd_qty) : '0);

    // ---------------- occupancy bitmaps ----------------
    logic bid_bm_valid, ask_bm_valid;
    assign bid_bm_valid = cmd_valid && !cmd_side;
    assign ask_bm_valid = cmd_valid &&  cmd_side;

    logic          bid_hi_valid, ask_lo_valid;
    logic [LW-1:0] bid_hi, ask_lo;

    bitmap_best #(.LEVELS(LEVELS)) u_bid_bm (
        .clk      (clk),
        .rst_n    (rst_n),
        .upd_valid(bid_bm_valid),
        .upd_set  (new_q != '0),
        .upd_index(cmd_level),
        .hi_valid (bid_hi_valid),
        .hi_index (bid_hi),
        .lo_valid (),
        .lo_index ()
    );

    bitmap_best #(.LEVELS(LEVELS)) u_ask_bm (
        .clk      (clk),
        .rst_n    (rst_n),
        .upd_valid(ask_bm_valid),
        .upd_set  (new_q != '0),
        .upd_index(cmd_level),
        .hi_valid (),
        .hi_index (),
        .lo_valid (ask_lo_valid),
        .lo_index (ask_lo)
    );

    // ---------------- ladder write + read pipeline ----------------
    logic             bid_valid_q, ask_valid_q;
    logic [LW-1:0]    bid_idx_q,   ask_idx_q;
    logic [QTY_W-1:0] bid_qty_q,   ask_qty_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < LEVELS; i++) begin
                bid_q[i] <= '0;
                ask_q[i] <= '0;
            end
            bid_valid_q <= 1'b0;
            ask_valid_q <= 1'b0;
            bid_idx_q   <= '0;
            ask_idx_q   <= '0;
            bid_qty_q   <= '0;
            ask_qty_q   <= '0;
        end else begin
            // ladder update
            if (cmd_valid) begin
                if (cmd_side) ask_q[cmd_level] <= new_q;
                else          bid_q[cmd_level] <= new_q;
            end

            // best index and its quantity, one cycle later
            bid_valid_q <= bid_hi_valid;
            bid_idx_q   <= bid_hi;
            bid_qty_q   <= bid_q[bid_hi];

            ask_valid_q <= ask_lo_valid;
            ask_idx_q   <= ask_lo;
            ask_qty_q   <= ask_q[ask_lo];
        end
    end

    assign bid_valid     = bid_valid_q;
    assign best_bid      = bid_idx_q;
    assign best_bid_qty  = bid_qty_q;

    assign ask_valid     = ask_valid_q;
    assign best_ask      = ask_idx_q;
    assign best_ask_qty  = ask_qty_q;

endmodule
