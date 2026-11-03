// Eight-digit, active-low seven-segment scanner on the HX1P35A board.
// DIG0..DIG7 are a..g/DP and SEL0..SEL7 select the eight digits.
module lpr_mode_seg(input clk,input rst_n,input edge_mode,
                    output reg [7:0] seg,output reg [7:0] sel);
    reg [15:0] div;
    reg [2:0] digit;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin div<=0;digit<=0; end
        else begin
            div<=div+1'b1;
            if(div==16'd0) digit<=digit+1'b1;
        end
    end
    always @* begin
        case(digit)
            3'd0: sel=8'b11111110; 3'd1: sel=8'b11111101;
            3'd2: sel=8'b11111011; 3'd3: sel=8'b11110111;
            3'd4: sel=8'b11101111; 3'd5: sel=8'b11011111;
            3'd6: sel=8'b10111111; default: sel=8'b01111111;
        endcase
        // direct active-low patterns: a,b,c,d,e,f,g,DP
        case(digit)
            3'd0: seg=8'b11000000;                         // 0
            3'd1: seg=edge_mode?8'b10100100:8'b11111001;  // 2 / 1
            3'd2: seg=8'b10111111;                         // '-'
            3'd3: seg=edge_mode?8'b10000110:8'b11000110;  // E / C
            3'd4: seg=edge_mode?8'b11000000:8'b11000000;  // D shown as 0 / O
            3'd5: seg=edge_mode?8'b10000010:8'b11000111;  // G shown as 6 / L
            3'd6: seg=edge_mode?8'b10000110:8'b11000000;  // E / O
            // Upper-case R approximation (a,e,f,g,c); final COLOR digit.
            default: seg=edge_mode?8'b11111111:8'b10001000; // blank / A
        endcase
    end
endmodule
