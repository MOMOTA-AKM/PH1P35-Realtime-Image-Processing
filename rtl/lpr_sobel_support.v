// Streaming 3x3 Sobel evidence inside the previous color candidate.
// Color remains the proposal; EDGE mode requires independent edge evidence.
module lpr_sobel_support # (parameter WIDTH=1280,GREEN_SCALE_ASSOCIATION=0)(
 input clk,rst_n,frame_tick,de,found,
 input [11:0] x,y,left,right,top,bottom,
 input [7:0] gray,
 output reg supported,
 output reg edge_pixel,
 input green
);
 (* ram_style="bram" *) reg [7:0] line0[0:WIDTH-1];
 (* ram_style="bram" *) reg [7:0] line1[0:WIDTH-1];
 reg [7:0] q0,q1,gd,a00,a01,a10,a11,a20,a21;
 reg dd;
 reg [11:0] xd,yd,pl,pr,pt,pb;
 reg have;
 reg previous_green;
 wire [11:0] previous_width=pr-pl+1'b1,previous_height=pb-pt+1'b1;
 wire [11:0] scale_dx=(previous_width>>4)>48?12'd48:
     (previous_width>>4)>32?(previous_width>>4):12'd32;
 wire [11:0] scale_dy=(previous_height>>3)>40?12'd40:
     (previous_height>>3)>24?(previous_height>>3):12'd24;
 wire [11:0] limit_dx=GREEN_SCALE_ASSOCIATION && green?scale_dx:12'd32;
 wire [11:0] limit_dy=GREEN_SCALE_ASSOCIATION && green?scale_dy:12'd24;
 reg [17:0] edges;
 reg [15:0] upper_edges;
 wire [9:0] posx={2'b0,q1}+{1'b0,q0,1'b0}+{2'b0,gd};
 wire [9:0] negx={2'b0,a00}+{1'b0,a10,1'b0}+{2'b0,a20};
 wire [9:0] posy={2'b0,a20}+{1'b0,a21,1'b0}+{2'b0,gd};
 wire [9:0] negy={2'b0,a00}+{1'b0,a01,1'b0}+{2'b0,q1};
 wire [9:0] gx=posx>negx?posx-negx:negx-posx;
 wire [9:0] gy=posy>negy?posy-negy:negy-posy;
 wire [10:0] magnitude={1'b0,gx}+{1'b0,gy};
 wire in_roi=have && xd>pl+2 && xd<pr-1 && yd>pt+2 && yd<pb-1;
 always @(posedge clk) begin
  if(de && x<WIDTH) begin q0<=line0[x];q1<=line1[x];line0[x]<=gray;end
  if(dd && xd<WIDTH) line1[xd]<=q0;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   dd<=0;xd<=0;yd<=0;gd<=0;a00<=0;a01<=0;a10<=0;a11<=0;a20<=0;a21<=0;
   pl<=0;pr<=0;pt<=0;pb<=0;have<=0;edges<=0;upper_edges<=0;supported<=0;
   edge_pixel<=0;previous_green<=0;
  end else begin
   dd<=de;xd<=x;yd<=y;gd<=gray;
   if(dd) begin
    a00<=a01;a01<=q1;a10<=a11;a11<=q0;a20<=a21;a21<=gd;
    if(xd>=2 && yd>=2 && in_roi && magnitude>=120) begin
     if(edges!=18'h3ffff) edges<=edges+1'b1;
     if(yd<pt+((pb-pt)>>1) && upper_edges!=16'hffff) upper_edges<=upper_edges+1'b1;
    end
    // Full-frame display output.  This is deliberately independent of the
    // color ROI used by the EDGE acceptance gate above.
    edge_pixel <= (magnitude >= 120);
   end else begin
    edge_pixel <= 1'b0;
   end
   if(frame_tick) begin
    // Reject a stale edge count if the color proposal has moved/replaced.
    supported<=found && have && (!GREEN_SCALE_ASSOCIATION || green==previous_green) &&
       {1'b0,left}+limit_dx>=pl && {1'b0,pl}+limit_dx>=left &&
       {1'b0,right}+limit_dx>=pr && {1'b0,pr}+limit_dx>=right &&
       {1'b0,top}+limit_dy>=pt && {1'b0,pt}+limit_dy>=top &&
       {1'b0,bottom}+limit_dy>=pb && {1'b0,pb}+limit_dy>=bottom && edges>=32 && upper_edges>=8;
    previous_green<=green;
    pl<=left;pr<=right;pt<=top;pb<=bottom;have<=found;edges<=0;upper_edges<=0;
   end
  end
 end
endmodule
