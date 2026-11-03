`timescale 1ns/1ps
module tb_green_components_limits;
reg clk=0;always #5 clk=~clk;
reg rst=0,start=0;reg [9:0] width=96;reg [7:0] height=96;
wire busy,done,overflow,we;wire [16:0] ra,wa;
reg pixel_q;reg memory[0:131071];integer x,y,i;
lpr_green_components dut(clk,rst,start,width,height,busy,done,overflow,ra,pixel_q,we,wa);
always @(posedge clk) begin pixel_q<=memory[ra];if(we) memory[wa]<=0;end
task launch;
 begin @(negedge clk);start=1;@(negedge clk);start=0;wait(done);repeat(3) @(negedge clk);end
endtask
initial begin
 for(i=0;i<131072;i=i+1) memory[i]=0;
 for(y=0;y<96;y=y+1) for(x=0;x<96;x=x+1) memory[y*640+x]=1;
 repeat(4) @(negedge clk);rst=1;launch;
 if(!overflow || busy) $fatal(1,"large connected region did not safely overflow");
 // A fresh start must clear the old overflow and visited flags.
 for(i=0;i<131072;i=i+1) memory[i]=0;
 width=64;height=48;
 // Boundary glyphs and a diagonal 8-connected glyph, with no wrapped neighbors.
 for(y=0;y<25;y=y+1) memory[y*640]=1;
 for(y=20;y<48;y=y+1) memory[y*640+63]=1;
 for(y=10;y<30;y=y+1) memory[y*640+20+((y-10)/4)]=1;
 launch;
 if(overflow) $fatal(1,"overflow was not cleared on restart");
 for(y=0;y<48;y=y+1) for(x=0;x<64;x=x+1)
  if(memory[y*640+x]!==(((x==0 && y<25)||(x==63 && y>=20)||(y>=10 && y<30 && x==20+((y-10)/4)))?1'b1:1'b0))
   $fatal(1,"boundary or 8-connectivity mismatch %0d,%0d",x,y);
 // Asynchronous reset during initialization must stop all writes and processing.
 @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(20) @(negedge clk);rst=0;repeat(4) @(negedge clk);
 if(busy || done || we) $fatal(1,"reset failed to cancel cleanup");
 $display("PASS green_components_limits overflow rejection restart boundaries diagonal reset");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
