`timescale 1ns / 1ps

// Occupancy bitmap with tree priority encoding (v1.1 best-price block).
//
// One bitmap per side. The owner sets a bit when a level becomes non-empty and
// clears it when the level empties. Outputs are the highest and lowest set bit.
//
// Depth: per-word 16-bit priority (2 levels) + 64-word tree (3 levels of 4:1)
// + final mux. The earlier linear version walked 64 + 16 levels and only
// reached 66 MHz at 1,024 levels.
//
// GROUP must be 16 (the per-word trees are written for 16 bits).
module bitmap_best #(
    parameter int LEVELS = 1024,
    parameter int GROUP  = 16,
    parameter int W      = LEVELS / GROUP,
    parameter int LW     = (LEVELS <= 2) ? 1 : $clog2(LEVELS),
    parameter int WW     = (W <= 2) ? 1 : $clog2(W),
    parameter int GW     = (GROUP <= 2) ? 1 : $clog2(GROUP)
) (
    input  logic          clk,
    input  logic          rst_n,

    input  logic          upd_valid,
    input  logic          upd_set,     // 1 = level became occupied, 0 = level emptied
    input  logic [LW-1:0] upd_index,

    output logic          hi_valid,
    output logic [LW-1:0] hi_index,
    output logic          lo_valid,
    output logic [LW-1:0] lo_index
);

    // ---------------- storage and update ----------------
    logic [GROUP-1:0] words [W];
    logic [W-1:0]     summary;

    wire [WW-1:0] upd_word = upd_index[LW-1:GW];
    wire [GW-1:0] upd_bit  = upd_index[GW-1:0];

    wire [GROUP-1:0] bit_mask  = {{(GROUP-1){1'b0}}, 1'b1} << upd_bit;
    wire [GROUP-1:0] word_next = upd_set ? (words[upd_word] | bit_mask)
                                         : (words[upd_word] & ~bit_mask);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int w = 0; w < W; w++) words[w] <= '0;
            summary <= '0;
        end else if (upd_valid) begin
            words[upd_word]   <= word_next;
            summary[upd_word] <= |word_next;
        end
    end

    // ---------------- priority helpers (tree, not a chain) ----------------
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic [1:0] hi2(input logic [3:0] v);
        if (v[3])      hi2 = 2'd3;
        else if (v[2]) hi2 = 2'd2;
        else if (v[1]) hi2 = 2'd1;
        else           hi2 = 2'd0;
    endfunction

    function automatic [1:0] lo2(input logic [3:0] v);
        if (v[0])      lo2 = 2'd0;
        else if (v[1]) lo2 = 2'd1;
        else if (v[2]) lo2 = 2'd2;
        else           lo2 = 2'd3;
    endfunction

    // 16-bit highest/lowest set bit: 4 nibbles in parallel, then one 4:1 mux.
    function automatic [3:0] hi16(input logic [15:0] v);
        if (v[15:12] != '0)      hi16 = {2'd3, hi2(v[15:12])};
        else if (v[11:8] != '0)  hi16 = {2'd2, hi2(v[11:8])};
        else if (v[7:4] != '0)   hi16 = {2'd1, hi2(v[7:4])};
        else                     hi16 = {2'd0, hi2(v[3:0])};
    endfunction

    function automatic [3:0] lo16(input logic [15:0] v);
        if (v[3:0] != '0)        lo16 = {2'd0, lo2(v[3:0])};
        else if (v[7:4] != '0)   lo16 = {2'd1, lo2(v[7:4])};
        else if (v[11:8] != '0)  lo16 = {2'd2, lo2(v[11:8])};
        else                     lo16 = {2'd3, lo2(v[15:12])};
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // ---------------- per-word bit index, computed in parallel ----------------
    logic [GW-1:0] w_hi_bit [W];
    logic [GW-1:0] w_lo_bit [W];

    generate
        for (genvar w = 0; w < W; w++) begin : g_word_prio
            assign w_hi_bit[w] = hi16(words[w]);
            assign w_lo_bit[w] = lo16(words[w]);
        end
    endgenerate

    // ---------------- 64-word selection tree ----------------
    // level 1: 16 groups of 4 words
    logic [W/4-1:0] g_any;
    logic [1:0]     g_sel [W/4];

    always_comb begin
        for (int g = 0; g < W / 4; g++) begin
            logic [3:0] s;
            s        = summary[g*4 +: 4];
            g_any[g] = |s;
            g_sel[g] = hi2(s);
        end
    end

    // level 2: 4 supers of 4 groups -> 4-bit index (2b group + 2b word)
    logic [3:0] h_any;
    logic [3:0] h_idx [4];

    always_comb begin
        for (int h = 0; h < 4; h++) begin
            logic [3:0] ga;
            logic [1:0] sel;
            ga       = g_any[h*4 +: 4];
            sel      = hi2(ga);
            h_any[h] = |ga;
            h_idx[h] = {sel, g_sel[h*4 + 32'(sel)]};
        end
    end

    logic [WW-1:0] hi_word;
    logic [WW-1:0] lo_word;
    logic [1:0]    top_sel;

    assign top_sel = hi2(h_any);
    assign hi_word = {top_sel, h_idx[top_sel]};

    // lowest: mirror the tree using lo2 comparisons
    logic [W/4-1:0] g_any_lo;
    logic [1:0]     g_sel_lo [W/4];

    always_comb begin
        for (int g = 0; g < W / 4; g++) begin
            logic [3:0] s;
            s           = summary[g*4 +: 4];
            g_any_lo[g] = |s;
            g_sel_lo[g] = lo2(s);
        end
    end

    logic [3:0] h_any_lo;
    logic [3:0] h_idx_lo [4];

    always_comb begin
        for (int h = 0; h < 4; h++) begin
            logic [3:0] ga;
            logic [1:0] sel;
            ga          = g_any_lo[h*4 +: 4];
            sel         = lo2(ga);
            h_any_lo[h] = |ga;
            h_idx_lo[h] = {sel, g_sel_lo[h*4 + 32'(sel)]};
        end
    end

    logic [1:0] top_sel_lo;
    assign top_sel_lo = lo2(h_any_lo);
    assign lo_word    = {top_sel_lo, h_idx_lo[top_sel_lo]};

    // ---------------- output mux ----------------
    logic [W*GW-1:0] w_hi_flat;
    logic [W*GW-1:0] w_lo_flat;

    generate
        for (genvar w = 0; w < W; w++) begin : g_flat
            assign w_hi_flat[w*GW +: GW] = w_hi_bit[w];
            assign w_lo_flat[w*GW +: GW] = w_lo_bit[w];
        end
    endgenerate

    logic [GW-1:0] hi_bit;
    logic [GW-1:0] lo_bit;

    assign hi_bit = w_hi_flat[hi_word*GW +: GW];
    assign lo_bit = w_lo_flat[lo_word*GW +: GW];

    assign hi_valid = |summary;
    assign lo_valid = |summary;
    assign hi_index = LW'(hi_word) * LW'(GROUP) + LW'(hi_bit);
    assign lo_index = LW'(lo_word) * LW'(GROUP) + LW'(lo_bit);

endmodule
