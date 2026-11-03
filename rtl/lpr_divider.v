// Unsigned restoring divider. 24 registered steps, no combinational '/'.
module lpr_divider(
    input clk,rst_n,start,
    input [23:0] numerator,
    input [13:0] denominator,
    output reg done,busy,
    output reg [23:0] quotient
);
    reg [23:0] dividend;
    reg [13:0] divisor;
    reg [14:0] remainder;
    reg [4:0] count;
    wire [14:0] trial={remainder[13:0],dividend[23]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            done<=0;busy<=0;quotient<=0;dividend<=0;divisor<=1;remainder<=0;count<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                dividend<=numerator;divisor<=denominator;remainder<=0;
                quotient<=0;count<=0;busy<=1;
            end else if(busy) begin
                dividend<={dividend[22:0],1'b0};
                if(trial>={1'b0,divisor}) begin
                    remainder<=trial-divisor;quotient<={quotient[22:0],1'b1};
                end else begin
                    remainder<=trial;quotient<={quotient[22:0],1'b0};
                end
                if(count==23) begin busy<=0;done<=1;end
                else count<=count+1'b1;
            end
        end
    end
endmodule
