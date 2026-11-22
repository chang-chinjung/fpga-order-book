# Vivado 時序約束（XDC）
# 目標：300 MHz（3.333 ns）
#
# 用法：add_files -fileset constrs_1 constraints/order_book.xdc
# 報告：report_timing_summary -delay_type min_max
#
# 注意：這是「單一時脈域 + 非同步重置」的最小約束集。
# 任何新增的時脈域或 I/O 介面都必須補對應約束，否則 STA 會給出無意義的綠燈。

create_clock -name clk -period 3.333 -waveform {0 1.667} [get_ports clk]

# 輸入在上游暫存器輸出後 1.0 ns 穩定；輸出需在下游暫存器前 1.0 ns 抵達。
# 實際值要依板級/介面規格調整，這裡是保守預設。
set_input_delay  -clock clk -max 1.0 [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay  -clock clk -min 0.0 [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock clk -max 1.0 [all_outputs]
set_output_delay -clock clk -min 0.0 [all_outputs]

# 非同步重置：不做資料路徑時序分析，但 recovery/removal 仍由工具檢查。
# 若重置在晶片內有同步器，請改為只對同步器之前設 false_path。
set_false_path -from [get_ports rst_n]

# 若之後加入跨時脈域 FIFO，必須明確宣告：
# set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]
# set_max_delay -datapath_only -from [get_clocks clk_a] -to [get_clocks clk_b] <ns>
