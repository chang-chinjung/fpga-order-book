`timescale 1ns / 1ps

// Timing experiment 2: three-stage book, adder split into two 8-bit halves.
//
//   S1: decode + read current level quantity          (mux only)
//   S2: low half add/sub, capture carry and borrow    (8-bit carry chain)
//   S3: high half add/sub with the captured carry     (8-bit carry chain) + write
//
// order_book_pipe2 (two stages) is bounded by the full 16-bit carry chain
// (~6.4 ns). Splitting it should roughly halve the arithmetic depth again.
//
// Cost: latency 3 cycles, throughput 1 command / 3 cycles.
// Timing-only module; the verified design remains order_book.sv.
module order_book_pipe3 #(
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

    localparam int H = QTY_W / 2;

    logic [QTY_W-1:0] bid_q [LEVELS];
    logic [QTY_W-1:0] ask_q [LEVELS];

    // ---------------- S1: read ----------------
    logic             s1_valid;
    logic [1:0]       s1_op;
    logic             s1_side;
    logic [LVL_W-1:0] s1_level;
    logic [QTY_W-1:0] s1_cur;
    logic [QTY_W-1:0] s1_qty;

    wire [QTY_W-1:0] rd_cur = cmd_side ? ask_q[cmd_level] : bid_q[cmd_level];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_op    <= 2'b0;
            s1_side  <= 1'b0;
            s1_level <= '0;
            s1_cur   <= '0;
            s1_qty   <= '0;
        end else begin
            s1_valid <= cmd_valid;
            s1_op    <= cmd_op;
            s1_side  <= cmd_side;
            s1_level <= cmd_level;
            s1_cur   <= rd_cur;
            s1_qty   <= cmd_qty;
        end
    end

    // ---------------- S2: low half (8-bit carry) ----------------
    wire [H:0] add_lo = {1'b0, s1_cur[H-1:0]} + {1'b0, s1_qty[H-1:0]};
    wire [H:0] sub_lo = {1'b0, s1_cur[H-1:0]} - {1'b0, s1_qty[H-1:0]};

    logic             s2_valid;
    logic [1:0]       s2_op;
    logic             s2_side;
    logic [LVL_W-1:0] s2_level;
    logic [H-1:0]     s2_cur_hi;
    logic [H-1:0]     s2_qty_hi;
    logic [H-1:0]     s2_low_add;
    logic [H-1:0]     s2_low_sub;
    logic             s2_carry;
    logic             s2_borrow;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid   <= 1'b0;
            s2_op      <= 2'b0;
            s2_side    <= 1'b0;
            s2_level   <= '0;
            s2_cur_hi  <= '0;
            s2_qty_hi  <= '0;
            s2_low_add <= '0;
            s2_low_sub <= '0;
            s2_carry   <= 1'b0;
            s2_borrow  <= 1'b0;
        end else begin
            s2_valid   <= s1_valid;
            s2_op      <= s1_op;
            s2_side    <= s1_side;
            s2_level   <= s1_level;
            s2_cur_hi  <= s1_cur[QTY_W-1:H];
            s2_qty_hi  <= s1_qty[QTY_W-1:H];
            s2_low_add <= add_lo[H-1:0];
            s2_low_sub <= sub_lo[H-1:0];
            s2_carry   <= add_lo[H];
            s2_borrow  <= sub_lo[H];
        end
    end

    // ---------------- S3: high half with captured carry ----------------
    wire [H:0] add_hi = {1'b0, s2_cur_hi} + {1'b0, s2_qty_hi} + s2_carry;
    wire [H:0] sub_hi = {1'b0, s2_cur_hi} - {1'b0, s2_qty_hi} - s2_borrow;

    wire [QTY_W-1:0] res_add = {add_hi[H-1:0], s2_low_add};
    wire [QTY_W-1:0] res_sub = sub_hi[H] ? '0 : {sub_hi[H-1:0], s2_low_sub};
    wire [QTY_W-1:0] wr_val  = (s2_op == 2'd0) ? res_add : res_sub;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < LEVELS; i++) begin
                bid_q[i] <= '0;
                ask_q[i] <= '0;
            end
        end else if (s2_valid) begin
            if (s2_side) ask_q[s2_level] <= wr_val;
            else         bid_q[s2_level] <= wr_val;
        end
    end

    // ---------------- best price ----------------
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
