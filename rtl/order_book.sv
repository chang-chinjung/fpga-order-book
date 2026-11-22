`timescale 1ns / 1ps

// Level-indexed limit order book core.
//
// One shared price axis: level 0 is the lowest price, LEVELS-1 the highest.
// Bids sit on lower levels, asks on higher levels; best bid is the highest
// occupied level, best ask the lowest. This is the smallest book that still
// requires a priority scan, which is what a real feed handler needs.
module order_book #(
    parameter int LEVELS = 16,
    parameter int QTY_W  = 16,
    parameter int LVL_W  = (LEVELS <= 2) ? 1 : $clog2(LEVELS)
) (
    input  logic              clk,
    input  logic              rst_n,

    // Command interface: one command per cycle.
    input  logic              cmd_valid,
    input  logic [1:0]        cmd_op,    // 0 = ADD, 1 = CANCEL, 2 = TRADE
    input  logic              cmd_side,  // 0 = bid, 1 = ask
    input  logic [LVL_W-1:0]  cmd_level,
    input  logic [QTY_W-1:0]  cmd_qty,

    // Best price and size.
    output logic              bid_valid,
    output logic [LVL_W-1:0]  best_bid,
    output logic [QTY_W-1:0]  best_bid_qty,
    output logic              ask_valid,
    output logic [LVL_W-1:0]  best_ask,
    output logic [QTY_W-1:0]  best_ask_qty,

    // Full depth, level-major.
    output logic [LEVELS*QTY_W-1:0] bid_levels,
    output logic [LEVELS*QTY_W-1:0] ask_levels
);

    logic [QTY_W-1:0] bid_q [LEVELS];
    logic [QTY_W-1:0] ask_q [LEVELS];

    logic [QTY_W-1:0] cur_q;
    assign cur_q = cmd_side ? ask_q[cmd_level] : bid_q[cmd_level];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < LEVELS; i++) begin
                bid_q[i] <= '0;
                ask_q[i] <= '0;
            end
        end else if (cmd_valid) begin
            case (cmd_op)
                2'd0: begin  // ADD
                    if (cmd_side) ask_q[cmd_level] <= ask_q[cmd_level] + cmd_qty;
                    else          bid_q[cmd_level] <= bid_q[cmd_level] + cmd_qty;
                end
                default: begin  // CANCEL / TRADE: subtract, saturate at zero
                    if (cmd_side) ask_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q - cmd_qty) : '0;
                    else          bid_q[cmd_level] <= (cur_q > cmd_qty) ? (cur_q - cmd_qty) : '0;
                end
            endcase
        end
    end

    // Best bid: highest occupied level (last non-zero wins in ascending scan).
    always_comb begin
        bid_valid    = 1'b0;
        best_bid     = '0;
        best_bid_qty = '0;
        for (int i = 0; i < LEVELS; i++) begin
            if (bid_q[i] != '0) begin
                bid_valid    = 1'b1;
                best_bid     = LVL_W'(i);
                best_bid_qty = bid_q[i];
            end
        end
    end

    // Best ask: lowest occupied level (last non-zero wins in descending scan).
    always_comb begin
        ask_valid    = 1'b0;
        best_ask     = '0;
        best_ask_qty = '0;
        for (int i = LEVELS - 1; i >= 0; i--) begin
            if (ask_q[i] != '0) begin
                ask_valid    = 1'b1;
                best_ask     = LVL_W'(i);
                best_ask_qty = ask_q[i];
            end
        end
    end

    always_comb begin
        for (int i = 0; i < LEVELS; i++) begin
            bid_levels[i*QTY_W +: QTY_W] = bid_q[i];
            ask_levels[i*QTY_W +: QTY_W] = ask_q[i];
        end
    end

endmodule
