"""Run the public core tests with a locally installed Vivado XSim."""
from pathlib import Path
import argparse,subprocess,re,json,time

ROOT=Path(__file__).resolve().parents[1]
TESTS=['tb_lpr_cn_sampler','tb_lpr_cn_vote','tb_lpr_cn_detector','tb_lpr_cn_tracker','tb_lpr_cn_quality','tb_lpr_sobel_support','tb_green_gray_roi','tb_green_components','tb_green_components_limits','tb_ocr_latency','tb_v24_address']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--vivado',type=Path,required=True);a=p.parse_args()
 binary=a.vivado/'bin';work=ROOT/'build/public_core';work.mkdir(parents=True,exist_ok=True)
 def run(command,filename):
  with (work/filename).open('w',encoding='utf-8') as out:
   result=subprocess.run(list(map(str,command)),cwd=work,stdout=out,stderr=subprocess.STDOUT,timeout=240)
  content=(work/filename).read_text(encoding='utf-8',errors='replace')
  if result.returncode:raise RuntimeError(f'Command failed: see {work/filename}')
  return content
 sources=[p for p in sorted((ROOT/'rtl').glob('lpr_*.v')) if p.name!='lpr_cn_font.v']
 sources += [ROOT/'sim'/(t+'.v') for t in TESTS]
 run([binary/'xvlog.bat','--sv','--define','LPR_BEHAVIORAL_RAM',*sources],'compile.log')
 print('COMPILE_PASS',flush=True);results=[]
 for test in TESTS:
  snapshot=test+'_public';start=time.monotonic()
  run([binary/'xelab.bat',test,'--snapshot',snapshot,'--timescale','1ns/1ps'],test+'_elab.log')
  output=run([binary/'xsim.bat',snapshot,'--runall'],test+'.log')
  # Several original testbenches report a descriptive PASS rather than their module name.
  if not re.search(r'^PASS\s+',output,re.M) or re.search(r'^(?:Fatal|FATAL|ERROR):',output,re.M):raise RuntimeError('Missing clean PASS: '+test)
  results.append({'test':test,'passed':True,'seconds':round(time.monotonic()-start,2)})
  print('PASS',test,flush=True)
 (work/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 print('ALL_PASS',len(results),flush=True)
if __name__=='__main__':main()
