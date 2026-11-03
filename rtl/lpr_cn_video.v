// COLOR and Sobel-display EDGE views share raw-image plate OCR.
// All camera, MIPI, ISP, AE and DDR logic remains upstream and untouched.
module lpr_cn_video #(
    parameter SEARCH_TOP=144,CONFIRM_RESULTS=3,STALE_FRAMES=60,FRAME_INTERVAL=2, BUTTON_CYCLES=750000, OCR_MARGIN=2
)(
    input clk,rst_n,vs,hs,de,mode_button,clear_button,
    input [23:0] rgb,
    output reg out_vs,out_hs,out_de,
    output reg [23:0] out_rgb,
    output [3:0] leds,
    output [7:0] seg, output [7:0] sel
);
    reg vs_d,de_d;
    reg [11:0] x,y;
    reg [5:0] frame_number;
    wire frame_tick=vs && !vs_d;
    wire found,green,roi_frame_done;
    wire [11:0] left,right,top,bottom;
    wire tracked,track_green,track_changed;
    wire [7:0] epoch;
    wire [11:0] tl,tr,tt,tb;
    wire [1023:0] glyphs;
    wire [63:0] glyph_aspects;
    wire snapshot_valid,snapshot_green,segment_rejected,capture_started;
    wire memory_ready,memory_error;
    wire segment_busy,allow_capture,quality_rejected;
    wire [2:0] reject_reason;
    wire [11:0] result_left,result_right,result_top,result_bottom;
    wire busy,done,valid,result_green;
    wire [63:0] plate;
    wire [7:0] distance;
    wire debug_we,debug_fallback;
    wire [6:0] debug_row;
    wire [5:0] debug_pixels;
    wire [63:0] character_distances;
    (* ram_style="distributed" *) reg [5:0] debug_rows[0:111];
    reg preview_valid,preview_green,preview_fallback;
    reg [63:0] debug_distances;
    reg [7:0] debug_worst;
    reg debug_accepted;
    always @(posedge clk) if(debug_we) debug_rows[debug_row]<=debug_pixels;
    reg [63:0] display_plate;
    reg display_green,display_valid;
    // Historical caption only. display_plate/display_green already retain
    // the last confirmed value when the live display expires, so no duplicate
    // 64-bit result register or timer is needed. Reset clears this history.
    reg caption_valid;
    reg [7:0] age,capture_epoch,ocr_epoch;
    wire fast_mode=1'b0;
    reg [1:0] key_meta,key_sync,key_stable;
    reg [19:0] key_count0,key_count1;
    wire key_color=key_count0==BUTTON_CYCLES-1 && key_sync[0]!=key_stable[0] && !key_sync[0];
    wire key_edge=key_count1==BUTTON_CYCLES-1 && key_sync[1]!=key_stable[1] && !key_sync[1];
    reg requested_edge,edge_mode;
    wire mode_event=frame_tick && requested_edge!=edge_mode;
    wire clear_event=mode_event;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin requested_edge<=0;edge_mode<=0;end
        else begin
            if(key_color) requested_edge<=0;
            else if(key_edge) requested_edge<=1;
            if(frame_tick) edge_mode<=requested_edge;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin key_meta<=3;key_sync<=3;key_stable<=3;key_count0<=0;key_count1<=0;end
        else begin
            key_meta<={clear_button,mode_button};key_sync<=key_meta;
            if(key_sync[0]==key_stable[0]) key_count0<=0;
            else if(key_count0==BUTTON_CYCLES-1) begin key_stable[0]<=key_sync[0];key_count0<=0;end
            else key_count0<=key_count0+1'b1;
            if(key_sync[1]==key_stable[1]) key_count1<=0;
            else if(key_count1==BUTTON_CYCLES-1) begin key_stable[1]<=key_sync[1];key_count1<=0;end
            else key_count1<=key_count1+1'b1;
        end
    end
    reg ocr_associated;
    reg [2:0] stage_code;
    reg [21:0] ocr_timeout;
    reg capture_cancelled;
    reg [7:0] capture_count,ocr_count;
    wire accepted_result=done && valid && tracked && ocr_associated &&
        ocr_epoch==epoch && result_green==track_green && !track_changed && !memory_error;
    wire vote_busy,vote_done,vote_confirmed,vote_green;
    wire [63:0] voted_plate;
    wire [3:0] vote_count;
    wire clear_history=track_changed || !tracked || memory_error || mode_event || clear_event || (frame_tick && age==STALE_FRAMES);
    wire [15:0] latency_bcd;
    wire latency_valid;
    // Actual pixel clock is 75 MHz (PLL output C4). Count full milliseconds
    // from ROI admission to OCR completion, NOT end-to-end video latency.
    lpr_ocr_latency latency(.clk(clk),.rst_n(rst_n),.capture(capture_started),
        .cancel(clear_history || segment_rejected),.finish(done),
        .accept(accepted_result && !vote_busy),
        .publish(vote_done && vote_confirmed && !clear_history),
        .display_bcd(latency_bcd),.display_valid(latency_valid));
    lpr_cn_detector #(.SEARCH_TOP(SEARCH_TOP),.WIDE_GLYPH_GAP(1),.GREEN_TOP_PAD(1),.GREEN_PAD_CAP(24),.SCALE_GAP(1),.GREEN_HEIGHT_RECOVERY(1),.BLUE_HEIGHT_RECOVERY(1),.GREEN_INK_REFINE(1)) detector(
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.de(de),
        .x(x),.y(y),.rgb(rgb),.found(found),.green(green),.frame_done(roi_frame_done),
        .left(left),.right(right),.top(top),.bottom(bottom));
    wire edge_supported,edge_pixel;
    // Both blue and green proposals may pass EDGE's independent Sobel gate.
    // Keep the gradient-recovered raw-image ROI and filled glyph segmentation:
    // feeding outline pixels into filled-glyph templates would damage OCR.
    // This is color-proposal + edge-validation, not color-independent search.
    wire algorithm_found=found && (!edge_mode || edge_supported);
    wire [9:0] edge_gray_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    lpr_sobel_support #(.GREEN_SCALE_ASSOCIATION(1)) edge_evidence(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.de(de),.green(green),
        .found(found),.x(x),.y(y),.left(left),.right(right),.top(top),.bottom(bottom),
        .gray(edge_gray_sum[9:2]),.supported(edge_supported),.edge_pixel(edge_pixel));
    lpr_cn_tracker #(.HOLD_FRAMES(8),.OUTLIER_HOLD(6)) tracker(.clk(clk),.rst_n(rst_n && !mode_event),.update(roi_frame_done),.found(algorithm_found),.green(green),
        .left(left),.right(right),.top(top),.bottom(bottom),.tracked(tracked),.track_green(track_green),
        .changed(track_changed),.epoch(epoch),.track_left(tl),.track_right(tr),.track_top(tt),.track_bottom(tb));
    lpr_cn_sampler #(.FRAME_INTERVAL(FRAME_INTERVAL),.GREEN_SCALE_STABILITY(1)) sampler(
        .clk(clk),.rst_n(rst_n && !mode_event),.update(roi_frame_done),.found(algorithm_found),.green(green),
        .tracked(tracked),.changed(track_changed),.segment_busy(segment_busy),.ocr_busy(busy || vote_busy),
        .memory_error(memory_error),.capture_started(capture_started),.fast_mode(fast_mode),
        .left(left),.right(right),.top(top),.bottom(bottom),.allow_capture(allow_capture));
    lpr_cn_segment #(.FILTER_SHORT_COLUMNS(1),.ADAPTIVE_RUNS(1),.GREEN_DARK_QUANTILE(1),.GREEN_LOCAL_BANDS(1),.GREEN_GRAY_ROI(1)) segment(.clk(clk),.rst_n(rst_n && !mode_event),.frame_tick(roi_frame_done),
        .capture_enable(allow_capture),.capture_busy(segment_busy),
        .quality_rejected(quality_rejected),.reject_reason(reject_reason),
        .de(de),.found(found),.green(green),.x(x),.y(y),.rgb(rgb),
        .left(left),.right(right),.top(top),.bottom(bottom),
        .glyphs(glyphs),.glyph_aspects(glyph_aspects),.snapshot_valid(snapshot_valid),.snapshot_green(snapshot_green),
        .rejected(segment_rejected),.capture_started(capture_started),
        .result_left(result_left),.result_right(result_right),
        .memory_ready(memory_ready),.memory_error(memory_error),
        .result_top(result_top),.result_bottom(result_bottom),
        .debug_we(debug_we),.debug_row(debug_row),.debug_pixels(debug_pixels),.debug_fallback(debug_fallback));
    lpr_cn_ocr #(.PROJECTION_FEATURES(1),.PROVINCE_MARGIN(4),.PROVINCE_MAX_DISTANCE(44),.GREEN_DF_FORMAT(1),.VY_LOWER_WEIGHT(1),.GREEN_PHOTO_BANK(1),.GREEN_STROKE_FEATURES(1),.GREEN_PROVINCE_MARGIN(8)) recognizer(.clk(clk),.rst_n(rst_n && !mode_event),.start(snapshot_valid && !memory_error),
        .confidence_margin(fast_mode?4'd2:OCR_MARGIN[3:0]),
        .green(snapshot_green),.glyphs(glyphs),.glyph_aspects(glyph_aspects),.busy(busy),.done(done),.valid(valid),
        .result_green(result_green),.plate(plate),.worst_distance(distance),.character_distances(character_distances));
    lpr_cn_vote #(.REQUIRED(CONFIRM_RESULTS)) voter(
        .clk(clk),.rst_n(rst_n),.clear(clear_history),.start(accepted_result),
        .green(result_green),.plate(plate),.busy(vote_busy),.done(vote_done),
        .required_runtime(fast_mode?3'd2:3'd3),.confirmed(vote_confirmed),.result_green(vote_green),.result_plate(voted_plate),.votes(vote_count));
    reg [23:0] overlay;
    wire [9:0] gray_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    wire [7:0] gray=gray_sum[9:2];
    // Full-frame 32x32 grid: at 720p there are 920 samples, not an ROI meter.
    reg [17:0] light_sum;
    reg [9:0] light_dark,light_bright,light_count;
    reg [7:0] light_level,dark_level,bright_level;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            light_sum<=0;light_dark<=0;light_bright<=0;light_count<=0;
            light_level<=0;dark_level<=0;bright_level<=0;
        end else if(frame_tick) begin
            // L is sum/1024 (920/1024 of grid mean); D/H are sample counts/4.
            light_level<=light_sum[17:10];dark_level<=light_dark[9:2];bright_level<=light_bright[9:2];
            light_sum<=0;light_dark<=0;light_bright<=0;light_count<=0;
        end else if(de && x[4:0]==16 && y[4:0]==16 && light_count<1023) begin
            light_sum<=light_sum+gray;light_count<=light_count+1'b1;
            if(gray<32) light_dark<=light_dark+1'b1;
            if(gray>223) light_bright<=light_bright+1'b1;
        end
    end
    reg [7:0] code;
    reg [4:0] glyph_row;
    reg [3:0] glyph_col;
    reg [7:0] font_code_q;
    reg [4:0] font_row_q;
    reg [3:0] font_col_q;
    reg text_enable,text_enable_q;
    reg [23:0] text_color,text_color_q,base_q;
    reg video_vs_q,video_hs_q,video_de_q;
    wire [15:0] bits;
    reg [7:0] cn_code;
    reg [3:0] cn_row,cn_col;
    wire [15:0] cn_bits;
    integer text_index;
    reg [6:0] preview_address;
    reg [5:0] preview_bits;
    reg [7:0] selected_distance;
    // Split coordinate/text selection from font decode. Delay the base image
    // and syncs by the same stage so OCR/box coordinates stay aligned.
    lpr_cn_font_rom font(.clk(clk),.code(code),.row(glyph_row),.bits(bits));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            font_code_q<=0;font_row_q<=0;font_col_q<=0;
            text_enable_q<=0;text_color_q<=0;base_q<=0;
            video_vs_q<=0;video_hs_q<=0;video_de_q<=0;
        end else begin
            font_code_q<=code;font_row_q<=glyph_row;font_col_q<=glyph_col;
            text_enable_q<=text_enable;text_color_q<=text_color;base_q<=overlay;
            video_vs_q<=vs;video_hs_q<=hs;video_de_q<=de;
        end
    end
    osd_char_lib logo(.I_char(cn_code),.I_row(cn_row),.O_row_bits(cn_bits));
    // D10 is dedicated to the same confirmed-valid state drawn at top-right.
    // A vote confirms consistency; it is not comparison with ground truth.
    assign leds={memory_error,frame_number[5],tracked,display_valid};
    lpr_mode_seg mode_seg(.clk(clk),.rst_n(rst_n),.edge_mode(edge_mode),
        .seg(seg),.sel(sel));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d<=0;de_d<=0;x<=0;y<=0;frame_number<=0;
            display_plate<=0;display_green<=0;display_valid<=0;age<=0;
            caption_valid<=0;
            capture_cancelled<=0;capture_count<=0;ocr_count<=0;
            capture_epoch<=0;ocr_epoch<=0;ocr_associated<=0;stage_code<=0;ocr_timeout<=0;
            preview_valid<=0;preview_green<=0;preview_fallback<=0;
            debug_distances<=0;debug_worst<=0;debug_accepted<=0;
            out_vs<=0;out_hs<=0;out_de<=0;out_rgb<=0;
        end else begin
            vs_d<=vs;de_d<=de;
            if(frame_tick) begin
                x<=0;y<=0;frame_number<=frame_number+1'b1;
                if(age<255) age<=age+1'b1;
                if(age>=STALE_FRAMES) display_valid<=0;
            end else begin
                if(de) x<=x+1'b1;else x<=0;
                if(de_d && !de) y<=y+1'b1;
            end
            if(capture_started) begin
                preview_valid<=0;
                capture_epoch<=epoch;capture_cancelled<=0;capture_count<=capture_count+1'b1;
            end
            if(track_changed) capture_cancelled<=1;
            if(snapshot_valid && !busy) begin
                // Do not show fresh glyphs beside scores from the last OCR.
                preview_valid<=0;preview_green<=snapshot_green;preview_fallback<=debug_fallback;
                // The capture itself is the identity reference.  The tracker
                // box is deliberately smoothed for drawing, so it may differ
                // from the raw ROI by more than one character edge.  Keep the
                // epoch/color guard for stale results, but do not discard a
                // valid OCR merely because the display box moved slightly.
                ocr_epoch<=capture_epoch;
                ocr_associated<=tracked && !capture_cancelled && !track_changed &&
                    capture_epoch==epoch && snapshot_green==track_green;
                stage_code<=2;
                ocr_timeout<=0;
            end
            if(ocr_timeout<22'h3fffff && stage_code==2) ocr_timeout<=ocr_timeout+1'b1;
            // At 75 MHz this is about 56 ms, longer than the normal segment
            // plus OCR pipeline but short enough to prevent a permanent READ
            // indication if a real ROI never completes.
            if(stage_code==2 && ocr_timeout==22'd4194303) begin
                stage_code<=3;ocr_timeout<=0;
            end
            if(segment_rejected) stage_code<=1;
            if(done) begin
                preview_valid<=ocr_associated && ocr_epoch==epoch && !capture_cancelled;
                debug_distances<=character_distances;debug_worst<=distance;debug_accepted<=accepted_result;
                // A completed OCR that fails identity/epoch association is a
                // retry, never a permanently displayed READ state.
                stage_code<=accepted_result?4:3;ocr_count<=ocr_count+1'b1;
                ocr_timeout<=0;
                // A single disagreeing OCR must not erase a voted result.
            end
            if(vote_done && vote_confirmed && !clear_history) begin
                display_plate<=voted_plate;display_green<=vote_green;display_valid<=1;age<=0;
                caption_valid<=1;
            end
            // Short segmentation/OCR misses keep a confirmed result. Replacement
            // or track expiration clears it, including in-flight old OCR results.
            if(track_changed || !tracked || memory_error || mode_event || clear_event) begin
                preview_valid<=0;
                display_valid<=0;
                if(!tracked) stage_code<=0;
            end
            out_vs<=video_vs_q;out_hs<=video_hs_q;out_de<=video_de_q;
            out_rgb<=video_de_q?(text_enable_q && bits[font_col_q]?text_color_q:base_q):0;
        end
    end
    always @* begin
        // COLOR keeps the camera image. EDGE shows the actual full-frame
        // Sobel binary image, while the recognition/OCR pipeline continues
        // in parallel and its OSD remains visible below.
        overlay=edge_mode ? (edge_pixel ? 24'hffffff : 24'h000000) : rgb;
        text_enable=0;text_color=24'hffffff;
        preview_address=0;preview_bits=0;selected_distance=0;
        if(tracked && x>=tl && x<=tr && y>=tt && y<=tb &&
            (x<=tl+3 || x+3>=tr || y<=tt+3 || y+3>=tb))
            overlay=24'h0080ff;
        code=0;glyph_row=0;glyph_col=0;text_index=0;cn_code=8'h80;cn_row=0;cn_col=0;
        if(x>=176 && x<240 && y>=16 && y<48) begin
            cn_code=x<208?8'h80:8'h81;cn_row=(y-16)>>1;cn_col=((x-176)%32)>>1;
            if(cn_bits[15-cn_col]) overlay=24'h00c8ff;
        end
        if(x>=256 && x<1216 && y>=16 && y<48) begin
            text_index=(x-256)>>5;glyph_row=y-16;glyph_col=((x-256)%32)>>1;
            case(text_index)
                0:code="S";1:code="C";2:code="5";3:code="2";4:code="0";
                6:code="L";7:code="P";8:code="R";
                10:code=tracked?(track_green?"G":"B"):"-";
                11:code=tracked?(track_green?"8":"7"):"-";
                16:code=edge_mode?"E":"C";17:code=edge_mode?"D":"O";18:code=edge_mode?"G":"L";19:code=edge_mode?"E":"O";20:code=edge_mode?0:"R";
                default:code=0;
            endcase
            text_enable=1;text_color=24'hfff080;
        end
        // Eight 64px cells at the upper-right (blue7 leaves cell8 blank).
        if(x>=736 && x<1248 && y>=64 && y<128) begin
            overlay=display_valid?(display_green?24'h104020:24'h102850):24'h202020;
            text_index=(x-736)>>6;glyph_row=(y-64)>>1;glyph_col=((x-736)%64)>>2;
            code=display_valid && text_index<(display_green?8:7)?display_plate[text_index*8+:8]:0;
            if(!display_valid) begin
                case(text_index)
                    0:code=tracked?"R":"S";1:code=tracked?"E":"E";
                    2:code=tracked?"A":"A";3:code=tracked?"D":"R";
                    4:code=tracked?0:"C";5:code=tracked?0:"H";
                    default:code=0;
                endcase
            end
            text_enable=1;text_color=24'hffffff;
        end
        // Historical caption retains the last voted result, independently of
        // live display timeout/track loss/mode changes. Only confirmed updates
        // replace the number; reset clears it.
        // 5 Chinese cells + up to 8 plate cells fit within the existing width.
        // No backpressure or additional delay in the camera/OCR pipelines.
        if(caption_valid && x>=736 && x<1152 && y>=136 && y<168) begin
            overlay=display_green?24'h104020:24'h102850;
            text_index=(x-736)>>5;glyph_row=y-136;
            glyph_col=((x-736)%32)>>1;
            case(text_index)
                0:code=8'hb0;1:code=8'hb1;2:code=8'hb2;
                3:code=8'hb3;4:code=8'hb4;
                default:code=text_index<(display_green?13:12)?
                    display_plate[(text_index-5)*8+:8]:0;
            endcase
            text_enable=1;text_color=24'hffffff;
        end
        // Each cell: exact 8x16 OCR bitmap enlarged 4x, then two hex score digits.
        // Reuse existing uppercase/numeral font. Last confirmed sample's time
        // stays with the historical plate, including on track loss/mode change.
        if(latency_valid && x>=736 && x<1120 && y>=176 && y<208) begin
            overlay=24'h182028;
            text_index=(x-736)>>5;glyph_row=y-176;glyph_col=((x-736)%32)>>1;
            case(text_index)
                0:code="O";1:code="C";2:code="R";3:code=":";
                4:code=8'd48+latency_bcd[15:12];
                5:code=8'd48+latency_bcd[11:8];
                6:code=8'd48+latency_bcd[7:4];
                7:code=8'd48+latency_bcd[3:0];
                9:code="M";10:code="S";default:code=0;
            endcase
            text_enable=1;text_color=24'h80e0ff;
        end
        if(x>=736 && x<992 && y>=600 && y<696) begin
            overlay=24'h101010;
            text_index=(x-736)>>5;
            if(y<664 && preview_valid && text_index<(preview_green?8:7) &&
               y>=604 && y<660 && x[4:0]>=4 && x[4:0]<28) begin
                preview_address=text_index*14+((y-604)>>2);
                preview_bits=debug_rows[preview_address];
                if(preview_bits[(x[4:0]-4)>>2]) overlay=24'hffffff;
            end
            if(y>=664) begin
                selected_distance=debug_distances[text_index*8+:8];
                code=x[4]?hexchar(selected_distance[3:0]):hexchar(selected_distance[7:4]);
                glyph_row=y-664;glyph_col=x[3:0];
                text_enable=1;text_color=debug_accepted?24'h80e0ff:24'hff8060;
            end
        end
    end
    function [7:0] hexchar;
        input [3:0] n;
        begin hexchar=n<10?8'd48+n:8'd65+n-10;end
    endfunction
endmodule

// Small diagnostic side branch: no backpressure, RAM, DSP or combinational
// division. BCD carries only occur every CYCLES_PER_MS clocks. Floor to ms;
// saturate at 9999 rather than wrap. Pending sample follows the voter input.
module lpr_ocr_latency #(parameter CYCLES_PER_MS=75000)(
 input clk,rst_n,capture,cancel,finish,accept,publish,
 output reg [15:0] display_bcd,output reg display_valid
);
 reg [16:0] sub_ms;
 reg [15:0] elapsed,pending;
 reg active,pending_valid;
 wire tick=sub_ms==CYCLES_PER_MS-1;
 function [15:0] increment_bcd;
  input [15:0] n;
  begin
   increment_bcd=n;
   if(n!=16'h9999) begin
    if(n[3:0]!=9) increment_bcd[3:0]=n[3:0]+1'b1;
    else begin
     increment_bcd[3:0]=0;
     if(n[7:4]!=9) increment_bcd[7:4]=n[7:4]+1'b1;
     else begin
      increment_bcd[7:4]=0;
      if(n[11:8]!=9) increment_bcd[11:8]=n[11:8]+1'b1;
      else begin increment_bcd[11:8]=0;increment_bcd[15:12]=n[15:12]+1'b1;end
     end
    end
   end
  end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   sub_ms<=0;elapsed<=0;pending<=0;active<=0;pending_valid<=0;
   display_bcd<=0;display_valid<=0;
  end else begin
   if(active) begin
    if(tick) begin sub_ms<=0;elapsed<=increment_bcd(elapsed);end
    else sub_ms<=sub_ms+1'b1;
   end
   if(finish) begin
    active<=0;
    if(active && accept && !cancel) begin
     pending<=tick?increment_bcd(elapsed):elapsed;pending_valid<=1;
    end
   end
   if(publish && pending_valid && !cancel) begin
    display_bcd<=pending;display_valid<=1;pending_valid<=0;
   end
   if(cancel) begin active<=0;pending_valid<=0;end
   // New admission resets time, but must not destroy an in-flight vote sample.
   if(capture && !cancel) begin active<=1;sub_ms<=0;elapsed<=0;end
  end
 end
endmodule
