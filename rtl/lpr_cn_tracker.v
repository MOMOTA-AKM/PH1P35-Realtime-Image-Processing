// One plate on screen: acquire consecutive detections, associate by position
// and color, smooth display coordinates, hold a short gap, invalidate on switch.
// The segmenter uses RAW boxes; these smoothed boxes are for drawing only.
module lpr_cn_tracker #(
    parameter ACQUIRE_FRAMES=3,HOLD_FRAMES=3,OUTLIER_HOLD=0
)(
    input clk,rst_n,update,found,green,
    input [11:0] left,right,top,bottom,
    output reg tracked,track_green,changed,
    output reg [7:0] epoch,
    output reg [11:0] track_left,track_right,track_top,track_bottom
);
    reg [1:0] state;
    reg in_found,in_green;
    reg [11:0] il,ir,it,ib,pl,pr,pt,pb;
    reg pending_green;
    reg [3:0] hits,misses;
    reg associated;
    reg [3:0] outliers;
    wire same_track=in_green==pending_green &&
        il+(in_green?96:64)>=pl && pl+(in_green?96:64)>=il &&
        ir+(in_green?96:64)>=pr && pr+(in_green?96:64)>=ir &&
        it+(in_green?96:32)>=pt && pt+(in_green?96:32)>=it &&
        ib+(in_green?96:32)>=pb && pb+(in_green?96:32)>=ib;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0;in_found<=0;in_green<=0;il<=0;ir<=0;it<=0;ib<=0;
            pl<=0;pr<=0;pt<=0;pb<=0;pending_green<=0;hits<=0;misses<=0;associated<=0;outliers<=0;
            tracked<=0;track_green<=0;changed<=0;epoch<=0;
            track_left<=0;track_right<=0;track_top<=0;track_bottom<=0;
        end else begin
            changed<=0;
            case(state)
                0:if(update) begin
                    in_found<=found;in_green<=green;il<=left;ir<=right;it<=top;ib<=bottom;state<=1;
                end
                1:begin associated<=same_track;state<=2;end
                2:begin
                    state<=0;
                    if(!in_found) begin
                        hits<=0;outliers<=0;
                        if(tracked) begin
                            if(misses>=HOLD_FRAMES) begin tracked<=0;changed<=1;epoch<=epoch+1'b1;end
                            else misses<=misses+1'b1;
                        end
                    end else if(OUTLIER_HOLD!=0 && tracked && !associated &&
                                in_green==pending_green && outliers<OUTLIER_HOLD) begin
                        // Quarantine a brief same-color detector excursion.
                        // Keep the last accepted association anchor, do not
                        // smooth the outlier into the box or advance epoch.
                        outliers<=outliers+1'b1;
                    end else begin
                        outliers<=0;
                        pl<=il;pr<=ir;pt<=it;pb<=ib;pending_green<=in_green;misses<=0;
                        if(associated && (tracked || hits!=0)) begin
                            if(tracked) begin
                                track_left<=({1'b0,track_left}+{1'b0,il}+1'b1)>>1;
                                track_right<=({1'b0,track_right}+{1'b0,ir}+1'b1)>>1;
                                track_top<=({1'b0,track_top}+{1'b0,it}+1'b1)>>1;
                                track_bottom<=({1'b0,track_bottom}+{1'b0,ib}+1'b1)>>1;
                            end else if(hits>=ACQUIRE_FRAMES-1) begin
                                tracked<=1;track_green<=in_green;changed<=1;epoch<=epoch+1'b1;
                                track_left<=il;track_right<=ir;track_top<=it;track_bottom<=ib;
                            end else hits<=hits+1'b1;
                        end else begin
                            hits<=1;
                            if(tracked) begin tracked<=0;changed<=1;epoch<=epoch+1'b1;end
                            if(ACQUIRE_FRAMES==1) begin
                                tracked<=1;track_green<=in_green;changed<=1;epoch<=epoch+1'b1;
                                track_left<=il;track_right<=ir;track_top<=it;track_bottom<=ib;
                            end
                        end
                    end
                end
                default:state<=0;
            endcase
        end
    end
endmodule
