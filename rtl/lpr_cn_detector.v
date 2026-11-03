// Scanline color bands joined into four local candidates. Distant same-color
// objects no longer expand a single full-frame bounding box.
module lpr_cn_detector #(
    parameter WIDTH=1280,HEIGHT=720,SEARCH_TOP=170,MIN_PIXELS=1200,COLOR_GAP=24, WIDE_GLYPH_GAP=0,GREEN_TOP_PAD=0, SCALE_GAP=0,GREEN_PAD_CAP=0,GREEN_GRADIENT=1,GREEN_HEIGHT_RECOVERY=0,BLUE_HEIGHT_RECOVERY=0,GREEN_INK_REFINE=0
)(
    input clk,rst_n,frame_tick,de,
    input [11:0] x,y,
    input [23:0] rgb,
    output reg found,green,frame_done,
    output reg [11:0] left,right,top,bottom
);
    wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
    // Strong green rejects dim vegetation and neutral car bodies.
    // Widen every addition to avoid 8-bit wrap near white.
    wire green_strong=g>95 && {1'b0,g}>={1'b0,r}+9'd5 &&
        {1'b0,g}>={1'b0,b}+9'd3;
    // Recover the nearly-white upper rim by bottom-anchored plate geometry
    // below. Feeding pale pixels back through the previous ROI changed its
    // shape and caused alternating acquisition/loss on the Mercedes sample.
    // No screen-fixed y threshold and no previous-box color feedback.
    wire [1:0] color_hit={
        GREEN_GRADIENT ? green_strong :
            (g>60 && {1'b0,g}>{1'b0,r}+8 && {1'b0,g}>{1'b0,b}+5),
        b>50 && {1'b0,b}>{1'b0,r}+(b>>2)+10 && {1'b0,b}>{1'b0,g}+(b>>2)};
    reg de_d;
    reg [11:0] row_y;
    reg [11:0] run_l[0:1],run_r[0:1],run_n[0:1];
    reg [11:0] band_l[0:1],band_r[0:1],band_n[0:1];
    reg [11:0] previous_width[0:1];
    reg [1:0] pending;
    reg used[0:3],kind[0:3];
    reg [11:0] xl[0:3],xr[0:3],yt[0:3],yb[0:3];
    reg [20:0] count[0:3];
    reg [2:0] evaluate;
    reg final_evaluation;
    reg [1:0] eval_slot;
    reg best_valid,best_green;
    reg [20:0] best_count;
    reg [11:0] best_l,best_r,best_t,best_b;
    wire [11:0] green_pad_raw=(best_b-best_t)>>1;
    // Never extrapolate a tall green region by another half-height. Limit
    // recovery by plate width as well as an absolute cap, saturating at y=0.
    wire [11:0] green_pad_width=(best_r-best_l)>>4;
    wire [11:0] green_pad_limited=green_pad_raw>green_pad_width?green_pad_width:green_pad_raw;
    wire [11:0] green_pad=GREEN_PAD_CAP==0?green_pad_raw:
        (green_pad_limited>GREEN_PAD_CAP?GREEN_PAD_CAP:green_pad_limited);
    // New-energy plates are approximately 480:140. Color often covers only
    // their lower half. Recover a minimum height, anchored at the green base,
    // instead of adding a constant margin to an unstable color-derived top.
    // This is a bounded geometry estimate, NOT observed white-edge detection.
    wire [12:0] best_width={1'b0,best_r}-{1'b0,best_l}+13'd1;
    wire [12:0] best_height={1'b0,best_b}-{1'b0,best_t}+13'd1;
    // 5/16 leaves a small margin over the physical 140/480 plate ratio.
    // 3/8 included excess bodywork and shrank normalized character strokes.
    wire [12:0] green_expected_height=(best_width>>2)+(best_width>>4);
    wire [12:0] recovery_height=best_height>green_expected_height?best_height:green_expected_height;
    wire [11:0] recovery_top=({1'b0,best_b}+13'd1>recovery_height)?
        ({1'b0,best_b}+13'd1-recovery_height):12'd0;
    // Observe black-character rows inside the previous green color candidate.
    // This never feeds pale background back into color candidate generation.
    reg ink_previous,ink_row_seen;
    reg [11:0] ink_count,ink_runs;
    reg [11:0] ink_top,ink_bottom,ink_rows;
    reg [11:0] ink_final_top,ink_final_bottom,ink_final_rows;
    reg [11:0] anchor_l,anchor_r,anchor_t,anchor_b;
    reg anchor_valid;
    wire [12:0] anchor_width={1'b0,anchor_r}-{1'b0,anchor_l}+1;
    wire [12:0] anchor_height={1'b0,anchor_b}-{1'b0,anchor_t}+1;
    wire [11:0] ink_margin=(anchor_height>>4)+1;
    wire [11:0] ink_search_top=anchor_t>ink_margin?anchor_t-ink_margin:0;
    wire in_ink_window=anchor_valid && x>anchor_l+(anchor_width>>5) &&
        x<anchor_r-(anchor_width>>5) && y>=ink_search_top && y<=anchor_b;
    wire [9:0] ink_gray_sum={2'b0,r}+{1'b0,g,1'b0}+{2'b0,b};
    wire ink_pixel=in_ink_window && ink_gray_sum<10'd400;
    wire ink_row_good=ink_count>=(anchor_width>>5) && ink_count<(anchor_width>>1) &&
        ink_runs>=4 && ink_runs<=64;
    wire ink_associated=anchor_valid && best_l+16>=anchor_l && anchor_l+16>=best_l &&
        best_r+16>=anchor_r && anchor_r+16>=best_r && best_b+12>=anchor_b && anchor_b+12>=best_b;
    wire ink_refine_valid=GREEN_INK_REFINE && best_green && best_width>=256 && ink_associated &&
        ink_final_rows>=(anchor_height>>2) &&
        ink_final_bottom>ink_final_top+(anchor_height>>2) &&
        ink_final_bottom-ink_final_top<anchor_height;
    wire [11:0] refined_top=ink_final_top>ink_margin?ink_final_top-ink_margin:0;
    wire [12:0] refined_bottom={1'b0,ink_final_bottom}+ink_margin;
    // Blue color bands can fragment across wide white characters. A short
    // winning band must not become a vertically cropped OCR ROI. Recover a
    // conservative 5/16 width around the observed band center, saturating at
    // image bounds. This is geometry recovery, not perspective correction.
    wire [12:0] blue_expected_height=(best_width>>2)+(best_width>>4);
    wire [12:0] blue_extra=blue_expected_height>best_height?
        blue_expected_height-best_height:13'd0;
    wire [12:0] blue_up=blue_extra>>1;
    wire [12:0] blue_down=blue_extra-blue_up;
    wire [11:0] blue_top=best_t>blue_up?best_t-blue_up:12'd0;
    wire [12:0] blue_bottom_sum={1'b0,best_b}+blue_down;
    wire [11:0] blue_bottom=blue_bottom_sum>=HEIGHT?HEIGHT-1:blue_bottom_sum[11:0];
    reg [12:0] w,h;
    reg [25:0] area;
    reg [15:0] twice_h,six_h,twelve_h;
    reg shape_ok,occupied;
    reg [11:0] line_l,line_r,line_n;
    integer c,match_slot,free_slot;
    reg line_color;
    always @* begin
        line_color=pending==2; c=line_color;
        line_l=band_l[c];line_r=band_r[c];line_n=band_n[c];
        if(run_n[c]>line_n) begin line_l=run_l[c];line_r=run_r[c];line_n=run_n[c];end
        match_slot=-1;free_slot=-1;
        for(c=0;c<4;c=c+1) begin
            if(used[c] && kind[c]==line_color && row_y>=yb[c] && row_y<=yb[c]+4 &&
               line_l<=xr[c] && line_r>=xl[c] &&
               line_l+48>=xl[c] && line_l<=xl[c]+48 &&
               line_r+48>=xr[c] && line_r<=xr[c]+48 && match_slot==-1) match_slot=c;
            if((!used[c] || row_y>yb[c]+4) && free_slot==-1) free_slot=c;
        end
    end
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            found<=0;green<=0;left<=0;right<=0;top<=0;bottom<=0;
            frame_done<=0;evaluate<=0;final_evaluation<=0;eval_slot<=0;best_valid<=0;best_green<=0;best_count<=0;
            best_l<=0;best_r<=0;best_t<=0;best_b<=0;
            ink_previous<=0;ink_row_seen<=0;ink_count<=0;ink_runs<=0;
            ink_top<=0;ink_bottom<=0;ink_rows<=0;ink_final_top<=0;ink_final_bottom<=0;ink_final_rows<=0;
            anchor_l<=0;anchor_r<=0;anchor_t<=0;anchor_b<=0;anchor_valid<=0;
            w<=0;h<=0;area<=0;twice_h<=0;six_h<=0;twelve_h<=0;shape_ok<=0;occupied<=0;
            de_d<=0;row_y<=0;pending<=0;
            for(k=0;k<2;k=k+1) begin
                run_l[k]<=0;run_r[k]<=0;run_n[k]<=0;band_l[k]<=0;band_r[k]<=0;band_n[k]<=0;previous_width[k]<=0;
            end
            for(k=0;k<4;k=k+1) begin used[k]<=0;kind[k]<=0;xl[k]<=0;xr[k]<=0;yt[k]<=0;yb[k]<=0;count[k]<=0;end
        end else begin
            de_d<=de;
            frame_done<=0;
            if(GREEN_INK_REFINE) begin
                if(frame_tick) begin
                    ink_final_top<=ink_top;ink_final_bottom<=ink_bottom;ink_final_rows<=ink_rows;
                    ink_rows<=0;ink_count<=0;ink_runs<=0;ink_previous<=0;ink_row_seen<=0;
                end else if(de) begin
                    ink_previous<=ink_pixel;ink_row_seen<=1;
                    if(ink_pixel) begin
                        ink_count<=ink_count+1'b1;
                        if(!ink_previous) ink_runs<=ink_runs+1'b1;
                    end
                end else if(de_d && ink_row_seen) begin
                    if(ink_row_good) begin
                        if(ink_rows==0) ink_top<=row_y;
                        ink_bottom<=row_y;ink_rows<=ink_rows+1'b1;
                    end
                    ink_row_seen<=0;ink_count<=0;ink_runs<=0;ink_previous<=0;
                end
            end
            if(frame_tick) begin
                // Evaluate one candidate at a time in vertical blanking.
                // Separate subtraction, multiplication, shape and winner paths.
                evaluate<=1;final_evaluation<=1;eval_slot<=0;pending<=0;
                for(k=0;k<2;k=k+1) begin run_n[k]<=0;band_n[k]<=0;previous_width[k]<=0;end
            end else if(evaluate!=0) begin
                case(evaluate)
                    1:begin
                        w<={1'b0,xr[eval_slot]}-{1'b0,xl[eval_slot]}+13'd1;
                        h<={1'b0,yb[eval_slot]}-{1'b0,yt[eval_slot]}+13'd1;
                        evaluate<=2;
                    end
                    2:begin
                        area<=w*h;twice_h<={h,1'b0};six_h<=({3'b0,h}<<2)+({3'b0,h}<<1);
                        twelve_h<=({3'b0,h}<<3)+({3'b0,h}<<2);
                        shape_ok<=used[eval_slot] && count[eval_slot]>=(GREEN_HEIGHT_RECOVERY && kind[eval_slot]?(MIN_PIXELS>>2):MIN_PIXELS) &&
                                  w>=100 && w<=1200 && h>=(GREEN_HEIGHT_RECOVERY && kind[eval_slot]?16:30) && h<=384;
                        evaluate<=3;
                    end
                    3:begin
                        occupied<=shape_ok && w>=twice_h &&
                            (!(GREEN_HEIGHT_RECOVERY && kind[eval_slot]) ||
                             (w>=(({3'b0,h}<<1)+h+(h>>2)) && w<=({3'b0,h}<<3))) &&
                            w<=(GREEN_HEIGHT_RECOVERY && kind[eval_slot]?twelve_h:six_h) &&
                            count[eval_slot]>=(GREEN_HEIGHT_RECOVERY && kind[eval_slot]?(area>>1):(area>>2));
                        evaluate<=4;
                    end
                    4:begin
                        if(occupied && (!best_valid || count[eval_slot]>best_count)) begin
                            best_valid<=1;best_count<=count[eval_slot];best_green<=kind[eval_slot];
                            best_l<=xl[eval_slot];best_r<=xr[eval_slot];best_t<=yt[eval_slot];best_b<=yb[eval_slot];
                        end
                        if(!final_evaluation || eval_slot==3) evaluate<=5;
                        else begin eval_slot<=eval_slot+1'b1;evaluate<=1;end
                    end
                    5:begin
                        evaluate<=0;
                        if(final_evaluation) begin
                            found<=best_valid;green<=best_green;
                            left<=best_l;right<=best_r;
                            // Pale upper green gradient may not meet chroma
                            // threshold although the dark text starts there.
                            top<=ink_refine_valid?refined_top:BLUE_HEIGHT_RECOVERY && !best_green?blue_top:GREEN_HEIGHT_RECOVERY && best_green?recovery_top:GREEN_TOP_PAD && best_green?
                                (best_t>green_pad?best_t-green_pad:12'd0):best_t;
                            bottom<=ink_refine_valid?(refined_bottom<HEIGHT?refined_bottom[11:0]:HEIGHT-1):BLUE_HEIGHT_RECOVERY && !best_green?blue_bottom:best_b;
                            if(GREEN_INK_REFINE) begin
                                anchor_valid<=best_valid && best_green;
                                anchor_l<=best_l;anchor_r<=best_r;anchor_t<=recovery_top;anchor_b<=best_b;
                            end
                            frame_done<=1;best_valid<=0;best_count<=0;
                            for(k=0;k<4;k=k+1) begin used[k]<=0;count[k]<=0;end
                        end else begin used[eval_slot]<=0;count[eval_slot]<=0;end
                    end
                    default:evaluate<=0;
                endcase
            end else if(de) begin
                row_y<=y;
                for(k=0;k<2;k=k+1) begin
                    if(y>=SEARCH_TOP && color_hit[k]) begin
                        if(run_n[k]==0 || x>run_r[k]+(SCALE_GAP && (previous_width[k]>>2)>COLOR_GAP ? (previous_width[k]>>2) : (previous_width[k]>384?
                            (WIDE_GLYPH_GAP ? (previous_width[k]>>2) :
                            ((previous_width[k]>>3)>96?96:(previous_width[k]>>3))):COLOR_GAP))) begin
                            if(run_n[k]>band_n[k]) begin band_l[k]<=run_l[k];band_r[k]<=run_r[k];band_n[k]<=run_n[k];end
                            run_l[k]<=x;run_r[k]<=x;run_n[k]<=1;
                        end else begin run_r[k]<=x;run_n[k]<=run_n[k]+1'b1;end
                    end
                end
            end else if(de_d) pending<=1;
            else if(pending!=0) begin
                if(line_n>=32 && line_r>=line_l+63 && line_r-line_l<1200) begin
                    if(match_slot!=-1) begin
                        if(line_l<xl[match_slot]) xl[match_slot]<=line_l;
                        if(line_r>xr[match_slot]) xr[match_slot]<=line_r;
                        yb[match_slot]<=row_y;count[match_slot]<=count[match_slot]+line_n;
                    end else if(free_slot!=-1 && used[free_slot]) begin
                        // Preserve an expired candidate's score before reuse.
                        // Upper-image clutter can no longer occupy every slot.
                        eval_slot<=free_slot;evaluate<=1;final_evaluation<=0;
                    end else if(free_slot!=-1) begin
                        used[free_slot]<=1;kind[free_slot]<=line_color;
                        xl[free_slot]<=line_l;xr[free_slot]<=line_r;yt[free_slot]<=row_y;yb[free_slot]<=row_y;
                        count[free_slot]<=line_n;
                    end
                end
                if(!(line_n>=32 && line_r>=line_l+63 && line_r-line_l<1200 &&
                     match_slot==-1 && free_slot!=-1 && used[free_slot])) begin
                    previous_width[line_color]<=line_n!=0?line_r-line_l+1'b1:0;
                    if(pending==2) begin
                        pending<=0;
                        for(k=0;k<2;k=k+1) begin run_n[k]<=0;band_n[k]<=0;end
                    end else pending<=2;
                end
            end
        end
    end
endmodule
