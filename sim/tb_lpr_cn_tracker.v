`timescale 1ns/1ps
module tb_lpr_cn_tracker #(parameter OUTLIER_HOLD=0);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,update=0,found=0,green=0;
    reg [11:0] l=300,r=780,t=300,b=419;
    wire tracked,color,changed;
    wire [7:0] epoch;
    wire [11:0] tl,tr,tt,tb;
    reg [7:0] old_epoch;
    lpr_cn_tracker #(.OUTLIER_HOLD(OUTLIER_HOLD)) dut(.clk(clk),.rst_n(rst_n),.update(update),.found(found),.green(green),
        .left(l),.right(r),.top(t),.bottom(b),.tracked(tracked),.track_green(color),
        .changed(changed),.epoch(epoch),.track_left(tl),.track_right(tr),.track_top(tt),.track_bottom(tb));
    task tick;
        begin update=1;@(negedge clk);update=0;repeat(5) @(negedge clk);end
    endtask
    initial begin
        #22;rst_n=1;@(negedge clk);found=1;
        tick;if(tracked) $fatal(1,"one-frame false acquisition");
        tick;if(tracked) $fatal(1,"two-frame false acquisition");
        tick;if(!tracked || tl!=300) $fatal(1,"acquisition failed");
        l=308;r=788;tick;if(tl!=304 || tr!=784) $fatal(1,"jitter smoothing failed");
        if(OUTLIER_HOLD!=0) begin
            old_epoch=epoch;l=600;r=1080;
            repeat(OUTLIER_HOLD) begin tick;if(!tracked || epoch!=old_epoch || tl!=304) $fatal(1,"outlier changed accepted box");end
            l=308;r=788;tick;if(!tracked || epoch!=old_epoch) $fatal(1,"outlier recovery changed identity");
        end
        found=0;tick;tick;tick;if(!tracked) $fatal(1,"short misses not held");
        found=1;tick;if(!tracked) $fatal(1,"reassociation failed");
        old_epoch=epoch;green=1;tick;
        if(tracked || epoch==old_epoch) $fatal(1,"color replacement kept stale identity");
        tick;tick;if(!tracked || !color) $fatal(1,"green reacquisition failed");
        old_epoch=epoch;l=600;r=1080;repeat(OUTLIER_HOLD+1) tick;
        if(tracked || epoch==old_epoch) $fatal(1,"position replacement kept stale identity");
        tick;tick;if(!tracked || tl!=600) $fatal(1,"position reacquisition failed");
        found=0;tick;tick;tick;tick;if(tracked) $fatal(1,"expired track not cleared");
        found=1;tick;found=0;tick;found=1;tick;tick;
        if(tracked) $fatal(1,"nonconsecutive detections acquired");
        $display("PASS tb_lpr_cn_tracker acquire jitter hold expiry replacement epoch consecutive");$finish;
    end
endmodule
