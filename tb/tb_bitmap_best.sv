`timescale 1ns / 1ps

// Replays bitmap stimulus and compares hi/lo against the Python model.
module tb_bitmap_best;
    localparam int LEVELS = 1024;
    localparam int LW     = 10;

    logic clk = 0;
    /* verilator lint_off SYNCASYNCNET */
    logic rst_n = 0;
    /* verilator lint_on SYNCASYNCNET */

    logic          upd_valid = 0;
    logic          upd_set   = 0;
    logic [LW-1:0] upd_index = 0;

    logic          hi_valid, lo_valid;
    logic [LW-1:0] hi_index, lo_index;

    bitmap_best #(.LEVELS(LEVELS)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .upd_valid(upd_valid),
        .upd_set  (upd_set),
        .upd_index(upd_index),
        .hi_valid (hi_valid),
        .hi_index (hi_index),
        .lo_valid (lo_valid),
        .lo_index (lo_index)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    int inv_errors = 0;

    // Independent invariants over the ports.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk) begin
        if (rst_n) begin
            if (hi_valid && 32'(hi_index) >= LEVELS) begin
                $display("INV hi_index out of range: %0d", hi_index);
                inv_errors++;
            end
            if (lo_valid && 32'(lo_index) >= LEVELS) begin
                $display("INV lo_index out of range: %0d", lo_index);
                inv_errors++;
            end
            if (hi_valid && lo_valid && hi_index < lo_index) begin
                $display("INV hi %0d < lo %0d", hi_index, lo_index);
                inv_errors++;
            end
        end
    end
    /* verilator lint_on BLKSEQ */

    int fd_s, fd_e, rc;
    int n, n_exp, i;
    int e_hv, e_hi, e_lv, e_lo;
    int errors = 0;
    string op;

    initial begin
        $dumpfile("build/wave_bitmap.fst");
        $dumpvars(0, tb_bitmap_best);

        fd_s = $fopen("stim_bitmap.txt", "r");
        fd_e = $fopen("exp_bitmap.txt", "r");
        if (fd_s == 0 || fd_e == 0) $fatal(1, "missing stim_bitmap.txt / exp_bitmap.txt - run 'make stim-bitmap'");

        rc = $fscanf(fd_s, "%d", n);
        rc = $fscanf(fd_e, "%d", n_exp);
        if (n != n_exp) $fatal(1, "stim/exp length mismatch");

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (i = 0; i < n; i++) begin
            rc = $fscanf(fd_s, "%s %d", op, upd_index);
            if (rc != 2) $fatal(1, "stim step %0d: short read", i);
            rc = $fscanf(fd_e, "%d %d %d %d", e_hv, e_hi, e_lv, e_lo);
            if (rc != 4) $fatal(1, "exp step %0d: short read", i);

            @(negedge clk);
            upd_valid = 1'b1;
            upd_set   = (op == "set");
            if (32'(upd_index) >= LEVELS) $fatal(1, "bad index %0d", upd_index);

            @(posedge clk);
            #1;
            upd_valid = 1'b0;

            if (hi_valid !== (e_hv != 0)) begin
                $display("step %0d: hi_valid got=%0b exp=%0b", i, hi_valid, e_hv != 0);
                errors++;
            end else if (e_hv != 0 && hi_index !== e_hi[LW-1:0]) begin
                $display("step %0d: hi got=%0d exp=%0d", i, hi_index, e_hi);
                errors++;
            end

            if (lo_valid !== (e_lv != 0)) begin
                $display("step %0d: lo_valid got=%0b exp=%0b", i, lo_valid, e_lv != 0);
                errors++;
            end else if (e_lv != 0 && lo_index !== e_lo[LW-1:0]) begin
                $display("step %0d: lo got=%0d exp=%0d", i, lo_index, e_lo);
                errors++;
            end

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
