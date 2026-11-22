# Vivado timing run — Kintex-7 量測腳本
#
# 用法（在有 Vivado 的機器上）：
#   vivado -mode batch -source scripts/vivado_timing.tcl
#
# 產出：
#   build/vivado/order_book_pipe3/vivado.log        合成與實作日誌
#   build/vivado/order_book_pipe3/timing_summary.rpt  WNS / 各時脈 slack
#   build/vivado/order_book_pipe3/utilization.rpt     資源報告
#
# 注意：這只是量測腳本，不會產生 bitstream，也不需要板子。

set root      [file normalize [file join [file dirname [info script]] ..]]
set outdir    [file join $root build vivado order_book_pipe3]
set part      xc7k325tffg900-2
set top       order_book_pipe3
set period_ns 3.333

file mkdir $outdir

read_verilog -sv [file join $root rtl order_book_pipe3.sv]
read_xdc      [file join $root constraints order_book.xdc]

synth_design -top $top -part $part -flatten_hierarchy rebuilt
opt_design
place_design
route_design

report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $outdir timing_summary.rpt]
report_utilization -file [file join $outdir utilization.rpt]
report_clock_utilization -file [file join $outdir clock_utilization.rpt]

set wns [get_property SLACK [get_timing_paths -delay_type max]]
puts "=============================================="
puts "Target period : ${period_ns} ns (300 MHz)"
puts "Worst slack   : ${wns} ns"
puts "=============================================="

write_checkpoint -force [file join $outdir post_route.dcp]
