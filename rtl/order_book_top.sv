`timescale 1ns / 1ps

// Synthesis / place-and-route wrapper.
//
// The full book exposes LEVELS*QTY_W*2 depth bits, which is far more I/O than
// any small ECP5 package has (16 levels -> 512 pins). For timing analysis we
// only need the logic, not the pins, so this wrapper leaves the depth outputs
// unconnected. Synthesis removes the unused output logic but keeps every
// register that feeds best-price, which is what the critical path goes through.
module order_book_top #(
    parameter int LEVELS = 16,
    parameter int QTY_W  = 16,
    parameter int LVL_W  = (LEVELS <= 2) ? 1 : $clog2(LEVELS)
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             cmd_valid,
    input  logic [1:0]       cmd_op,
    input  logic             cmd_side,
    input  logic [LVL_W-1:0] cmd_level,
    input  logic [QTY_W-1:0] cmd_qty,
    output logic             bid_valid,
    output logic [LVL_W-1:0] best_bid,
    output logic [QTY_W-1:0] best_bid_qty,
    output logic             ask_valid,
    output logic [LVL_W-1:0] best_ask,
    output logic [QTY_W-1:0] best_ask_qty
);

    order_book #(
        .LEVELS(LEVELS),
        .QTY_W (QTY_W)
    ) u_book (
        .clk          (clk),
        .rst_n        (rst_n),
        .cmd_valid    (cmd_valid),
        .cmd_op       (cmd_op),
        .cmd_side     (cmd_side),
        .cmd_level    (cmd_level),
        .cmd_qty      (cmd_qty),
        .bid_valid    (bid_valid),
        .best_bid     (best_bid),
        .best_bid_qty (best_bid_qty),
        .ask_valid    (ask_valid),
        .best_ask     (best_ask),
        .best_ask_qty (best_ask_qty),
        .bid_levels   (),
        .ask_levels   ()
    );

endmodule
