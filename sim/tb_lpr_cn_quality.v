`timescale 1ns/1ps
module tb_lpr_cn_quality;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ft=0,de=0,enable=1;
    reg [11:0] x=0,y=0;
    reg [23:0] rgb=0;
    wire reject,qr,cb;
    wire [2:0] reason;
    integer kind,xx,yy,value;
    lpr_cn_segment #(.REQUIRE_CALIBRATION(0)) dut(.clk(clk),.rst_n(rst_n),.frame_tick(ft),
        .capture_enable(enable),.capture_busy(cb),.de(de),.found(1'b1),.green(1'b0),
        .x(x),.y(y),.left(12'd20),.right(12'd147),.top(12'd200),.bottom(12'd239),.rgb(rgb),
        .rejected(reject),.quality_rejected(qr),.reject_reason(reason));
    initial begin
        for(kind=0;kind<4;kind=kind+1) begin
            rst_n=0;repeat(4) @(negedge clk);rst_n=1;repeat(300) @(negedge clk);
            enable=1;ft=1;@(negedge clk);ft=0;repeat(650) @(negedge clk);
            if(!cb || dut.state!=3) $fatal(1,"capture did not start");
            // Scheduler must not gate the next frame_tick used to END capture.
            enable=0;
            for(yy=200;yy<240;yy=yy+1) begin
                for(xx=20;xx<148;xx=xx+1) begin
                    case(kind)
                        0:value=100;
                        1:value=(xx%8==0)?60:255;
                        2:value=60+((xx-20)>>1);
                        default:value=((xx>>2)%2)?200:40;
                    endcase
                    rgb={value[7:0],value[7:0],value[7:0]};x=xx;y=yy;de=1;@(negedge clk);
                end
                de=0;repeat(4) @(negedge clk);
            end
            ft=1;@(negedge clk);ft=0;
            wait(reject || dut.state==30);@(negedge clk);
            if(kind<3 && (!reject || !qr || reason!=kind+2))
                $fatal(1,"quality rejection wrong kind=%d reason=%d edges=%d",kind,reason,dut.edge_count);
            if(kind==3 && (reject || qr || reason!=0)) $fatal(1,"sharp contrast ROI rejected");
        end
        $display("PASS tb_lpr_cn_quality contrast clipping blur sharp admission_vs_completion");$finish;
    end
    initial begin #5000000;$fatal(1,"quality timeout");end
endmodule
