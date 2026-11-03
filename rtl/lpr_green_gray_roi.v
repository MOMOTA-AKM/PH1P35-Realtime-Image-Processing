// Experimental bounded 4-bit grayscale ROI. Two serial passes per 16x16 tile.
// Not connected-component labeling and not a substitute for OCR confidence.
module lpr_green_gray_roi(
 input clk,rst_n,capture_we,start,
 input [16:0] capture_address,
 input [3:0] capture_gray,
 input [9:0] width,
 input [7:0] height,
 output reg busy,done,mask_we,
 output reg [16:0] mask_address,
 output reg mask_pixel
);
 (* ram_style="bram" *) reg [3:0] gray_mem[0:131071];
 reg [16:0] ra;
 reg [3:0] q;
 always @(posedge clk) begin
  if(capture_we) gray_mem[capture_address]<=capture_gray;
  q<=gray_mem[ra];
 end
 reg [2:0] state;
 reg [9:0] w,tx,px;
 reg [7:0] h,ty,py;
 reg pass;
 reg [11:0] sum;
 reg [8:0] count;
 wire last_x=px==15 || tx+px+1>=w;
 wire last_y=py==15 || ty+py+1>=h;
 wire [12:0] product=q*count;
 // Same low 17 address bits as (ty+py)*640+tx+px. Explicit constant
 // shifts prevent two mutually exclusive address sites using DSP blocks.
 wire [8:0] address_y={1'b0,ty}+{1'b0,py};
 wire [16:0] tile_address=({address_y,9'b0}+{address_y,7'b0})+tx+px;
 // Mean minus one 4-bit gray level (~16/255). No divider or floating point.
 wire dark={1'b0,sum}>product+count;
 wire interior=tx+px>=(w>>5) && tx+px<w-(w>>5) &&
               ty+py>=(h>>4) && ty+py<h-(h>>4);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=0;busy<=0;done<=0;mask_we<=0;mask_address<=0;mask_pixel<=0;
   ra<=0;w<=0;h<=0;tx<=0;ty<=0;px<=0;py<=0;sum<=0;count<=0;pass<=0;
  end else begin
   done<=0;mask_we<=0;
   case(state)
    0:if(start) begin
     if(width==0 || width>640 || height==0 || height>192) done<=1;
     else begin
      w<=width;h<=height;tx<=0;ty<=0;px<=0;py<=0;
      sum<=0;count<=0;pass<=0;busy<=1;state<=1;
     end
    end
    1:begin ra<=tile_address;state<=2;end
    2:state<=3;
    3:begin
     if(!pass) begin sum<=sum+q;count<=count+1'b1;end
     else begin mask_we<=1;mask_address<=tile_address;mask_pixel<=dark && interior;end
     if(last_x && last_y) begin
      px<=0;py<=0;
      if(!pass) begin pass<=1;state<=1;end
      else if(tx+16<w) begin tx<=tx+16;sum<=0;count<=0;pass<=0;state<=1;end
      else if(ty+16<h) begin tx<=0;ty<=ty+16;sum<=0;count<=0;pass<=0;state<=1;end
      else state<=4;
     end else begin
      if(last_x) begin px<=0;py<=py+1'b1;end else px<=px+1'b1;
      state<=1;
     end
    end
    4:begin busy<=0;done<=1;state<=0;end
    default:begin busy<=0;state<=0;end
   endcase
  end
 end
endmodule
