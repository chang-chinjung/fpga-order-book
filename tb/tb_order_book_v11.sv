`timescale 1ns / 1ps

// Replays 1,024-level stimulus against order_book_v11 and compares to the
// Python model. Latency is one clock.
module tb_order_book_v11;
    localparam int LEVELS = 1024;
    localparam int QTY_W  = 16;
    localparam int LW     = 10;

    logic clk = 0;
    /* verilator lint_off SYNCASYNCNET */
    logic rst_n = 0;
    /* verilator lint_on SYNCASYNCNET */

    logic             cmd_valid = 0;
    logic [1:0]       cmd_op    = 0;
    logic             cmd_side  = 0;
    logic [LW-1:0]    cmd_level = 0;
    logic [QTY_W-1:0] cmd_qty   = 0;

    logic             bid_valid, ask_valid;
    logic [LW-1:0]    best_bid, best_ask;
    logic [QTY_W-1:0] best_bid_qty, best_ask_qty;

    order_book_v11 #(.LEVELS(LEVELS), .QTY_W(QTY_W)) dut (
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
        .best_ask_qty (best_ask_qty)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    int inv_errors = 0;

    /* verilator lint_off BLKSEQ */
    always @(posedge clk) begin
        if (rst_n) begin
            if (bid_valid && best_bid_qty == '0) begin
                $display("INV bid_valid with zero qty");
                inv_errors++;
            end
            if (ask_valid && best_ask_qty == '0) begin
                $display("INV ask_valid with zero qty");
                inv_errors++;
            end
            if (bid_valid && 32'(best_bid) >= LEVELS) begin
                $display("INV best_bid out of range");
                inv_errors++;
            end
            if (ask_valid && 32'(best_ask) >= LEVELS) begin
                $display("INV best_ask out of range");
                inv_errors++;
            end
        end
    end
    /* verilator lint_on BLKSEQ */

    int fd_s, fd_e, rc;
    int n, n_exp, i;
    int op, side, lvl, qty;
    int e_bv, e_bid, e_bq, e_av, e_ask, e_aq;
    int errors = 0;

    initial begin
        $dumpfile("build/wave_v11.fst");
        $dumpvars(0, tb_order_book_v11);

        fd_s = $fopen("stim_v11.txt", "r");
        fd_e = $fopen("exp_v11.txt", "r");
        if (fd_s == 0 || fd_e == 0) $fatal(1, "missing stim_v11.txt / exp_v11.txt - run 'make stim-v11'");

        rc = $fscanf(fd_s, "%d", n);
        rc = $fscanf(fd_e, "%d", n_exp);
        if (n != n_exp) $fatal(1, "stim/exp length mismatch");
        $display("replaying %0d commands (v11, %0d levels)", n, LEVELS);

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (i = 0; i < n; i++) begin
            rc = $fscanf(fd_s, "%d %d %d %d", op, side, lvl, qty);
            if (rc != 4) $fatal(1, "stim step %0d: short read", i);
            rc = $fscanf(fd_e, "%d %d %d %d %d %d", e_bv, e_bid, e_bq, e_av, e_ask, e_aq);
            if (rc != 6) $fatal(1, "exp step %0d: short read", i);

            if (lvl < 0 || lvl >= LEVELS) $fatal(1, "bad level %0d", lvl);
            if (qty <= 0 || qty > 65535) $fatal(1, "bad qty %0d", qty);
            if (op < 0 || op > 2) $fatal(1, "bad op %0d", op);
            if (side != 0 && side != 1) $fatal(1, "bad side %0d", side);

            @(negedge clk);
            cmd_valid = 1'b1;
            cmd_op    = op[1:0];
            cmd_side  = side[0];
            cmd_level = lvl[LW-1:0];
            cmd_qty   = qty[QTY_W-1:0];

            @(posedge clk);   // E1: ladder write + bitmap update
            @(negedge clk);
            cmd_valid = 1'b0; // deassert away from the edge (no double write)
            @(posedge clk);   // E2: best index + quantity registered
            #1;

            if (bid_valid !== (e_bv != 0)) begin
                $display("step %0d: bid_valid got=%0b exp=%0b", i, bid_valid, e_bv != 0);
                errors++;
            end else if (e_bv != 0 && (best_bid !== e_bid[LW-1:0] || best_bid_qty !== e_bq[QTY_W-1:0])) begin
                $display("step %0d: bid got level=%0d qty=%0d exp level=%0d qty=%0d",
                         i, best_bid, best_bid_qty, e_bid, e_bq);
                errors++;
            end

            if (ask_valid !== (e_av != 0)) begin
                $display("step %0d: ask_valid got=%0b exp=%0b", i, ask_valid, e_av != 0);
                errors++;
            end else if (e_av != 0 && (best_ask !== e_ask[LW-1:0] || best_ask_qty !== e_aq[QTY_W-1:0])) begin
                $display("step %0d: ask got level=%0d qty=%0d exp level=%0d qty=%0d",
                         i, best_ask, best_ask_qty, e_ask, e_aq);
                errors++;
            end

            @(negedge clk);
            cmd_valid = 1'b0;

            if (errors > 20) begin
                $display("too many errors, stopping at step %0d", i);
                i = n;
            end
        end

        if (errors == 0 && inv_errors == 0) $display("ALL TESTS PASS (%0d steps)", n);
        else $display("FAILED: %0d mismatch(es), %0d invariant(s)", errors, inv_errors);

        $finish;
    end
endmodule
