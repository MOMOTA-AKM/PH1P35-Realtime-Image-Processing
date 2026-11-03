param(
 [string]$TdRoot=$env:TD_ROOT,
 [string]$PythonExe='python'
)
$ErrorActionPreference='Stop'
if(!$TdRoot){throw 'Set TD_ROOT or provide -TdRoot with the Tang Dynasty installation directory.'}
$root=Split-Path $PSScriptRoot -Parent
$td=Join-Path $TdRoot 'bin\td_commands_prompt.exe'
if(!(Test-Path -LiteralPath $td)){throw 'TD command launcher not found.'}
Push-Location $root
try {
 if(!(Test-Path -LiteralPath 'vendor\td_project\camera_to_dsi_display.al')){throw 'Import separately licensed platform dependencies first; see README.md.'}
 & $PythonExe tools/prepare_project.py --variant cn
 if($LASTEXITCODE-ne 0){throw 'Project preparation failed.'}
 & $td tools/build.tcl
 if($LASTEXITCODE-ne 0){throw 'TD build failed; inspect tool output.'}
 $timing=Get-Content -LiteralPath 'build\public\timing.rpt' -Raw
 foreach($metric in @('SWNS','HWNS')){
  $m=[regex]::Match($timing,($metric+':\s*(-?[\d.]+)ns'))
  if(!$m.Success){throw ('Missing timing metric: '+$metric)}
  $value=[double]::Parse($m.Groups[1].Value,[cultureinfo]::InvariantCulture)
  if($value-lt 0){throw ('Timing failed: '+$metric+'='+$value)}
 }
 Write-Output 'Build complete: build/public/hx1p35_lpr.bit; setup and hold checks passed.'
} finally{Pop-Location}
