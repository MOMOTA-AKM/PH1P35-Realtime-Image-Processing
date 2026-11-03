"""Generate the TD project after importing the separately licensed platform dependencies."""
from pathlib import Path
import xml.etree.ElementTree as ET
import argparse

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--variant',choices=['cn'],default='cn')
    args=parser.parse_args()
    source=ROOT/'vendor/user_source/hdl_source/design_top_wrapper.v'
    top=source.read_text(encoding='utf-8')
    top=top.replace('module design_top_wrapper (','module hx1p35_lpr_top (',1)
    top=top.replace('inout wire [1:0]  I_button,',
        'inout wire [1:0]  I_button,\n    output wire [3:0] O_led,\n    output wire [7:0] O_seg,\n    output wire [7:0] O_sel,',1)
    # Keep the supplied SC520 camera setup exactly as-is.  All additions below
    # are downstream display/image-processing logic; no sensor registers,
    # exposure, gain, MIPI or CSI source is replaced.
    assert 'ae_set u_ae_set' in top and '.I_btn({I_button,2\'b11})' in top
    # Keep SC520 I2C/MIPI/ISP intact; replace only the manual gain requester.
    ae_begin=top.index('  ae_set u_ae_set (')
    ae_end=top.index(');',ae_begin)+2
    top=top[:ae_begin]+'''  sc520_exposure_refresh exposure_control (
      .clk(S_24m_clk), .rst_n(S_rst_n),
      .cam_ready(S_cam_cfg_done), .ae_ready(S_ae_cfg_done),
      .request(S_ae_req), .exposure(S_ae), .gain(S_ag)
  );'''+top[ae_end:]
    marker='    hdmi_tx u_hdmi_tx('
    assert top.count(marker)==1
    instance='''    // Plate-only additions start here (camera foundation unchanged).
    wire lpr_vs, lpr_hs, lpr_de;
    wire [23:0] lpr_rgb;
    lpr_cn_video cn_video (
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n),
        .vs(S_hdmi_out_vsync), .hs(S_hdmi_out_hsync),
        .de(S_hdmi_out_de), .rgb(S_hdmi_out_data),
        .mode_button(I_button[0]), .clear_button(I_button[1]),
        .out_vs(lpr_vs), .out_hs(lpr_hs), .out_de(lpr_de), .out_rgb(lpr_rgb),
        .leds(O_led), .seg(O_seg), .sel(O_sel)
    );

'''
    before,after=top.split(marker)
    after=after.replace('( S_hdmi_out_vsync  )','( lpr_vs            )')
    after=after.replace('( S_hdmi_out_de     )','( lpr_de            )')
    after=after.replace('( S_hdmi_out_data   )','( lpr_rgb           )')
    top=before+instance+marker+after
    out=ROOT/'rtl/hx1p35_lpr_top.v'
    out.write_text(top,encoding='utf-8')
    # Correct official sample reset/buttons to match the supplied board manual.
    adc=(ROOT/'vendor/user_source/constraints_source/pin.adc').read_text(encoding='utf-8')
    adc=adc.replace('LOCATION = R10','LOCATION = D5')
    adc=adc.replace('LOCATION = N2','LOCATION = A9').replace('LOCATION = J14','LOCATION = B9')
    adc='\n'.join(line.replace('DRIVESTRENGTH = 8;','') if 'I_button[' in line else line
                  for line in adc.splitlines())
    extras={'O_led[0]':'D10','O_led[1]':'E10','O_led[2]':'C6','O_led[3]':'D6'}
    adc+='\n# Plate-only status LEDs. No mode switches.\n'
    adc+=''.join(f'set_pin_assignment {{ {name} }} {{ LOCATION = {pin}; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }}\n'
                 for name,pin in extras.items())
    adc+='\n# Eight-digit seven-segment display (active low).\n'
    for name,pin in {'O_seg[0]':'C9','O_seg[1]':'C11','O_seg[2]':'B11','O_seg[3]':'E7','O_seg[4]':'E6','O_seg[5]':'B6','O_seg[6]':'B7','O_seg[7]':'E5','O_sel[0]':'G15','O_sel[1]':'G14','O_sel[2]':'A17','O_sel[3]':'A18','O_sel[4]':'B16','O_sel[5]':'A15','O_sel[6]':'B15','O_sel[7]':'A14'}.items():
        adc+=f'set_pin_assignment {{ {name} }} {{ LOCATION = {pin}; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }}\n'
    (ROOT/'constraints').mkdir(exist_ok=True)
    (ROOT/'constraints/hx1p35.adc').write_text(adc,encoding='utf-8')
    for filename in ['cn_words.mem','cn_templates.mem','cn_aspects.mem','cn_green_words.mem','cn_green_aspects.mem']:
        for folder in ['rtl','td_project','sim']:
            (ROOT/folder/filename).write_bytes((ROOT/'assets/cn'/filename).read_bytes())
    original=ROOT/'vendor/td_project/camera_to_dsi_display.al'
    # TD uses a pseudo-XML attribute value "UsedInP&R" with a literal ampersand.
    project=ET.fromstring(original.read_text(encoding='utf-8').replace('P&R','P&amp;R').replace('::','__COLON__'))
    tree=ET.ElementTree(project)
    project.set('Path',(ROOT/'td_project').as_posix())
    project.find('Name').text='hx1p35_lpr'
    for label in ['LABEL','MODULE']:
        project.find('TOP_MODULE/'+label).text='hx1p35_lpr_top'
    for run in project.findall('Runs/Run'):
        run.attrib.pop('useDefaultScript',None)
    for f in project.findall('.//Source_Files/*/File'):
        old=f.get('Path')
        if old.endswith('/design_top_wrapper.v'):
            new='../rtl/hx1p35_lpr_top.v'
        elif old.endswith('/pin.adc'):
            new='../constraints/hx1p35.adc'
        elif old=='camera_to_dsi_display.sdc':
            new='../vendor/td_project/camera_to_dsi_display.sdc'
        else:
            new=old.replace('../user_source/','../vendor/user_source/')
        f.set('Path',new)
        assert (ROOT/'td_project'/new).exists(),new
    files=project.find('Source_Files/Verilog')
    cn_sources=['lpr_cn_bitmap.v','lpr_cn_detector.v','lpr_cn_segment.v','lpr_cn_ocr.v',
                'lpr_cn_video.v','lpr_cn_font.v','lpr_cn_tracker.v','lpr_divider.v',
        'lpr_cn_sampler.v','lpr_cn_vote.v','lpr_sobel_support.v','lpr_mode_seg.v','sc520_exposure_refresh.v',
        'lpr_green_gray_roi.v','lpr_green_components.v']
    for order,name in enumerate(cn_sources,100):
        path=ROOT/'rtl'/name
        f=ET.SubElement(files,'File',Path='../rtl/'+path.name)
        info=ET.SubElement(f,'FileInfo')
        for name,val in [('UsedInSyn','true'),('UsedInP&R','true'),
                         ('BelongTo','design_1'),('CompileOrder',str(order))]:
            ET.SubElement(info,'Attr',Name=name,Val=val)
    ET.indent(tree,space='    ')
    serialized=ET.tostring(project,encoding='unicode').replace('P&amp;R','P&R').replace('__COLON__','::')
    (ROOT/'td_project/hx1p35_lpr.al').write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'+serialized,encoding='utf-8')
    print('TD project:',ROOT/'td_project/hx1p35_lpr.al')
    print('All project references exist; original vendor source is unchanged.')
    (ROOT/'td_project/variant.txt').write_text(args.variant,encoding='ascii')


if __name__=='__main__': main()
