# 通用 SDC（nextpnr / OpenSTA / 其他 STA 工具）
# 以 300 MHz 為目標：period = 3.333 ns

create_clock -name clk -period 3.333 [get_ports clk]

set_input_delay  -clock clk 1.0 [all_inputs]
set_output_delay -clock clk 1.0 [all_outputs]

# 非同步重置（與 XDC 一致；若工具不支援 remove_from_collection，先全設再排除 clk）
set_false_path -from [get_ports rst_n]
