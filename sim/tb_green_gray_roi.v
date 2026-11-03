`timescale 1ns/1ps
module tb_green_gray_roi;
reg clk=0;always #5 clk=~clk;
reg rst=0,we=0,start=0;reg [16:0] wa=0;reg [3:0] gray=0;
reg [9:0] w=35;reg [7:0] h=19;
wire busy,done,mwe,mp;wire [16:0] ma;
reg [3:0] data[0:122879];reg seen[0:122879];
integer x,y,i,xx,yy,s,c,expected,total,tx,ty;
lpr_green_gray_roi dut(clk,rst,we,start,wa,gray,w,h,busy,done,mwe,ma,mp);
always @(negedge clk) if(mwe) begin
 x=ma%640;y=ma/640;tx=(x/16)*16;ty=(y/16)*16;s=0;c=0;
 for(yy=ty;yy<ty+16 && yy<h;yy=yy+1)
  for(xx=tx;xx<tx+16 && xx<w;xx=xx+1) begin s=s+data[yy*640+xx];c=c+1;end
 expected=(s>data[ma]*c+c) && x>=w/32 && x<w-w/32 && y>=h/16 && y<h-h/16;
 if(mp!==expected[0] || seen[ma]) $fatal(1,"mask mismatch/duplicate address=%0d",ma);
 seen[ma]=1;total=total+1;
end
initial begin
 total=0;for(i=0;i<122880;i=i+1) seen[i]=0;
 repeat(4) @(negedge clk);rst=1;
 for(yy=0;yy<19;yy=yy+1) for(xx=0;xx<35;xx=xx+1) begin
  wa=yy*640+xx;gray=(xx+yy)%16;data[wa]=gray;we=1;@(negedge clk);
 end
 we=0;start=1;@(negedge clk);start=0;wait(done);repeat(3) @(negedge clk);
 if(total!=35*19) $fatal(1,"mask missing pixels %0d",total);
 $display("PASS gray ROI partial tiles exact mean-minus-offset mask every address");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
