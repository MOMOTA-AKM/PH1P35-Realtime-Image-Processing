`timescale 1ns/1ps
module tb_green_components;
reg clk=0;always #5 clk=~clk;
reg rst=0,start=0;wire busy,done,overflow,we;wire [16:0] ra,wa;
reg pixel_q;reg memory[0:122879];integer x,y,i,cleared;
lpr_green_components dut(clk,rst,start,10'd64,8'd48,busy,done,overflow,ra,pixel_q,we,wa);
always @(posedge clk) begin pixel_q<=memory[ra];if(we) memory[wa]<=0;end
initial begin
 cleared=0;
 for(i=0;i<122880;i=i+1) memory[i]=0;
 // Tall narrow glyph, short dot, wide frame, disconnected speck.
 for(y=8;y<38;y=y+1) for(x=15;x<20;x=x+1) memory[y*640+x]=1;
 for(y=9;y<12;y=y+1) for(x=30;x<33;x=x+1) memory[y*640+x]=1;
 for(x=2;x<62;x=x+1) memory[2*640+x]=1;
 memory[40*640+40]=1;
 repeat(4) @(negedge clk);rst=1;start=1;@(negedge clk);start=0;
 wait(done);repeat(3) @(negedge clk);
 if(overflow) $fatal(1,"unexpected overflow");
 for(y=0;y<48;y=y+1) for(x=0;x<64;x=x+1)
  if(memory[y*640+x]!==((y>=8 && y<38 && x>=15 && x<20)?1'b1:1'b0)) $fatal(1,"cleanup mismatch %0d %0d",x,y);
 $display("PASS bounded connected cleanup glyph retained dot frame speck removed");$finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
