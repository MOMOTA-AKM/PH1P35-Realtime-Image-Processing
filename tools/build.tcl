# Run with: td_commands_prompt.exe tools/build.tcl
# Set LPR_BUILD_STEP=design|rtl|gate|bitgen to select the terminal step.
set root [file normalize [file join [file dirname [info script]] ..]]
cd [file join $root td_project]
set build_step bitgen
if {![info exists ::env(LPR_BUILD_DIR)]} {set ::env(LPR_BUILD_DIR) build/public}
if {![info exists ::env(LPR_PROJECT_ROOT)]} {set ::env(LPR_PROJECT_ROOT) $root}
if {[info exists ::env(LPR_BUILD_STEP)]} {set build_step $::env(LPR_BUILD_STEP)}
if {[catch {
set build_start [clock seconds]
# Single-run mode avoids a TD 6.2.1 Windows launcher defect where launch_runs
# constructs a nonexistent td_commands_prompt_commands_prompt.exe child path.
file mkdir [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR)]
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project -single_run hx1p35_lpr.al
elaborate -top hx1p35_lpr_top
if {$build_step eq "design"} { puts "LPR_BUILD_SUCCESS design"; close_project; exit }
read_adc [file join $root constraints hx1p35.adc]
read_ip_adc -ip ddr2 -file [file join $root vendor user_source hdl_source ph1p35_ddr ddr2 src adc ddr2.adc]
optimize_rtl
report_area -file [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) rtl.area]
if {$build_step eq "rtl"} { puts "LPR_BUILD_SUCCESS rtl"; close_project; exit }
read_sdc [file join $root vendor td_project camera_to_dsi_display.sdc]
read_sdc -ip ddr2 [file join $root vendor user_source hdl_source ph1p35_ddr ddr2 src sdc ddr2.sdc]
read_sdc -ip w128_d512_fifo [file join $root vendor user_source ip_source w128_d512_fifo w128_d512_fifo.tcl]
optimize_gate
legalize_phy_inst
report_area -file [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) gate.area]
export_db [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) gate.db]
update_timing -mode basic
report_timing_summary -file [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) gate_timing.rpt]
if {$build_step eq "gate"} { puts "LPR_BUILD_SUCCESS gate"; close_project; exit }
place
route
export_db [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) route.db]
report_area -file [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) route.area]
update_timing -mode final
report_timing_summary -file [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) timing.rpt]
bitgen -bit [file join $::env(LPR_PROJECT_ROOT) $::env(LPR_BUILD_DIR) hx1p35_lpr.bit]
close_project
puts "LPR_BUILD_SUCCESS bitgen"
puts "LPR_BUILD_SECONDS [expr {[clock seconds]-$build_start}]"
} build_error]} { puts stderr "LPR_BUILD_FAILED: $build_error"; exit 1 }
exit
