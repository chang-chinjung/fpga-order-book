VERILATOR ?= verilator
PYTHON    ?= python3
YOSYS     ?= yosys
NEXTPNR   ?= nextpnr-ecp5
VCOV      ?= verilator_coverage

TOP       := tb_order_book
SRC       := rtl/order_book.sv tb/tb_order_book.sv
RTL       := rtl/order_book.sv rtl/order_book_top.sv
SYNTH_TOP := order_book_top
JSON      := build/order_book_ecp5.json
FREQ_MHZ  ?= 300

.PHONY: stim lint sim synth pnr coverage all clean

all: lint sim

stim:
	$(PYTHON) model/book_model.py --n 200 --seed 42 --dir .

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal --top-module $(TOP) $(SRC)

sim: stim
	$(VERILATOR) --binary --timing --assert --trace-fst -j 0 -Wall -Wno-fatal \
		--top-module $(TOP) --Mdir build $(SRC)
	./build/V$(TOP)

# Functional check of the two-stage pipelined variant (same stimulus as sim).
sim-pipe2: stim
	mkdir -p build/pipe2
	$(VERILATOR) --binary --timing --assert -j 0 -Wall -Wno-fatal \
		--top-module tb_order_book_pipe2 --Mdir build/pipe2 \
		rtl/order_book_pipe2.sv tb/tb_order_book_pipe2.sv
	./build/pipe2/Vtb_order_book_pipe2

# 合成（不需要板子，也不需要授權）
synth:
	mkdir -p build
	$(YOSYS) -p "read_verilog -sv $(RTL); synth_ecp5 -top $(SYNTH_TOP) -json $(JSON)"

# Timing experiment: two-stage pipelined variant (see rtl/order_book_pipe2.sv)
synth-pipe2:
	mkdir -p build
	$(YOSYS) -p "read_verilog -sv rtl/order_book_pipe2.sv; synth_ecp5 -top order_book_pipe2 -json build/order_book_pipe2.json"

pnr-pipe2: synth-pipe2
	$(NEXTPNR) --85k --package CABGA381 --json build/order_book_pipe2.json \
		--freq $(FREQ_MHZ) --textcfg build/order_book_pipe2.config \
		2>&1 | tee build/pnr_pipe2.log

# Timing experiment 2: three-stage, adder split into two 8-bit halves
synth-pipe3:
	mkdir -p build
	$(YOSYS) -p "read_verilog -sv rtl/order_book_pipe3.sv; synth_ecp5 -top order_book_pipe3 -json build/order_book_pipe3.json"

pnr-pipe3: synth-pipe3
	$(NEXTPNR) --85k --package CABGA381 --json build/order_book_pipe3.json \
		--freq $(FREQ_MHZ) --textcfg build/order_book_pipe3.config \
		2>&1 | tee build/pnr_pipe3.log

# Place & route + STA（需要 nextpnr-ecp5；不需要板子）
pnr: synth
	$(NEXTPNR) --85k --package CABGA381 --json $(JSON) \
		--freq $(FREQ_MHZ) --textcfg build/order_book.config \
		2>&1 | tee build/pnr.log

coverage: stim
	mkdir -p build/cov
	$(VERILATOR) --binary --timing --assert --coverage-line -j 0 -Wall -Wno-fatal \
		--top-module $(TOP) --Mdir build/cov $(SRC)
	./build/cov/V$(TOP)
	$(VCOV) --write-info build/cov/lcov.info coverage.dat
	$(VCOV) --annotate build/cov/annotated coverage.dat
	$(PYTHON) tools/cov_report.py build/cov/lcov.info

coverage-pipe2: stim
	mkdir -p build/cov_pipe2
	$(VERILATOR) --binary --timing --assert --coverage-line -j 0 -Wall -Wno-fatal \
		--top-module tb_order_book_pipe2 --Mdir build/cov_pipe2 \
		rtl/order_book_pipe2.sv tb/tb_order_book_pipe2.sv
	./build/cov_pipe2/Vtb_order_book_pipe2
	$(VCOV) --write-info build/cov_pipe2/lcov.info coverage.dat
	$(PYTHON) tools/cov_report.py build/cov_pipe2/lcov.info

# ---- v1.1 integrated book (1,024 levels) ----
stim-v11:
	$(PYTHON) model/book_v11_model.py --n 400 --seed 11 --dir .

sim-v11: stim-v11
	mkdir -p build/v11
	$(VERILATOR) --binary --timing --assert -j 0 -Wall -Wno-fatal \
		--top-module tb_order_book_v11 --Mdir build/v11 \
		rtl/bitmap_best.sv rtl/order_book_v11.sv tb/tb_order_book_v11.sv
	./build/v11/Vtb_order_book_v11

synth-v11:
	mkdir -p build
	$(YOSYS) -p "read_verilog -sv rtl/bitmap_best.sv rtl/order_book_v11.sv; synth_ecp5 -top order_book_v11 -json build/order_book_v11.json"

pnr-v11: synth-v11
	$(NEXTPNR) --85k --package CABGA381 --json build/order_book_v11.json \
		--freq $(FREQ_MHZ) --textcfg build/order_book_v11.config \
		2>&1 | tee build/pnr_v11.log

clean:
	rm -rf build stim.txt exp.txt coverage.dat stim_bitmap.txt exp_bitmap.txt stim_v11.txt exp_v11.txt

# ---- v1.1: bitmap best-price block ----
stim-bitmap:
	$(PYTHON) model/bitmap_model.py --n 500 --seed 7 --dir .

sim-bitmap: stim-bitmap
	mkdir -p build/bitmap
	$(VERILATOR) --binary --timing --assert -j 0 -Wall -Wno-fatal \
		--top-module tb_bitmap_best --Mdir build/bitmap \
		rtl/bitmap_best.sv tb/tb_bitmap_best.sv
	./build/bitmap/Vtb_bitmap_best

synth-bitmap:
	mkdir -p build
	$(YOSYS) -p "read_verilog -sv rtl/bitmap_best.sv; synth_ecp5 -top bitmap_best -json build/bitmap_best.json"

pnr-bitmap: synth-bitmap
	$(NEXTPNR) --85k --package CABGA381 --json build/bitmap_best.json \
		--freq $(FREQ_MHZ) --textcfg build/bitmap_best.config \
		2>&1 | tee build/pnr_bitmap.log
