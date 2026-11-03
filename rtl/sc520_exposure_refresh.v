// Fixed full-frame exposure and low-light gain. Re-issue after initialization
// and periodically; never change gain when a display-mode button is pressed.
module sc520_exposure_refresh #(
    parameter CLOCK_HZ=23809524, EXPOSURE=1991, GAIN=144
)(
    input clk,rst_n,cam_ready,ae_ready,
    output reg request,
    output [15:0] exposure,gain
);
    assign exposure=EXPOSURE;
    assign gain=GAIN;
    reg [24:0] counter;
    reg [1:0] state;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin counter<=0;state<=0;request<=0;end
        else begin
            request<=0;
            if(!cam_ready) begin state<=0;counter<=0;end
            else case(state)
                0:if(ae_ready) begin request<=1;state<=1;counter<=0;end
                1:begin
                    // Wait for the receiver to acknowledge the one-cycle request.
                    if(!ae_ready) begin state<=2;counter<=0;end
                    else if(counter==CLOCK_HZ-1) begin state<=0;counter<=0;end
                    else counter<=counter+1'b1;
                end
                2:if(ae_ready) begin state<=3;counter<=0;end
                3:if(counter==CLOCK_HZ-1) begin state<=0;counter<=0;end
                  else counter<=counter+1'b1;
            endcase
        end
    end
endmodule
