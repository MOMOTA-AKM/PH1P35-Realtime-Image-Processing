"""Import local, separately licensed dependencies from a matching v24 project."""
from pathlib import Path
import argparse,shutil
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--from-project',type=Path,required=True)
 a=p.parse_args();source=a.from_project.resolve()
 if source==ROOT: p.error('Choose the original complete project, not this checkout.')
 required=['vendor/td_project/camera_to_dsi_display.al','vendor/user_source/hdl_source/design_top_wrapper.v','rtl/lpr_cn_font.v','assets/cn/cn_words.mem','td_project/cn_display_font.mem']
 for f in required:
  if not (source/f).is_file():p.error('Missing dependency: '+f)
 targets=['vendor','assets/cn','constraints','td_project']
 for d in targets:
  if (ROOT/d).exists():p.error('Destination already exists; use a fresh checkout: '+d)
 for d in targets:shutil.copytree(source/d,ROOT/d)
 shutil.copy2(source/'rtl/lpr_cn_font.v',ROOT/'rtl/lpr_cn_font.v')
 for f in (source/'rtl').glob('*.mem'):shutil.copy2(f,ROOT/'rtl'/f.name)
 print('Imported local dependencies. Their original licenses still apply.')
 print('Next: python tools/prepare_project.py --variant cn')
if __name__=='__main__':main()
