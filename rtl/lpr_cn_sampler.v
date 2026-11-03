// Detection and HDMI never stop. Only new ROI captures are rate-limited.
module lpr_cn_sampler #(
    parameter FRAME_INTERVAL=3, STABLE_UPDATES=2, MAX_DX=8, MAX_DY=6,GREEN_SCALE_STABILITY=0
)(
    input clk,rst_n,update,found,green,tracked,changed,
    input segment_busy,ocr_busy,memory_error,capture_started,fast_mode,
    input [11:0] left,right,top,bottom,
    output allow_capture
);
    reg have_previous,previous_green;
    reg [11:0] pl,pr,pt,pb;
    reg [7:0] stable_count,cooldown;
    // Large green gradient/ink boxes jitter more pixels at the same relative
    // motion. Bounded scale tolerance changes admission only, not captured ROI,
    // identity, OCR confidence or voting. Blue retains its exact fixed limits.
    wire [11:0] previous_w=pr-pl+1'b1,previous_h=pb-pt+1'b1;
    wire [11:0] green_dx=(previous_w>>6)>24?12'd24:
        (previous_w>>6)>MAX_DX?(previous_w>>6):MAX_DX;
    wire [11:0] green_dy=(previous_h>>3)>16?12'd16:
        (previous_h>>3)>MAX_DY?(previous_h>>3):MAX_DY;
    wire [11:0] limit_dx=GREEN_SCALE_STABILITY && green?green_dx:MAX_DX;
    wire [11:0] limit_dy=GREEN_SCALE_STABILITY && green?green_dy:MAX_DY;
    wire stable=have_previous && green==previous_green &&
        {1'b0,left}+limit_dx>=pl && {1'b0,pl}+limit_dx>=left &&
        {1'b0,right}+limit_dx>=pr && {1'b0,pr}+limit_dx>=right &&
        {1'b0,top}+limit_dy>=pt && {1'b0,pt}+limit_dy>=top &&
        {1'b0,bottom}+limit_dy>=pb && {1'b0,pb}+limit_dy>=bottom;
    assign allow_capture=found && tracked && !changed && stable &&
        stable_count>=STABLE_UPDATES-1 && (fast_mode || cooldown>=FRAME_INTERVAL-1) &&
        !segment_busy && !ocr_busy && !memory_error;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            have_previous<=0;previous_green<=0;pl<=0;pr<=0;pt<=0;pb<=0;
            stable_count<=0;cooldown<=0;
        end else begin
            if(update) begin
                if(cooldown<255) cooldown<=cooldown+1'b1;
                have_previous<=found;previous_green<=green;
                pl<=left;pr<=right;pt<=top;pb<=bottom;
                if(found && stable) begin
                    if(stable_count<255) stable_count<=stable_count+1'b1;
                end else stable_count<=found?1:0;
            end
            if(capture_started) cooldown<=0;
            if(changed) begin stable_count<=0;have_previous<=0;end
        end
    end
endmodule
