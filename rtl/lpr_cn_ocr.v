// Serial, pipelined matcher. A fixed low 128-bit window avoids a wide mux.
module lpr_cn_ocr #(
    // Camera focus, oblique capture and display re-photography alter several
    // low-resolution pixels.  Keep a margin requirement, but allow a larger
    // absolute distance than the exact synthetic-font corpus needs.
    parameter MAX_DISTANCE=48,MIN_MARGIN=2,FONT_VARIANTS=6,ALLOW_IO=0,
    PROJECTION_FEATURES=0,PROVINCE_MARGIN=2,PROVINCE_MAX_DISTANCE=48,GREEN_DF_FORMAT=0,VY_LOWER_WEIGHT=0,GREEN_PHOTO_BANK=0,
    GREEN_STROKE_FEATURES=0,GREEN_PROVINCE_MARGIN=0
)(
    input clk,rst_n,start,green,
    input [3:0] confidence_margin,
    input [1023:0] glyphs,
    input [63:0] glyph_aspects,
    output reg busy,done,valid,result_green,
    output reg [63:0] plate,
    output reg [7:0] worst_distance,
    output reg [63:0] character_distances
);
    (* rom_style="bram" *) reg [15:0] words[0:70*FONT_VARIANTS*8-1];
    (* rom_style="bram" *) reg [7:0] aspects[0:70*FONT_VARIANTS-1];
    (* rom_style="bram" *) reg [15:0] green_words[0:70*FONT_VARIANTS*8-1];
    (* rom_style="bram" *) reg [7:0] green_aspects[0:70*FONT_VARIANTS-1];
    wire [15:0] template_word;
    reg [15:0] blue_word_q,green_word_q,selected_word,delta;
    reg [11:0] address;
    reg [8:0] aspect_address;
    wire [7:0] template_aspect;
    reg [7:0] blue_aspect_q,green_aspect_q;
    reg [4:0] aspect_penalty;
    reg [63:0] captured_aspects;
    reg plate_green;
    initial $readmemh("cn_words.mem",words);
    initial $readmemh("cn_aspects.mem",aspects);
    initial $readmemh("cn_green_words.mem",green_words);
    initial $readmemh("cn_green_aspects.mem",green_aspects);
    always @(posedge clk) begin
        blue_word_q<=words[address];green_word_q<=green_words[address];
        blue_aspect_q<=aspects[aspect_address];green_aspect_q<=green_aspects[aspect_address];
    end
    assign template_word=GREEN_PHOTO_BANK && plate_green?green_word_q:blue_word_q;
    assign template_aspect=GREEN_PHOTO_BANK && plate_green?green_aspect_q:blue_aspect_q;
    reg [1023:0] captured;
    reg [2:0] slot,chunk;
    reg [6:0] candidate;
    reg [2:0] variant;
    reg [3:0] state;
    reg [2:0] p0,p1,p2,p3;
    reg [7:0] distance,char_best,best,second,best_code,font_score;
    reg [63:0] work;
    reg all_good;
    reg [4:0] pop;
    // Four 4x1 zones per ROM word. Serial reuse adds local stroke-density
    // and row-projection evidence without a parallel full-glyph comparator.
    reg [2:0] a0,a1,a2,a3,b0,b1,b2,b3;
    reg [4:0] zone_cost,row_cost;
    reg [7:0] feature_distance;
    reg [2:0] ta0,ta1,tb0,tb1,va,vb;
    reg [4:0] stroke_cost;
    reg [7:0] stroke_distance;
    reg green_clean_capture;
    // A severely degraded province glyph signals a poor whole-ROI capture.
    // Do not let extra feature scores turn its uncertain suffix into an
    // apparently confident plate. Keep original scoring in that case.
    wire use_green_strokes=GREEN_STROKE_FEATURES && plate_green && slot!=0 && green_clean_capture;
    wire [3:0] row_a0={1'b0,a0}+a1,row_a1={1'b0,a2}+a3;
    wire [3:0] row_b0={1'b0,b0}+b1,row_b1={1'b0,b2}+b3;
    wire [3:0] row_delta0=row_a0>row_b0?row_a0-row_b0:row_b0-row_a0;
    wire [3:0] row_delta1=row_a1>row_b1?row_a1-row_b1:row_b1-row_a1;
    wire [7:0] candidate_code=candidate<10 ? "0"+candidate :
        candidate<36 ? "A"+candidate-10 : 8'h80+candidate-36;
    wire [7:0] char_score=font_score<char_best?font_score:char_best;
    // Small new-energy: D/F + alphanumeric + four digits. Restricting
    // slot 3 to digits incorrectly rejected legitimate F-Y / D-A layouts.
    // Slot numbers include province=0 and registration authority=1.
    wire small_green_digits=GREEN_DF_FORMAT && plate_green && slot>=4 &&
        (work[23:16]=="D" || work[23:16]=="F");
    wire legal_candidate=(!small_green_digits || candidate<10) &&
        (ALLOW_IO || slot==0 || (candidate!=18 && candidate!=24));
    wire [5:0] pixel_cost=VY_LOWER_WEIGHT && (candidate==31 || candidate==34) && chunk>=4?
        {pop,1'b0}:{1'b0,pop};
    wire [9:0] feature_total={2'b0,feature_distance}+zone_cost+row_cost+
        (use_green_strokes?(({2'b0,stroke_distance}+stroke_cost)<<1):10'd0);
    wire [8:0] legacy_score={1'b0,distance}+pixel_cost+aspect_penalty+
        (PROJECTION_FEATURES ? (({1'b0,feature_distance}+zone_cost+row_cost)>>2) : 0);
    wire [9:0] combined_score=use_green_strokes?
        ({2'b0,distance}+pixel_cost+aspect_penalty+(PROJECTION_FEATURES?(feature_total>>2):0)):
        {1'b0,legacy_score};
    // Reject uncertain pairs, never substitute a preferred province or digit.
    wire difficult_pair=best_code=="Q" || best_code=="0" || best_code==8'h8d || best_code==8'h8e;
    wire [4:0] base_margin=confidence_margin<MIN_MARGIN?MIN_MARGIN:confidence_margin;
    wire [4:0] pair_margin=difficult_pair && base_margin>2 ? base_margin+2 : base_margin;
    wire [4:0] province_margin=plate_green && GREEN_PROVINCE_MARGIN>PROVINCE_MARGIN?
        GREEN_PROVINCE_MARGIN:PROVINCE_MARGIN;
    wire [4:0] effective_margin=slot==0 && pair_margin<province_margin?province_margin:pair_margin;
    wire qualified=best<=(slot==0?PROVINCE_MAX_DISTANCE:MAX_DISTANCE) &&
        {1'b0,second}>={1'b0,best}+effective_margin && captured[127:0]!=0;
    wire [7:0] aspect_difference=template_aspect>captured_aspects[7:0]?
        template_aspect-captured_aspects[7:0]:captured_aspects[7:0]-template_aspect;
    function [2:0] count4;
        input [3:0] n;
        begin count4={2'b0,n[0]}+{2'b0,n[1]}+{2'b0,n[2]}+{2'b0,n[3]};end
    endfunction
    function [2:0] abs3;
        input [2:0] a,b;
        begin abs3=a>b?a-b:b-a;end
    endfunction
    function [2:0] count6;
        input [5:0] n;
        begin count6={2'b0,n[0]}+{2'b0,n[1]}+{2'b0,n[2]}+
            {2'b0,n[3]}+{2'b0,n[4]}+{2'b0,n[5]};end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;valid<=0;plate<=0;worst_distance<=0;result_green<=0;
            character_distances<=0;
            captured<=0;plate_green<=0;slot<=0;chunk<=0;candidate<=36;variant<=0;state<=0;
            distance<=0;char_best<=255;best<=255;second<=255;best_code<=0;
            address<=0;work<=0;all_good<=0;font_score<=0;selected_word<=0;delta<=0;
            p0<=0;p1<=0;p2<=0;p3<=0;pop<=0;
            captured_aspects<=0;aspect_address<=0;aspect_penalty<=0;
            a0<=0;a1<=0;a2<=0;a3<=0;b0<=0;b1<=0;b2<=0;b3<=0;
            zone_cost<=0;row_cost<=0;feature_distance<=0;
            ta0<=0;ta1<=0;tb0<=0;tb1<=0;va<=0;vb<=0;stroke_cost<=0;stroke_distance<=0;
            green_clean_capture<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                captured<=glyphs;captured_aspects<=glyph_aspects;plate_green<=green;busy<=1;slot<=0;chunk<=0;
                candidate<=36;variant<=0;state<=0;distance<=0;char_best<=255;
                best<=255;second<=255;best_code<=0;work<=0;all_good<=1;worst_distance<=0;
                character_distances<=0;
                feature_distance<=0;
                stroke_distance<=0;
                green_clean_capture<=0;
            end else if(busy) begin
                case(state)
                    0:begin
                        address<=(candidate*FONT_VARIANTS+variant)*8+chunk;
                        aspect_address<=candidate*FONT_VARIANTS+variant;
                        selected_word<=captured[chunk*16+:16];state<=1;
                    end
                    1:state<=2;
                    2:begin
                        delta<=selected_word^template_word;
                        aspect_penalty<=aspect_difference>62?31:aspect_difference>>1;state<=3;
                    end
                    3:begin
                        p0<=count4(delta[3:0]);p1<=count4(delta[7:4]);
                        p2<=count4(delta[11:8]);p3<=count4(delta[15:12]);state<=4;
                        a0<=count4(selected_word[3:0]);a1<=count4(selected_word[7:4]);
                        a2<=count4(selected_word[11:8]);a3<=count4(selected_word[15:12]);
                        b0<=count4(template_word[3:0]);b1<=count4(template_word[7:4]);
                        b2<=count4(template_word[11:8]);b3<=count4(template_word[15:12]);
                        ta0<=count6((selected_word[7:0]^(selected_word[7:0]>>1))&8'h3e);
                        ta1<=count6((selected_word[15:8]^(selected_word[15:8]>>1))&8'h3e);
                        tb0<=count6((template_word[7:0]^(template_word[7:0]>>1))&8'h3e);
                        tb1<=count6((template_word[15:8]^(template_word[15:8]>>1))&8'h3e);
                        va<=count6((selected_word[7:0]^selected_word[15:8])>>1);
                        vb<=count6((template_word[7:0]^template_word[15:8])>>1);
                    end
                    4:begin
                        pop<={2'b0,p0}+{2'b0,p1}+{2'b0,p2}+{2'b0,p3};state<=5;
                        zone_cost<={2'b0,abs3(a0,b0)}+abs3(a1,b1)+abs3(a2,b2)+abs3(a3,b3);
                        row_cost<={1'b0,row_delta0}+row_delta1;
                        stroke_cost<={2'b0,abs3(ta0,tb0)}+abs3(ta1,tb1)+abs3(va,vb);
                    end
                    5:begin
                        if(chunk!=7) begin
                            chunk<=chunk+1'b1;distance<=distance+pixel_cost;
                            feature_distance<=feature_distance+zone_cost+row_cost;state<=0;
                            stroke_distance<=stroke_distance+stroke_cost;
                        end else begin
                            font_score<=combined_score>255?8'd255:combined_score[7:0];
                            feature_distance<=0;distance<=0;chunk<=0;state<=6;
                            stroke_distance<=0;
                        end
                    end
                    6:begin
                        if(variant!=FONT_VARIANTS-1) begin variant<=variant+1'b1;char_best<=char_score;state<=0;end
                        else begin
                            variant<=0;char_best<=255;
                            // Second-best must belong to a DIFFERENT code.
                            if(legal_candidate) begin
                                if(char_score<best) begin second<=best;best<=char_score;best_code<=candidate_code;end
                                else if(char_score<second) second<=char_score;
                            end
                            if((slot==0 && candidate==69) || (slot!=0 && candidate==35)) state<=7;
                            else begin candidate<=candidate+1'b1;state<=0;end
                        end
                    end
                    7:begin
                        if(slot==0) green_clean_capture<=best<=38;
                        character_distances[slot*8+:8]<=best;
                        work[slot*8+:8]<=best_code;
                        if(best>worst_distance) worst_distance<=best;
                        if(!qualified) all_good<=0;
                        if(slot==(plate_green?7:6)) begin
                            plate<=work;plate[slot*8+:8]<=best_code;result_green<=plate_green;
                            valid<=all_good && qualified;busy<=0;done<=1;
                        end else begin
                            captured<={128'b0,captured[1023:128]};
                            captured_aspects<={8'b0,captured_aspects[63:8]};
                            slot<=slot+1'b1;candidate<=slot==0?10:0;
                            best<=255;second<=255;best_code<=0;state<=0;
                        end
                    end
                    default:begin busy<=0;valid<=0;done<=1;end
                endcase
            end
        end
    end
endmodule
