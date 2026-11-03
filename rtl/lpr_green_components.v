// Bounded, serial 8-connected foreground cleanup. Overflow rejects the frame;
// it never silently truncates a large component into a plausible character.
module lpr_green_components(
 input clk,rst_n,start,
 input [9:0] width,input [7:0] height,
 output reg busy,done,overflow,
 output reg [16:0] read_address,input pixel_q,
 output reg clear_we,output reg [16:0] clear_address
);
 (* ram_style="bram" *) reg visited[0:131071];
 (* ram_style="bram" *) reg [17:0] queue[0:4095];
 reg visit_we;reg [16:0] visit_wa,visit_ra;reg visit_di,visit_q;
 reg queue_we;reg [11:0] queue_wa,queue_ra;reg [17:0] queue_di,queue_q;
 always @(posedge clk) begin
  if(visit_we) visited[visit_wa]<=visit_di;
  visit_q<=visited[visit_ra];
  if(queue_we) queue[queue_wa]<=queue_di;
  queue_q<=queue[queue_ra];
 end
 reg [4:0] state;
 reg [16:0] scan_address,neighbor_address,current_address;
 reg [9:0] w,sx,cx,nx,xmin,xmax;
 reg [7:0] h,sy,cy,ny,ymin,ymax;
 reg [12:0] head,tail,erase;
 reg [3:0] neighbor;
 reg [16:0] init_address;
 wire valid_neighbor=nx<w && ny<h;
 // Address sites are active in disjoint FSM states. Share one constant
 // row-stride adder; retain the exact low-17-bit wrap of the old products.
 reg [8:0] address_y;
 reg [9:0] address_x;
 always @* begin
  address_y={1'b0,ny};address_x=nx;
  if(state==16) begin address_y={1'b0,queue_q[17:10]};address_x=queue_q[9:0];end
  else if(state==17) begin address_y={1'b0,sy}+9'd1;address_x=0;end
 end
 wire [16:0] shared_address=({address_y,9'b0}+{address_y,7'b0})+address_x;
 wire [9:0] cw=xmax-xmin+1'b1;
 wire [8:0] ch={1'b0,ymax}-{1'b0,ymin}+1'b1;
 // Conservative geometry, no expected character identity.
 wire keep=ch>=((h>>2)+(h>>4)) && ch<h-(h>>5) &&
           cw<((w>>3)+(w>>4)) && tail>=4;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=0;busy<=0;done<=0;overflow<=0;clear_we<=0;clear_address<=0;
   visit_we<=0;visit_wa<=0;visit_ra<=0;visit_di<=0;
   queue_we<=0;queue_wa<=0;queue_ra<=0;queue_di<=0;
   read_address<=0;scan_address<=0;current_address<=0;neighbor_address<=0;
   w<=0;h<=0;sx<=0;sy<=0;cx<=0;cy<=0;nx<=0;ny<=0;
   xmin<=0;xmax<=0;ymin<=0;ymax<=0;head<=0;tail<=0;erase<=0;neighbor<=0;init_address<=0;
  end else begin
   done<=0;visit_we<=0;queue_we<=0;clear_we<=0;
   case(state)
    0:if(start) begin
     w<=width;h<=height;sx<=0;sy<=0;scan_address<=0;init_address<=0;
     busy<=1;overflow<=0;state<=1;
    end
    1:begin
     visit_we<=1;visit_wa<=init_address;visit_di<=0;
     if(init_address==131071) state<=2;else init_address<=init_address+1'b1;
    end
    2:begin read_address<=scan_address;visit_ra<=scan_address;state<=3;end
    3:state<=4;
    4:if(pixel_q && !visit_q) begin
     visit_we<=1;visit_wa<=scan_address;visit_di<=1;
     queue_we<=1;queue_wa<=0;queue_di<={sy,sx};
     head<=0;tail<=1;xmin<=sx;xmax<=sx;ymin<=sy;ymax<=sy;state<=5;
    end else state<=17;
    5:if(head<tail) begin queue_ra<=head[11:0];state<=6;end
      else begin erase<=0;state<=14;end
    6:state<=7;
    7:begin
     cx<=queue_q[9:0];cy<=queue_q[17:10];
     neighbor<=0;state<=8;
    end
    8:begin
     case(neighbor)
      0:begin nx<=cx-1'b1;ny<=cy-1'b1;end
      1:begin nx<=cx;ny<=cy-1'b1;end
      2:begin nx<=cx+1'b1;ny<=cy-1'b1;end
      3:begin nx<=cx-1'b1;ny<=cy;end
      4:begin nx<=cx+1'b1;ny<=cy;end
      5:begin nx<=cx-1'b1;ny<=cy+1'b1;end
      6:begin nx<=cx;ny<=cy+1'b1;end
      7:begin nx<=cx+1'b1;ny<=cy+1'b1;end
     endcase
     state<=9;
    end
    9:if(valid_neighbor) begin
     neighbor_address<=shared_address;read_address<=shared_address;visit_ra<=shared_address;state<=10;
    end else state<=12;
    10:state<=11;
    11:begin
     if(pixel_q && !visit_q) begin
      if(tail==4096) begin overflow<=1;state<=18;end
      else begin
       visit_we<=1;visit_wa<=neighbor_address;visit_di<=1;
       queue_we<=1;queue_wa<=tail[11:0];queue_di<={ny,nx};tail<=tail+1'b1;
       if(nx<xmin) xmin<=nx;if(nx>xmax) xmax<=nx;
       if(ny<ymin) ymin<=ny;if(ny>ymax) ymax<=ny;
       state<=12;
      end
     end else state<=12;
    end
    12:if(neighbor==7) begin head<=head+1'b1;state<=5;end
       else begin neighbor<=neighbor+1'b1;state<=8;end
    14:if(keep || erase==tail) state<=17;
       else begin queue_ra<=erase[11:0];state<=15;end
    15:state<=16;
    16:begin clear_we<=1;clear_address<=shared_address;erase<=erase+1'b1;state<=14;end
    17:if(sx==w-1) begin
     if(sy==h-1) state<=18;
     else begin sx<=0;sy<=sy+1'b1;scan_address<=shared_address;state<=2;end
    end else begin sx<=sx+1'b1;scan_address<=scan_address+1'b1;state<=2;end
    18:begin done<=1;busy<=0;state<=0;end
    default:state<=0;
   endcase
  end
 end
endmodule
