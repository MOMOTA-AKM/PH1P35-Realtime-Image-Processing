`timescale 1ns/1ps
module tb_v24_address;
reg [7:0] ty,py,ny,sy;
reg [9:0] tx,px,nx;
wire [8:0] ay={1'b0,ty}+{1'b0,py};
wire [16:0] old_tile=(ty+py)*640+tx+px;
wire [16:0] new_tile=({ay,9'b0}+{ay,7'b0})+tx+px;
wire [8:0] next_sy={1'b0,sy}+9'd1;
wire [16:0] old_scan=(sy+1)*640;
wire [16:0] new_scan={next_sy,9'b0}+{next_sy,7'b0};
wire [16:0] old_neighbor=ny*640+nx;
wire [16:0] new_neighbor=({1'b0,ny,9'b0}+{1'b0,ny,7'b0})+nx;
integer i;
initial begin
 for(i=0;i<100000;i=i+1) begin
  ty=$random;py=$random;tx=$random;px=$random;
  sy=$random;ny=$random;nx=$random;#1;
  if(old_tile!==new_tile || old_scan!==new_scan || old_neighbor!==new_neighbor)
   $fatal(1,"address mismatch at %0d",i);
 end
 $display("PASS v24 shared address exact modulo equivalence: 100000 random cases");$finish;
end
endmodule
