# Runs smoke_test.pl against a throw-away copy of the built bundle, so the shipped
# folder keeps its pristine config (coder.ini, empty project list, fresh database).
#
#   powershell -ExecutionPolicy Bypass -File win_bundle\smoke_test.ps1

param(
	[string]$Bundle = "$PWD\dist\khcoder",
	[string]$Logs   = "$PWD\dist\smoke",
	[int]$TimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$tmpRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$test = Join-Path $tmpRoot 'khc_smoke'

function Save-Screenshot([string]$File) {
	try {
		Add-Type -AssemblyName System.Windows.Forms, System.Drawing
		$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
		$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
		[System.Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
		$bmp.Save($File)
	} catch { Write-Host "Screenshot failed: $_" }
}

function Stop-BundleProcesses {
	& "$test\dep\mysql\bin\mysqladmin.exe" --user=khc --password=khc --port=3307 shutdown 2>$null
	Start-Sleep 3
	Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($test, 'OrdinalIgnoreCase') } |
		ForEach-Object { Write-Host "Killing $($_.Name) ($($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
}

Remove-Item -Recurse -Force $test, $Logs -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Logs | Out-Null
& robocopy.exe $Bundle $test /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
$global:LASTEXITCODE = 0
Copy-Item "$Here\smoke_test.pl" $test
Copy-Item -Recurse "$Here\samples" "$test\smoke_samples"

# Same environment as kh_coder.bat.
foreach ($v in 'PERL5LIB', 'PERL5OPT', 'PERL_LOCAL_LIB_ROOT', 'R_HOME', 'R_LIBS', 'R_LIBS_USER', 'JAVA_HOME') {
	Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
$env:PATH = "$test\perl\perl\site\bin;$test\perl\perl\bin;$test\perl\c\bin;$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"

$p = Start-Process "$test\perl\perl\bin\perl.exe" -ArgumentList 'smoke_test.pl' -WorkingDirectory $test `
	-RedirectStandardOutput "$Logs\stdout.txt" -RedirectStandardError "$Logs\stderr.txt" -PassThru
$finished = $p.WaitForExit($TimeoutMinutes * 60 * 1000)
Save-Screenshot "$Logs\screen.png"
if (-not $finished) { Write-Host "Timed out after $TimeoutMinutes minutes" }
Stop-BundleProcesses

foreach ($f in 'smoke_results.txt', 'config\coder.ini') {
	if (Test-Path "$test\$f") { Copy-Item "$test\$f" $Logs }
}
Get-ChildItem "$test\config\R-bridge" -ErrorAction SilentlyContinue | Copy-Item -Destination $Logs
Get-ChildItem "$test\config\mysql_data" -Filter *.err -ErrorAction SilentlyContinue | Copy-Item -Destination $Logs

Write-Host "`n--- stdout (tail) ---";  Get-Content "$Logs\stdout.txt" -Tail 120 -ErrorAction SilentlyContinue
Write-Host "`n--- stderr (tail) ---";  Get-Content "$Logs\stderr.txt" -Tail 60 -ErrorAction SilentlyContinue
Write-Host "`n--- results ---";        Get-Content "$Logs\smoke_results.txt" -Encoding utf8 -ErrorAction SilentlyContinue

$passed = $finished -and $p.ExitCode -eq 0 -and
	(Select-String -Path "$Logs\smoke_results.txt" -Pattern '^RESULT: PASS' -Quiet -ErrorAction SilentlyContinue)
Remove-Item -Recurse -Force $test -ErrorAction SilentlyContinue
if (-not $passed) { throw 'Smoke test failed' }
Write-Host 'Smoke test passed'
