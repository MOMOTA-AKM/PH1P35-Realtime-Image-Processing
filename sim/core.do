onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
vlib core_work
vmap work core_work
vlog -sv +define+LPR_BEHAVIORAL_RAM ../rtl/lpr_*.v tb_*.v
foreach test {tb_lpr_cn_sampler tb_lpr_cn_vote tb_lpr_cn_detector tb_lpr_cn_tracker tb_lpr_cn_quality tb_lpr_sobel_support tb_green_gray_roi tb_green_components tb_green_components_limits tb_ocr_latency tb_v24_address} {
 vsim $test
 onfinish stop
 run -all
 quit -sim
}
quit -code 0 -f
