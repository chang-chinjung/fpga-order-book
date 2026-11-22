`timescale 1ns / 1ps

// Replays model-generated stimulus and compares every cycle against the
// Python reference model's golden output.
module tb_order_book;
    localparam int LEVELS = 16;
    localparam int QTY_W  = 16;
    localparam int LVL_W  = 4;
    localparam int QTY_MASK = (1 << QTY_W) - 1;

    logic clk = 0;
    /* verilator lint_off SYNCASYNCNET */
    logic rst_n = 0;
    /* verilator lint_on SYNCASYNCNET */

    logic              cmd_valid = 0;
    logic [1:0]        cmd_op    = 0;
    logic              cmd_side  = 0;
    logic [LVL_W-1:0]  cmd_level = 0;
    logic [QTY_W-1:0]  cmd_qty   = 0;

    logic              bid_valid, ask_valid;
    logic [LVL_W-1:0]  best_bid, best_ask;
    logic [QTY_W-1:0]  best_bid_qty, best_ask_qty;
    logic [LEVELS*QTY_W-1:0] bid_levels, ask_levels;

    order_book #(
        .LEVELS(LEVELS),
        .QTY_W (QTY_W)
    ) dut (
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
        .bid_levels   (bid_levels),
        .ask_levels   (ask_levels)
    );

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    // ---- Independent invariants -------------------------------------------
    // These check relationships between DUT outputs only; they never consult
    // the Python model, so they survive a shared misunderstanding of the spec.
    int inv_errors = 0;

    /* verilator lint_off BLKSEQ */
    always @(posedge clk) begin
        if (rst_n) begin
            // INV1: valid flag must equal "any level occupied".
            if (bid_valid !== (bid_levels != '0)) begin
                $display("INV1 bid_valid=%0b but depth nonzero=%0b", bid_valid, (bid_levels != '0));
                inv_errors++;
            end
            if (ask_valid !== (ask_levels != '0)) begin
                $display("INV1 ask_valid=%0b but depth nonzero=%0b", ask_valid, (ask_levels != '0));
                inv_errors++;
            end

            // INV2: best pointer must address the level holding best qty.
            if (bid_valid && best_bid_qty !== bid_levels[best_bid*QTY_W +: QTY_W]) begin
                $display("INV2 bid pointer %0d qty %0d != depth %0d",
                         best_bid, best_bid_qty, bid_levels[best_bid*QTY_W +: QTY_W]);
                inv_errors++;
            end
            if (ask_valid && best_ask_qty !== ask_levels[best_ask*QTY_W +: QTY_W]) begin
                $display("INV2 ask pointer %0d qty %0d != depth %0d",
                         best_ask, best_ask_qty, ask_levels[best_ask*QTY_W +: QTY_W]);
                inv_errors++;
            end

            // INV3: no occupied bid level above the best bid.
            for (int k = 0; k < LEVELS; k++) begin
                if (bid_valid && k > best_bid && bid_levels[k*QTY_W +: QTY_W] != '0) begin
                    $display("INV3 occupied bid level %0d above best %0d", k, best_bid);
                    inv_errors++;
                end
                // INV4: no occupied ask level below the best ask.
                if (ask_valid && k < best_ask && ask_levels[k*QTY_W +: QTY_W] != '0) begin
                    $display("INV4 occupied ask level %0d below best %0d", k, best_ask);
                    inv_errors++;
                end
            end
        end
    end
    /* verilator lint_on BLKSEQ */

    int fd_s, fd_e, rc;
    int n, n_exp, i;
    int op, side, lvl, qty;
    int e_bv, e_bid, e_bq, e_av, e_ask, e_aq, e_sum;
    int errors = 0;
    int unsigned got_sum;

    // Idle-cycle stability check: with cmd_valid low the book must not move.
    logic            saved_bv, saved_av;
    logic [LVL_W-1:0] saved_bb, saved_ba;
    logic [QTY_W-1:0] saved_bbq, saved_baq;

    initial begin
        $dumpfile("build/wave.fst");
        $dumpvars(0, tb_order_book);

        fd_s = $fopen("stim.txt", "r");
        fd_e = $fopen("exp.txt", "r");
        if (fd_s == 0 || fd_e == 0) begin
            $fatal(1, "missing stim.txt/exp.txt - run 'make stim' first");
        end

        rc = $fscanf(fd_s, "%d", n);
        rc = $fscanf(fd_e, "%d", n_exp);
        if (n != n_exp) $fatal(1, "stim/exp length mismatch: %0d vs %0d", n, n_exp);
        $display("replaying %0d commands", n);

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (i = 0; i < n; i++) begin
            rc = $fscanf(fd_s, "%d %d %d %d", op, side, lvl, qty);
            if (rc != 4) $fatal(1, "stim step %0d: short read", i);
            rc = $fscanf(fd_e, "%d %d %d %d %d %d %d", e_bv, e_bid, e_bq, e_av, e_ask, e_aq, e_sum);
            if (rc != 7) $fatal(1, "exp step %0d: short read", i);

            // Validate the stimulus itself before trusting a mismatch.
            if (lvl < 0 || lvl >= LEVELS) $fatal(1, "stim step %0d: bad level %0d", i, lvl);
            if (qty <= 0 || qty > QTY_MASK) $fatal(1, "stim step %0d: bad qty %0d", i, qty);
            if (op < 0 || op > 2) $fatal(1, "stim step %0d: bad op %0d", i, op);
            if (side != 0 && side != 1) $fatal(1, "stim step %0d: bad side %0d", i, side);

            @(negedge clk);
            cmd_valid = 1'b1;
            cmd_op    = op[1:0];
            cmd_side  = side[0];
            cmd_level = lvl[LVL_W-1:0];
            cmd_qty   = qty[QTY_W-1:0];

            @(posedge clk);
            #1;
            cmd_valid = 1'b0;

            if (bid_valid !== (e_bv != 0)) begin
                $display("step %0d: bid_valid got=%0b exp=%0b", i, bid_valid, e_bv != 0);
                errors++;
            end else if (e_bv != 0 && (best_bid !== e_bid[LVL_W-1:0] || best_bid_qty !== e_bq[QTY_W-1:0])) begin
                $display("step %0d: bid got level=%0d qty=%0d, exp level=%0d qty=%0d",
                         i, best_bid, best_bid_qty, e_bid, e_bq);
                errors++;
            end

            if (ask_valid !== (e_av != 0)) begin
                $display("step %0d: ask_valid got=%0b exp=%0b", i, ask_valid, e_av != 0);
                errors++;
            end else if (e_av != 0 && (best_ask !== e_ask[LVL_W-1:0] || best_ask_qty !== e_aq[QTY_W-1:0])) begin
                $display("step %0d: ask got level=%0d qty=%0d, exp level=%0d qty=%0d",
                         i, best_ask, best_ask_qty, e_ask, e_aq);
                errors++;
            end

            got_sum = 0;
            for (int k = 0; k < LEVELS; k++) begin
                got_sum += 32'(bid_levels[k*QTY_W +: QTY_W]) + 32'(ask_levels[k*QTY_W +: QTY_W]);
            end
            if (got_sum !== e_sum[31:0]) begin
                $display("step %0d: depth sum got=%0d exp=%0d", i, got_sum, e_sum);
                errors++;
            end

            // Every few commands, prove that idle cycles are truly idle.
            if ((i % 5) == 0) begin
                saved_bv  = bid_valid;
                saved_bb  = best_bid;
                saved_bbq = best_bid_qty;
                saved_av  = ask_valid;
                saved_ba  = best_ask;
                saved_baq = best_ask_qty;

                repeat (2) @(posedge clk);
                #1;

                if (bid_valid !== saved_bv || best_bid !== saved_bb || best_bid_qty !== saved_bbq ||
                    ask_valid !== saved_av || best_ask !== saved_ba || best_ask_qty !== saved_baq) begin
                    $display("step %0d: book changed during idle cycles (cmd_valid=0)", i);
                    errors++;
                end
            end

            if (errors > 20) begin
                $display("too many errors, stopping at step %0d", i);
                i = n;
            end
        end

        $display("depth check: bid[0]=%0d ask[15]=%0d", bid_levels[0 +: QTY_W], ask_levels[15*QTY_W +: QTY_W]);

        if (errors == 0 && inv_errors == 0) begin
            $display("ALL TESTS PASS (%0d steps)", n);
        end else begin
            $display("FAILED: %0d mismatch(es), %0d invariant violation(s) in %0d steps",
                     errors, inv_errors, n);
        end

        $finish;
    end
endmodule
