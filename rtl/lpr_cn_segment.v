// Capture one bounded 1-bit ROI; column projection splits 7/8 characters.
// Each segmented glyph is independently cropped vertically and normalized.
// No RGB frame buffer or CPU OCR. Invalid segmentation is rejected, not guessed.
module lpr_cn_segment #(
    parameter REQUIRE_CALIBRATION=1, QUALITY_FILTER=1, MIN_EDGE_STEP=20, FILTER_SHORT_COLUMNS=0, ADAPTIVE_RUNS=0, GREEN_DARK_QUANTILE=0,GREEN_LOCAL_BANDS=0,GREEN_GRAY_ROI=0
)(
    input clk,rst_n,frame_tick,de,found,green,capture_enable,
    input [11:0] x,y,left,right,top,bottom,
    input [23:0] rgb,
    output reg [1023:0] glyphs,
    output reg [63:0] glyph_aspects,
    output reg snapshot_valid,snapshot_green,rejected,capture_started,
    output memory_ready,memory_error,
    output capture_busy,
    output reg quality_rejected,
    output reg [2:0] reject_reason,
    output reg [11:0] result_left,result_right,result_top,result_bottom,
    output debug_we,
    output [6:0] debug_row,
    output [5:0] debug_pixels,
    output debug_fallback
);
    reg [5:0] state;
    reg [11:0] bx,by,bw,bh,original_w,original_h;
    reg half_scale;
    reg roi_green;
    // Two original-threshold captures, then one local-gray capture. Shared
    // bitmap, segmenter and OCR; acceptance thresholds are unchanged.
    reg [1:0] gray_phase;
    reg capture_uses_gray;
    reg [17:0] read_address,write_address;
    wire pixel_q;
    wire [11:0] raw_rx=x-bx,raw_ry=y-by;
    wire [11:0] rx=half_scale?(raw_rx>>1):raw_rx;
    wire [11:0] ry=half_scale?(raw_ry>>1):raw_ry;
    wire inner=rx>=(bw>>5) && rx<bw-(bw>>5) && ry>=(bh>>4) && ry<bh-(bh>>4);
    reg [191:0] allowed_rows;
    reg [9:0] row_foreground;
    reg sample_row_allowed;
    reg [7:0] row_index,row_run_start,row_run_end,best_row_height,text_top,text_bottom;
    reg row_in_run;
    // Previous associated ROI supplies a percentile threshold. A histogram,
    // rather than extrema, prevents isolated glare/noise setting the threshold.
    wire [9:0] gray_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    wire [7:0] gray=gray_sum[9:2];
    reg [16:0] histogram[0:15];
    reg [16:0] sample_count,cumulative;
    reg [16:0] bright_count,dark_count,edge_count;
    reg [7:0] previous_gray;
    reg [11:0] previous_rx,previous_ry;
    reg previous_sample;
    wire [7:0] gradient=gray>previous_gray?gray-previous_gray:previous_gray-gray;
    assign capture_busy=state!=0;
    reg [4:0] bin_index;
    reg [3:0] low_bin,high_bin;
    reg low_seen;
    reg [7:0] threshold;
    reg threshold_valid,threshold_green;
    reg capture_calibrated;
    reg [11:0] threshold_bx,threshold_by;
    wire associated_threshold=threshold_valid && threshold_green==roi_green &&
        bx+48>=threshold_bx && threshold_bx+48>=bx &&
        by+32>=threshold_by && threshold_by+32>=by;
    wire [7:0] active_threshold=associated_threshold?threshold:(roi_green?8'd145:8'd115);
    reg [7:0] band_min[0:7],band_max[0:7],band_threshold[0:7];
    reg [7:0] band_valid;
    wire [2:0] band_id=ry[7:5];
    wire [7:0] local_threshold=GREEN_LOCAL_BANDS && roi_green && associated_threshold && band_valid[band_id]?
        band_threshold[band_id]:active_threshold;
    wire foreground=roi_green ? gray<local_threshold : gray>active_threshold;
    wire capture_write=state==3 && de && x>=bx && raw_rx<original_w && y>=by && raw_ry<original_h &&
        (!half_scale || (!raw_rx[0] && !raw_ry[0]));
    wire gray_done,gray_mask_we,gray_mask_pixel,clean_done,clean_overflow,clean_we;
    wire [16:0] clean_ra,clean_wa;
    wire [16:0] gray_mask_address;
    generate if(GREEN_GRAY_ROI) begin:gray_path
        lpr_green_gray_roi gray_roi(.clk(clk),.rst_n(rst_n),
            .capture_we(capture_write && roi_green),.capture_address(write_address[16:0]),.capture_gray(gray[7:4]),
            .start(state==32),.width(bw[9:0]),.height(bh[7:0]),.busy(),.done(gray_done),
            .mask_we(gray_mask_we),.mask_address(gray_mask_address),.mask_pixel(gray_mask_pixel));
        lpr_green_components cleanup(.clk(clk),.rst_n(rst_n),.start(state==37),
            .width(bw[9:0]),.height(bh[7:0]),.busy(),.done(clean_done),.overflow(clean_overflow),
            .read_address(clean_ra),.pixel_q(pixel_q),.clear_we(clean_we),.clear_address(clean_wa));
    end else begin:no_gray
        assign gray_done=0;assign gray_mask_we=0;assign gray_mask_pixel=0;assign gray_mask_address=0;
        assign clean_done=0;assign clean_overflow=0;assign clean_we=0;assign clean_ra=0;assign clean_wa=0;
    end endgenerate
    wire binary_we=clean_we || gray_mask_we || capture_write;
    lpr_cn_bitmap bitmap(.clk(clk),.rst_n(rst_n),.we(binary_we),.di(clean_we?1'b0:gray_mask_we?gray_mask_pixel:inner && foreground),
        .wa(clean_we?clean_wa:gray_mask_we?gray_mask_address:write_address[16:0]),.ra(state==38?clean_ra:read_address[16:0]),.dout(pixel_q),
        .test_done(memory_ready),.test_error(memory_error));
    reg [9:0] index,run_start,run_end;
    reg [7:0] column_count;
    reg [7:0] run_peak;
    reg [7:0] projection_y;
    reg column_active;
    reg in_run;
    reg [3:0] runs,slot;
    reg [9:0] starts[0:7],ends[0:7];
    reg [9:0] scan_x,scan_y,glyph_ymin,glyph_ymax;
    reg [9:0] glyph_xmin,glyph_xmax;
    reg fallback_used;
    reg any_pixel;
    reg [9:0] glyph_width,glyph_height;
    reg [2:0] sample_col;
    reg [3:0] sample_row;
    reg [23:0] numerator;
    reg [13:0] denominator;
    reg div_start;
    wire div_done,div_busy;
    wire [23:0] quotient;
    reg [9:0] sample_x;
    // These address operations occur in mutually exclusive FSM states.
    // Share one row-stride adder instead of synthesizing five multipliers.
    // Only the low 18 address bits are observable (same modulo as before).
    reg [10:0] address_row;
    reg [9:0] address_column;
    always @* begin
        address_row=0;address_column=0;
        case(state)
            3:address_row=ry+1'b1;
            24:begin address_row=projection_y+11'd1;address_column=index;end
            7:begin address_row=scan_y;address_column=scan_x;end
            15:begin address_row=glyph_ymin+quotient;address_column=sample_x;end
            34:begin address_row=row_index;address_column=index;end
        endcase
    end
    wire [17:0] shared_address=({address_row,9'b0}+{address_row,7'b0})+address_column;
    // Assemble just one glyph at a time: no variable write into 1024 bits.
    reg [127:0] work;
    // Exact six interior pixels sent to the OCR normalizer, one row per write.
    assign debug_we=state==17 && sample_col==5;
    assign debug_row=slot*14+sample_row;
    assign debug_pixels={pixel_q && sample_row_allowed,work[(sample_row+1)*8+1+:5]};
    assign debug_fallback=fallback_used;
    wire [3:0] expected=roi_green?8:7;
    lpr_divider divider(.clk(clk),.rst_n(rst_n),.start(div_start),
        .numerator(numerator),.denominator(denominator),.done(div_done),
        .busy(div_busy),.quotient(quotient));
    integer k;
    // Broad GB-style character cells are a fallback only. Pixel bounds are
    // recropped in BOTH axes inside each cell; there is no fixed result string.
    function [8:0] boundary;
        input color;
        input [3:0] n;
        begin
            if(color) case(n)
                0:boundary=0;1:boundary=35;2:boundary=71;3:boundary=106;
                4:boundary=136;5:boundary=165;6:boundary=195;7:boundary=224;default:boundary=256;
            endcase
            else case(n)
                0:boundary=0;1:boundary=40;2:boundary=83;3:boundary=119;
                4:boundary=153;5:boundary=187;6:boundary=222;default:boundary=256;
            endcase
        end
    endfunction
    wire [20:0] cell_begin_product=bw*boundary(roi_green,slot);
    wire [20:0] cell_end_product=bw*boundary(roi_green,slot+1'b1);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0;bx<=0;by<=0;bw<=0;bh<=0;roi_green<=0;original_w<=0;original_h<=0;half_scale<=0;
            gray_phase<=0;capture_uses_gray<=0;
            snapshot_valid<=0;snapshot_green<=0;rejected<=0;capture_started<=0;glyphs<=0;glyph_aspects<=0;
            result_left<=0;result_right<=0;result_top<=0;result_bottom<=0;
            index<=0;run_start<=0;run_end<=0;in_run<=0;runs<=0;slot<=0;
            column_count<=0;projection_y<=0;column_active<=0;run_peak<=0;
            allowed_rows<=0;row_foreground<=0;sample_row_allowed<=0;
            row_index<=0;row_run_start<=0;row_run_end<=0;best_row_height<=0;
            text_top<=0;text_bottom<=0;row_in_run<=0;
            scan_x<=0;scan_y<=0;glyph_ymin<=191;glyph_ymax<=0;any_pixel<=0;
            glyph_xmin<=639;glyph_xmax<=0;fallback_used<=0;
            glyph_width<=0;glyph_height<=0;sample_col<=0;sample_row<=0;
            numerator<=0;denominator<=1;div_start<=0;sample_x<=0;work<=0;
            read_address<=0;write_address<=0;
            sample_count<=0;cumulative<=0;bin_index<=0;low_bin<=0;high_bin<=15;low_seen<=0;
            threshold<=128;threshold_valid<=0;threshold_green<=0;threshold_bx<=0;threshold_by<=0;
            capture_calibrated<=0;
            bright_count<=0;dark_count<=0;edge_count<=0;previous_gray<=0;
            previous_rx<=0;previous_ry<=0;previous_sample<=0;
            quality_rejected<=0;reject_reason<=0;
            for(k=0;k<16;k=k+1) histogram[k]<=0;
            band_valid<=0;
            for(k=0;k<8;k=k+1) begin band_min[k]<=255;band_max[k]<=0;band_threshold[k]<=128;end
            for(k=0;k<8;k=k+1) begin starts[k]<=0;ends[k]<=0;end
        end else begin
            snapshot_valid<=0;rejected<=0;capture_started<=0;div_start<=0;quality_rejected<=0;
            case(state)
                // Completion still observes EVERY frame_tick. Only admission
                // is gated, otherwise skipping frames would corrupt capture.
                0:if(frame_tick && capture_enable) state<=1;
                // Detector publishes its bbox at frame_tick; consume next clock.
                1:begin
                    if(found) begin
                        capture_started<=1;
                        reject_reason<=0;bright_count<=0;dark_count<=0;edge_count<=0;previous_sample<=0;
                        capture_calibrated<=threshold_valid && green==threshold_green &&
                            left+48>=threshold_bx && threshold_bx+48>=left &&
                            top+32>=threshold_by && threshold_by+32>=top;
                        bx<=left;by<=top;original_w<=right-left+1;original_h<=bottom-top+1;
                        half_scale<=right-left+1>640 || bottom-top+1>192;
                        if(right-left+1>640 || bottom-top+1>192) begin
                            bw<=(right-left+2)>>1;bh<=(bottom-top+2)>>1;
                        end else begin bw<=right-left+1;bh<=bottom-top+1;end
                        roi_green<=green;index<=0;sample_count<=0;state<=2;
                        capture_uses_gray<=GREEN_GRAY_ROI && green && gray_phase==2;
                        if(green) gray_phase<=gray_phase==2?0:gray_phase+1'b1;
                    end else begin rejected<=1;state<=0;end
                end
                2:begin
                    if(index<8) begin band_min[index]<=255;band_max[index]<=0;end
                    if(index<16) histogram[index]<=0;
                    if(index<192) allowed_rows[index]<=0;
                    if(index==639) begin write_address<=0;row_foreground<=0;state<=3;end
                    else index<=index+1'b1;
                end
                3:begin
                    if(capture_write) begin
                        write_address<=write_address+1'b1;
                        if(inner && foreground) row_foreground<=row_foreground+1'b1;
                        if(rx==bw-1) begin
                            write_address<=shared_address;row_foreground<=0;
                            // Suppress near-solid horizontal frame/plate edges
                            // without discarding the top bar of T, 7 or the Han.
                            allowed_rows[ry]<=row_foreground+(inner && foreground)<bw-(bw>>3) &&
                                row_foreground+(inner && foreground)>=(bw>>4);
                        end
                        if(inner) begin
                            if(gray<band_min[band_id]) band_min[band_id]<=gray;
                            if(gray>band_max[band_id]) band_max[band_id]<=gray;
                            if(histogram[gray[7:4]]!=17'h1ffff) histogram[gray[7:4]]<=histogram[gray[7:4]]+1'b1;
                            sample_count<=sample_count+1'b1;
                            if(gray>=248) bright_count<=bright_count+1'b1;
                            if(gray<=7) dark_count<=dark_count+1'b1;
                            if(previous_sample && previous_ry==ry && previous_rx+1'b1==rx && gradient>=MIN_EDGE_STEP)
                                edge_count<=edge_count+1'b1;
                            previous_gray<=gray;previous_rx<=rx;previous_ry<=ry;previous_sample<=1;
                        end
                    end
                    if(frame_tick) begin
                        index<=0;runs<=0;in_run<=0;work<=0;fallback_used<=0;
                        cumulative<=0;bin_index<=0;low_seen<=0;low_bin<=0;high_bin<=0;state<=20;
                    end
                end
                4:begin
                    // Reuse the ROI RAM for vertical projection. No 640-way
                    // counter mux or shallow two-pixel test that accepts dots.
                    column_count<=0;projection_y<=0;
                    if(index<bw) begin read_address<=index;state<=23;end
                    else begin column_active<=0;state<=25;end
                end
                23:state<=24;
                24:begin
                    if(pixel_q && allowed_rows[projection_y] && projection_y>=text_top && projection_y<=text_bottom)
                        column_count<=column_count+1'b1;
                    if(projection_y==bh-1) begin
                        column_active<=column_count+(pixel_q && allowed_rows[projection_y] &&
                            projection_y>=text_top && projection_y<=text_bottom)>=
                            (roi_green && ADAPTIVE_RUNS ? ((text_bottom-text_top+1)>>3) :
                             (FILTER_SHORT_COLUMNS && index>=(bw>>2) ? (((text_bottom-text_top+1)>>3)>2?((text_bottom-text_top+1)>>3):2) : 2));
                        state<=25;
                    end else begin
                        projection_y<=projection_y+1'b1;
                        read_address<=shared_address;state<=23;
                    end
                end
                25:begin
                    if(index<bw && column_active) begin
                        if(!in_run) begin run_start<=index;in_run<=1;run_peak<=column_count;end
                        else if(column_count>run_peak) run_peak<=column_count;
                        run_end<=index;
                    end else if(in_run && (index>=bw || index>run_end+(ADAPTIVE_RUNS?(bw>>7):(bw>>6))+1)) begin
                        // A real digit 1 can be only 1-2 pixels wide. Reject
                        // specks by vertical occupancy, not character width.
                        // Curved/slanted Z/C can peak below half text height.
                        // 3/8 retains them while excluding short separators.
                        if(run_end>=run_start && run_peak>=(ADAPTIVE_RUNS?(((text_bottom-text_top+1)>>2)+((text_bottom-text_top+1)>>3)):((bh>>4)>4?(bh>>4):4))) begin
                            // The province glyph can have disconnected vertical
                            // strokes (e.g. Chuan). Merge only inside the first
                            // character cell; never bridge the separator dot.
                            if(ADAPTIVE_RUNS && runs==1 && run_end<(bw>>3)+(bw>>4)) ends[0]<=run_end;
                            else begin
                                if(runs<8) begin starts[runs]<=run_start;ends[runs]<=run_end;end
                                if(runs<9) runs<=runs+1'b1;
                            end
                        end
                        in_run<=0;
                    end
                    // Flush a final character even when it touches the ROI's
                    // inner right margin (the old bw+2 exit could drop it).
                    if(index>=bw+(bw>>6)+3) state<=5;
                    else begin index<=index+1'b1;state<=4;end
                end
                5:begin
                    if(runs!=expected) begin slot<=0;fallback_used<=1;state<=26;end
                    else begin slot<=0;state<=6;end
                end
                6:begin
                    scan_x<=starts[slot];scan_y<=0;glyph_ymin<=191;glyph_ymax<=0;
                    glyph_xmin<=639;glyph_xmax<=0;
                    any_pixel<=0;glyph_width<=ends[slot]-starts[slot]+1;work<=0;state<=7;
                end
                7:begin read_address<=shared_address;state<=8;end
                8:state<=9;
                9:begin
                    if(pixel_q && allowed_rows[scan_y] && scan_y>=text_top && scan_y<=text_bottom) begin
                        any_pixel<=1;
                        if(scan_y<glyph_ymin) glyph_ymin<=scan_y;
                        if(scan_y>glyph_ymax) glyph_ymax<=scan_y;
                        if(scan_x<glyph_xmin) glyph_xmin<=scan_x;
                        if(scan_x>glyph_xmax) glyph_xmax<=scan_x;
                    end
                    if(scan_x==ends[slot]) begin
                        scan_x<=starts[slot];
                        if(scan_y==bh-1) state<=10;
                        else begin scan_y<=scan_y+1'b1;state<=7;end
                    end else begin scan_x<=scan_x+1'b1;state<=7;end
                end
                10:begin
                    if(!any_pixel || glyph_ymax<glyph_ymin+6) begin
                        // A separator dot can replace a merged run even when
                        // the total run count happens to equal seven/eight.
                        // Retry broad cells once; never normalize the dot.
                        if(!fallback_used) begin slot<=0;fallback_used<=1;state<=26;end
                        else begin rejected<=1;state<=0;end
                    end
                    else begin glyph_height<=glyph_ymax-glyph_ymin+1;glyph_width<=glyph_xmax-glyph_xmin+1;
                        sample_row<=0;sample_col<=0;state<=27;end
                end
                11:begin numerator<=(sample_col*2+1)*glyph_width;denominator<=12;state<=12;end
                12:begin div_start<=1;state<=13;end
                13:if(div_done) begin
                    sample_x<=glyph_xmin+quotient;
                    numerator<=(sample_row*2+1)*glyph_height;denominator<=28;state<=14;
                end
                14:begin div_start<=1;state<=15;end
                15:if(div_done) begin
                    read_address<=shared_address;
                    sample_row_allowed<=allowed_rows[glyph_ymin+quotient];state<=16;
                end
                16:state<=17;
                17:begin
                    work[(sample_row+1)*8+sample_col+1]<=pixel_q && sample_row_allowed;
                    if(sample_col==5) begin
                        sample_col<=0;
                        if(sample_row==13) begin
                            state<=19;
                        end else begin sample_row<=sample_row+1'b1;state<=11;end
                    end else begin sample_col<=sample_col+1'b1;state<=11;end
                end
                18:begin
                    snapshot_green<=roi_green;snapshot_valid<=1;
                    result_left<=bx;result_right<=bx+original_w-1;result_top<=by;result_bottom<=by+original_h-1;
                    state<=0;
                end
                19:begin
                    case(slot)
                        0:glyphs[127:0]<=work;1:glyphs[255:128]<=work;
                        2:glyphs[383:256]<=work;3:glyphs[511:384]<=work;
                        4:glyphs[639:512]<=work;5:glyphs[767:640]<=work;
                        6:begin glyphs[895:768]<=work;if(!roi_green) begin glyphs[1023:896]<=0;glyph_aspects[63:56]<=0;end end
                        7:glyphs[1023:896]<=work;
                    endcase
                    if(slot==expected-1) state<=18;
                    else begin slot<=slot+1'b1;state<=6;end
                end
                20:begin
                    // 1/16 and 15/16 quantiles (6.25% / 93.75%).
                    cumulative<=cumulative+histogram[bin_index];state<=21;
                end
                21:begin
                    if(!low_seen && cumulative>=(sample_count>>4)) begin low_bin<=bin_index;low_seen<=1;end
                    if(cumulative<sample_count-(sample_count>>4)) high_bin<=bin_index+1'b1;
                    if(bin_index==15) state<=22;
                    else begin bin_index<=bin_index+1'b1;state<=20;end
                end
                22:begin
                    for(k=0;k<8;k=k+1) begin
                        band_valid[k]<=band_max[k]>band_min[k]+9'd32;
                        band_threshold[k]<=band_min[k]+((band_max[k]-band_min[k])>>2);
                    end
                    threshold_valid<=sample_count>=128 && high_bin>=low_bin+2;
                    // Green plates have a bright-to-dark green gradient. The
                    // midpoint can label the lower background as black ink.
                    // Use the lower-quarter contrast threshold for dark text.
                    if(GREEN_DARK_QUANTILE && roi_green)
                        threshold<={low_bin,4'b0}+((high_bin-low_bin)<<2)+8;
                    else threshold<=({1'b0,low_bin,3'b0}+{1'b0,high_bin,3'b0})+8;
                    threshold_green<=roi_green;threshold_bx<=bx;threshold_by<=by;
                    // A new target first learns its own contrast threshold.
                    // Do not publish glyphs captured with a startup guess.
                    if(QUALITY_FILTER && (sample_count<128 || high_bin<low_bin+2)) begin
                        rejected<=1;quality_rejected<=1;reject_reason<=2;state<=0;
                    end else if(QUALITY_FILTER &&
                        (bright_count>sample_count-(sample_count>>2) || dark_count>sample_count-(sample_count>>2))) begin
                        rejected<=1;quality_rejected<=1;reject_reason<=3;state<=0;
                    end else if(QUALITY_FILTER && edge_count<(sample_count>>8)) begin
                        rejected<=1;quality_rejected<=1;reject_reason<=4;state<=0;
                    end else if(REQUIRE_CALIBRATION && !capture_calibrated) begin
                        rejected<=1;reject_reason<=1;state<=0;
                    end else if(capture_uses_gray) begin state<=32;row_foreground<=0;end
                    else state<=30;
                end
                32:state<=33;
                33:begin
                    if(gray_mask_we) begin
                        if(gray_mask_pixel) row_foreground<=row_foreground+1'b1;
                    end
                    if(gray_done) state<=37;
                end
                37:state<=38;
                38:if(clean_done) begin
                    if(clean_overflow) begin rejected<=1;quality_rejected<=1;reject_reason<=5;state<=0;end
                    else begin row_index<=0;index<=0;row_foreground<=0;state<=34;end
                end
                // Rebuild row occupancy by scanning the same binary ROI RAM.
                34:begin read_address<=shared_address;state<=35;end
                35:state<=36;
                36:begin
                    if(pixel_q) row_foreground<=row_foreground+1'b1;
                    if(index==bw-1) begin
                        allowed_rows[row_index]<=row_foreground+pixel_q>=(bw>>5) && row_foreground+pixel_q<bw-(bw>>3);
                        row_foreground<=0;index<=0;
                        if(row_index==bh-1) begin index<=0;state<=30;end
                        else begin row_index<=row_index+1'b1;state<=34;end
                    end else begin index<=index+1'b1;state<=34;end
                end
                26:begin
                    starts[slot]<=cell_begin_product>>8;
                    ends[slot]<=(cell_end_product>>8)-1'b1;
                    if(slot==expected-1) begin slot<=0;state<=6;end
                    else slot<=slot+1'b1;
                end
                27:begin numerator<={glyph_width,6'b0};denominator<=glyph_height;state<=28;end
                28:begin div_start<=1;state<=29;end
                29:if(div_done) begin
                    glyph_aspects[slot*8+:8]<=quotient>255?8'd255:quotient[7:0];state<=11;
                end
                30:begin
                    row_index<=0;row_in_run<=0;best_row_height<=0;text_top<=0;text_bottom<=0;state<=31;
                end
                31:begin
                    if(row_index<bh && allowed_rows[row_index]) begin
                        if(!row_in_run) begin row_run_start<=row_index;row_in_run<=1;end
                        row_run_end<=row_index;
                    end else if(row_in_run && row_index>row_run_end+1) begin
                        if(row_run_end-row_run_start+1>best_row_height) begin
                            best_row_height<=row_run_end-row_run_start+1;
                            text_top<=row_run_start;text_bottom<=row_run_end;
                        end
                        row_in_run<=0;
                    end
                    if(row_index>=bh+3) state<=4;
                    else row_index<=row_index+1'b1;
                end
                default:state<=0;
            endcase
        end
    end
endmodule
