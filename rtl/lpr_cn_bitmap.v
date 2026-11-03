// 8 x 16Kx1 PH1P block RAM banks. NOREG output still reads on the clock edge.
// XSim uses the matching synchronous behavioral model via an explicit define;
// TD uses the native macro, avoiding distributed-RAM inference ambiguity.
module lpr_cn_bitmap(
    input clk,rst_n,we,di,
    input [16:0] wa,ra,
    output dout,
    output reg test_done,test_error
);
    wire [7:0] bank_q;
    reg [2:0] bank_select;
    // Boot-time write/read test exercises both values, bank selects, first/
    // last addresses. It completes in 256 clocks, before ROI column clearing.
    reg [5:0] probe;
    reg [1:0] probe_state;
    wire [13:0] probe_low=probe[1]?14'd16382+probe[0]:{13'b0,probe[0]};
    wire [16:0] probe_address={probe[4:2],probe_low};
    wire probe_value=probe[5]^probe[0];
    wire memory_we=test_done?we:probe_state==0;
    wire memory_di=test_done?di:probe_value;
    wire [16:0] memory_wa=test_done?wa:probe_address;
    wire [16:0] memory_ra=test_done?ra:probe_address;
    always @(posedge clk) bank_select<=memory_ra[16:14];
    assign dout=bank_q[bank_select];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin probe<=0;probe_state<=0;test_done<=0;test_error<=0;end
        else if(!test_done) begin
            if(probe_state==3) begin
                if(dout!=probe_value) test_error<=1;
                if(probe==63) test_done<=1;
                else probe<=probe+1'b1;
                probe_state<=0;
            end else probe_state<=probe_state+1'b1;
        end
    end
    genvar bank;
    generate for(bank=0;bank<8;bank=bank+1) begin:banks
`ifdef LPR_BEHAVIORAL_RAM
        reg mem[0:16383];
        reg q;
        always @(posedge clk) begin
            if(memory_we && memory_wa[16:14]==bank) mem[memory_wa[13:0]]<=memory_di;
            q<=mem[memory_ra[13:0]];
        end
        assign bank_q[bank]=q;
`else
        PH1P_LOGIC_ERAM #(
            .DATA_WIDTH_A(1),.DATA_WIDTH_B(1),.ADDR_WIDTH_A(14),.ADDR_WIDTH_B(14),
            .DATA_DEPTH_A(16384),.DATA_DEPTH_B(16384),.MODE("DP"),
            .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
            .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
            .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
            .CLKMODE("SYNC"),.IMPLEMENT("20K(FAST)")
        ) ram(
            .dia(memory_di),.addra(memory_wa[13:0]),.cea(1'b1),.ocea(1'b1),.clka(clk),
            .wea(memory_we && memory_wa[16:14]==bank),.rsta(1'b0),.bea(1'b1),.doa(),
            .dib(1'b0),.addrb(memory_ra[13:0]),.ceb(1'b1),.oceb(1'b1),.clkb(clk),
            .web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(bank_q[bank]),
            .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
`endif
    end endgenerate
endmodule
