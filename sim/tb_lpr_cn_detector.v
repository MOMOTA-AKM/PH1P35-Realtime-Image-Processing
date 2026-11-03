`timescale 1ns/1ps
module tb_lpr_cn_detector;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ft=0,de=0;
    reg [11:0] x=0,y=0;
    reg [23:0] rgb=0;
    wire found,green;
    wire [11:0] l,r,t,b;
    integer xx,yy;
    lpr_cn_detector dut(.clk(clk),.rst_n(rst_n),.frame_tick(ft),.de(de),
        .x(x),.y(y),.rgb(rgb),.found(found),.green(green),.left(l),.right(r),.top(t),.bottom(b));
    task rectangle;
        input integer x0,y0,w,h;
        input [23:0] color;
        begin
            for(yy=y0;yy<y0+h;yy=yy+1) for(xx=x0;xx<x0+w;xx=xx+1) begin
                x=xx;y=yy;de=1;rgb=color;@(negedge clk);
                if(xx==x0+w-1) begin de=0;repeat(24) @(negedge clk);end
            end
            de=0;@(negedge clk);
        end
    endtask
    task publish;
        begin ft=1;@(negedge clk);ft=0;repeat(24) @(negedge clk);end
    endtask
    initial begin
        #22;rst_n=1;repeat(4) @(negedge clk);
        rectangle(100,250,300,100,24'h1038b8);publish;
        if(!found || green || l!=100 || r!=399 || t!=250 || b!=349) $fatal(1,"blue bbox");
        rectangle(200,300,400,100,24'h98dfa8);publish;
        if(!found || !green || l!=200 || r!=599 || t!=300 || b!=399) $fatal(1,"green bbox");
        rectangle(100,250,300,100,24'h1038b8);
        rectangle(700,350,320,100,24'h98dfa8);publish;
        if(!found || !green || l!=700 || r!=1019) $fatal(1,"colors merged or wrong dominant candidate");
        rectangle(100,20,300,100,24'h1038b8);publish;
        if(found) $fatal(1,"OSD area accepted");
        rectangle(100,250,300,100,24'h999999);publish;
        if(found) $fatal(1,"grey background accepted");
        rectangle(100,250,1000,250,24'h98dfa8);publish;
        if(!found || !green || l!=100 || r!=1099 || b!=499) $fatal(1,"large plate rejected");
        rectangle(20,250,1201,100,24'h98dfa8);publish;
        if(found) $fatal(1,"oversized ROI accepted");
        publish;if(found) $fatal(1,"stale bbox");
        // Same-color clutter on a different row must not contaminate the plate.
        rectangle(900,200,150,40,24'h1038b8);
        rectangle(150,350,400,100,24'h1038b8);publish;
        if(!found || green || l!=150 || r!=549 || t!=350 || b!=449) $fatal(1,"same color background merged");
        // Small clutter beside the plate on every row is also kept separate.
        for(yy=250;yy<350;yy=yy+1) begin
            for(xx=0;xx<1280;xx=xx+1) begin
                x=xx;y=yy;de=1;
                rgb=((xx>=150 && xx<550) || (xx>=950 && xx<1050))?24'h1038b8:24'h303238;
                @(negedge clk);
            end
            de=0;repeat(24) @(negedge clk);
        end
        publish;
        if(!found || green || l!=150 || r!=549 || t!=250 || b!=349) $fatal(1,"same row clutter merged");
        for(yy=288;yy<432;yy=yy+1) begin
            for(xx=384;xx<896;xx=xx+1) begin
                x=xx;y=yy;de=1;rgb=24'h1038b8;
                if(yy>=312 && yy<408 && xx>=416 && xx<808 && ((xx-416)%56)<30) rgb=24'hffffff;
                @(negedge clk);
            end
            de=0;repeat(24) @(negedge clk);
        end
        publish;
        if(!found || l!=384 || r!=895 || t!=288 || b!=431) $fatal(1,"large plate white character gaps");
        // Pale upper background + saturated lower background from green
        // plate references. The whole region, not only its lower half, joins.
        rectangle(200,250,400,50,24'hdce5df);
        rectangle(200,300,400,50,24'h52a66c);publish;
        if(!found || !green || l!=200 || r!=599 || t!=250 || b!=349) $fatal(1,"pale green gradient lost");
        // Cyan-leaning pale green: old G-B>5 rejects this entirely.
        rectangle(200,250,400,100,24'hb4c8c4);publish;
        if(!found || !green) $fatal(1,"pale cyan green lost");
        rectangle(200,250,400,100,24'h203a30);publish;
        if(found) $fatal(1,"dark low-confidence pixels accepted");
        rectangle(200,250,400,100,24'hfafafa);publish;
        if(found) $fatal(1,"white overflow accepted");
        rectangle(200,250,400,100,24'hdce1df);publish;
        if(found) $fatal(1,"near-neutral green cast accepted");
        rectangle(200,250,400,100,24'ha89f8c);publish;
        if(found) $fatal(1,"warm floor accepted");
        rectangle(200,250,400,100,24'h8caaaa);publish;
        if(found) $fatal(1,"cyan background accepted");
        $display("PASS tb_lpr_cn_detector independent_colors local_candidates search_top large_plate invalid_size no_plate same_color_clutter adaptive_white_gaps");$finish;
    end
    initial begin #20000000;$fatal(1,"detector timeout");end
endmodule
