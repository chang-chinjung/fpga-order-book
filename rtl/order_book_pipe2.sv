`timescale 1ns / 1ps

// Timing-only experiment: same level-indexed book, but split into two stages.
//
//   S1: decode the command and read the current level quantity  (mux only)
//   S2: compare/subtract and write the level                    (carry chain only)
//
// The prototype in order_book.sv does both in one cycle; nextpnr put the
// mux tree and the 16-bit carry chain in series (~10.4 ns, 95 MHz).
// Splitting them should roughly halve the logic depth.
//
// Cost: latency 2 cycles, throughput 1 command / 2 cycles. This module is for
// P&R measurement only; the verified design remains order_book.sv.
module order_book_pipe2 #(
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

    logic [QTY_W-1:0] bid_q [LEVELS];
    logic [QTY_W-1:0] ask_q [LEVELS];

    // ---------------- S1: read ----------------
    logic             s1_valid;
    logic [1:0]       s1_op;
    logic             s1_side;
    logic [LVL_W-1:0] s1_level;
    logic [QTY_W-1:0] s1_qty;
    logic [QTY_W-1:0] s1_cur;

    wire [QTY_W-1:0] rd_cur = cmd_side ? ask_q[cmd_level] : bid_q[cmd_level];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_op    <= 2'b0;
            s1_side  <= 1'b0;
            s1_level <= '0;
            s1_qty   <= '0;
            s1_cur   <= '0;
        end else begin
            s1_valid <= cmd_valid;
            s1_op    <= cmd_op;
            s1_side  <= cmd_side;
            s1_level <= cmd_level;
            s1_qty   <= cmd_qty;
            s1_cur   <= rd_cur;
        end
    end

    // ---------------- S2: compare / subtract / write ----------------
    logic [QTY_W-1:0] wr_val;
    always_comb begin
        if (s1_op == 2'd0) wr_val = s1_cur + s1_qty;
        else               wr_val = (s1_cur > s1_qty) ? (s1_cur - s1_qty) : '0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < LEVELS; i++) begin
                bid_q[i] <= '0;
                ask_q[i] <= '0;
            end
        end else if (s1_valid) begin
            if (s1_side) ask_q[s1_level] <= wr_val;
            else         bid_q[s1_level] <= wr_val;
        end
    end

    // ---------------- best price (combinational) ----------------
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

endmodule
