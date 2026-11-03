// Last five VALID, associated whole-plate results. Rejected OCR is not a vote.
// Compare sequentially to avoid five wide comparators on the pixel-clock path.
module lpr_cn_vote #(
    parameter WINDOW=5,REQUIRED=3
)(
    input clk,rst_n,clear,start,green,
    input [2:0] required_runtime,
    input [63:0] plate,
    output reg busy,done,confirmed,result_green,
    output reg [63:0] result_plate,
    output reg [3:0] votes
);
    reg [63:0] history[0:WINDOW-1];
    reg [WINDOW-1:0] colors,occupied;
    reg [63:0] pending;
    reg pending_green;
    reg [3:0] index,count;
    integer k;
    wire [2:0] required_effective = required_runtime;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;confirmed<=0;result_green<=0;result_plate<=0;votes<=0;
            colors<=0;occupied<=0;pending<=0;pending_green<=0;index<=0;count<=0;
            for(k=0;k<WINDOW;k=k+1) history[k]<=0;
        end else begin
            done<=0;confirmed<=0;
            if(clear) begin busy<=0;occupied<=0;votes<=0;end
            else if(start && !busy) begin
                pending<=plate;pending_green<=green;index<=0;count<=1;busy<=1;
            end else if(busy) begin
                // Count against the previous WINDOW-1 samples; the oldest
                // sample will fall out when the current sample is appended.
                if(index<(required_effective==2 ? 2 : WINDOW-1)) begin
                    if(occupied[index] && colors[index]==pending_green && history[index]==pending)
                        count<=count+1'b1;
                    index<=index+1'b1;
                end else begin
                    for(k=WINDOW-1;k>0;k=k-1) begin
                        history[k]<=history[k-1];colors[k]<=colors[k-1];occupied[k]<=occupied[k-1];
                    end
                    history[0]<=pending;colors[0]<=pending_green;occupied[0]<=1;
                    result_plate<=pending;result_green<=pending_green;
                    votes<=count;confirmed<=count>=required_effective;done<=1;busy<=0;
                end
            end
        end
    end
endmodule
