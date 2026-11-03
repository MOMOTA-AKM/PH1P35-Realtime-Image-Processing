`timescale 1ns/1ps
module tb_lpr_cn_sampler;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,update=0,found=1,green=0,tracked=1,changed=0;
    reg sb=0,ob=0,err=0,started=0;
    reg [11:0] l=300,r=780,t=300,b=419;
    wire allow;
    lpr_cn_sampler dut(.clk(clk),.rst_n(rst_n),.update(update),.found(found),.green(green),
        .tracked(tracked),.changed(changed),.segment_busy(sb),.ocr_busy(ob),.memory_error(err),
        .fast_mode(1'b0),.capture_started(started),.left(l),.right(r),.top(t),.bottom(b),.allow_capture(allow));
    task tick;begin update=1;@(negedge clk);update=0;repeat(3) @(negedge clk);end endtask
    initial begin
        #22;rst_n=1;@(negedge clk);
        if(allow) $fatal(1,"unwarmed sampler admitted ROI");
        tick;tick;tick;if(!allow) $fatal(1,"stable frame not eligible");
        started=1;@(negedge clk);started=0;@(negedge clk);
        if(allow) $fatal(1,"cooldown not reset");
        tick;if(allow) $fatal(1,"interval too short");tick;if(!allow) $fatal(1,"third frame not eligible");
        sb=1;#1;if(allow) $fatal(1,"segment busy ignored");sb=0;ob=1;#1;
        if(allow) $fatal(1,"OCR busy ignored");ob=0;err=1;#1;
        if(allow) $fatal(1,"RAM error ignored");err=0;
        l=340;r=820;#1;if(allow) $fatal(1,"moving ROI admitted");tick;
        tracked=0;#1;if(allow) $fatal(1,"untracked admitted");tracked=1;
        changed=1;@(negedge clk);changed=0;@(negedge clk);
        if(allow) $fatal(1,"identity change not flushed");
        tick;tick;tick;if(!allow) $fatal(1,"reacquisition failed");
        found=0;#1;if(allow) $fatal(1,"missing target admitted");
        $display("PASS tb_lpr_cn_sampler interval stable busy movement identity RAM");$finish;
    end
endmodule
