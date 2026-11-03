`timescale 1ns/1ps
module tb_lpr_cn_vote;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,clear=0,start=0,green=0;
    reg [63:0] plate=0;
    wire busy,done,confirmed,color;
    wire [63:0] result;
    wire [3:0] votes;
    lpr_cn_vote dut(.clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.green(green),
        .required_runtime(3'd3),.plate(plate),.busy(busy),.done(done),.confirmed(confirmed),.result_green(color),.result_plate(result),.votes(votes));
    task push;
        input [63:0] n;input integer expected;input yes;
        begin
            plate=n;start=1;@(negedge clk);start=0;wait(done);@(negedge clk);
            if(votes!=expected || confirmed!==yes || result!==n || color!==green)
                $fatal(1,"vote wrong n=%h votes=%d expected=%d confirmed=%b",n,votes,expected,confirmed);
        end
    endtask
    initial begin
        #22;rst_n=1;@(negedge clk);
        push(64'h111,1,0);push(64'h222,1,0);push(64'h111,2,0);push(64'h333,1,0);push(64'h111,3,1);
        push(64'h222,2,0);push(64'h222,2,0);push(64'h222,3,1);
        green=1;push(64'h222,1,0);
        clear=1;@(negedge clk);clear=0;@(negedge clk);push(64'h222,1,0);
        // A target change while a comparison is in flight cancels it.
        start=1;@(negedge clk);start=0;clear=1;@(negedge clk);clear=0;repeat(8) @(negedge clk);
        if(busy || done || confirmed || votes!=0) $fatal(1,"in-flight vote survived clear");
        $display("PASS tb_lpr_cn_vote three_of_five outliers rolling_window color clear inflight");$finish;
    end
endmodule
