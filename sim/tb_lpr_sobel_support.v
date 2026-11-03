`timescale 1ns/1ps
module tb_lpr_sobel_support;
reg clk=0;always #5 clk=~clk;
reg rst=0,ft=0,de=0;
reg [11:0] x=0,y=0;
reg [7:0] gray=0;
wire supported,edge_pixel;
integer xx,yy;
lpr_sobel_support #(.WIDTH(128)) dut(clk,rst,ft,de,1'b1,x,y,12'd10,12'd110,12'd5,12'd35,gray,supported,edge_pixel,1'b0);
task frame;
input strokes;
begin
 for(yy=0;yy<40;yy=yy+1) begin
  for(xx=0;xx<128;xx=xx+1) begin
   x=xx;y=yy;de=1;gray=strokes && xx>15 && xx<105 && yy>8 && yy<32 && ((xx/6)%2)?20:220;@(negedge clk);
  end
  de=0;repeat(5) @(negedge clk);
 end
 ft=1;@(negedge clk);ft=0;repeat(3) @(negedge clk);
end
endtask
initial begin
 repeat(4) @(negedge clk);rst=1;
 frame(0);frame(0);if(supported) $fatal(1,"uniform region passed edge gate");
 frame(1);if(!supported) $fatal(1,"character strokes failed Sobel gate");
 frame(0);if(supported) $fatal(1,"stale edge evidence");
 $display("PASS tb_lpr_sobel_support uniform_reject strokes_accept stale_clear");$finish;
end
endmodule
