`timescale 1ns/1ps
module tb_ocr_latency;
reg clk=0;always #5 clk=~clk;
reg rst=0,capture=0,cancel=0,finish=0,accept=0,publish=0;
wire [15:0] bcd;wire valid;
lpr_ocr_latency #(.CYCLES_PER_MS(10)) dut(clk,rst,capture,cancel,finish,accept,publish,bcd,valid);
task begin_capture;begin capture=1;@(negedge clk);capture=0;end endtask
task result;input accepted;begin finish=1;accept=accepted;@(negedge clk);finish=0;accept=0;end endtask
task confirm;begin publish=1;@(negedge clk);publish=0;end endtask
initial begin
 repeat(3) @(negedge clk);rst=1;@(negedge clk);
 if(valid) $fatal(1,"startup should hide time");
 begin_capture;repeat(24) @(negedge clk);result(1);
 if(dut.pending!==16'h0002 || valid) $fatal(1,"elapsed or pre-vote visibility wrong");
 confirm;if(!valid || bcd!==16'h0002) $fatal(1,"confirmed time missing");
 begin_capture;repeat(9) @(negedge clk);result(1); // exact 10-clock boundary
 if(dut.pending!==16'h0001) $fatal(1,"boundary ms wrong");
 cancel=1;@(negedge clk);cancel=0;confirm;
 if(bcd!==16'h0002) $fatal(1,"cancel must retain old confirmed display");
 begin_capture;repeat(110) @(negedge clk);result(0);confirm;
 if(bcd!==16'h0002) $fatal(1,"rejected result replaced time");
 begin_capture;repeat(99989) @(negedge clk);result(1);confirm;
 if(bcd!==16'h9999) $fatal(1,"BCD carry failed %h",bcd);
 begin_capture;repeat(100050) @(negedge clk);result(1);confirm;
 if(bcd!==16'h9999) $fatal(1,"saturation failed");
 rst=0;@(negedge clk);if(valid) $fatal(1,"reset failed");
 $display("PASS ocr_latency capture_to_done floor_ms boundary vote_lock reject cancel retention BCD saturation reset");$finish;
end
endmodule
