# Builds a self-contained KH Coder bundle for Windows x64 from this source tree.
#
#   powershell -ExecutionPolicy Bypass -File win_bundle\build.ps1
#
# Result: dist\khcoder\  (run kh_coder.bat inside it)
# Layout follows what kh_lib\kh_all_in_one.pm expects:
#   perl\                       Strawberry Perl (portable) + CPAN modules
#   dep\mysql\                  MariaDB server, started by KH Coder on port 3307
#   dep\R\                      R + packages used by KH Coder's plots
#   dep\AdoptOpenJDK64\         Java runtime for the Stanford tools
#   dep\stanford-postagger\     English / Chinese POS tagging
#   dep\stanford-segmenter\     Chinese word segmentation
#   dep\mecab\                  Japanese morphological analysis (UTF-8 IPADIC)
#   dep\pandoc-2.7.3-windows-i386\
#   config\mysql_data\          pre-initialized database (users khc/khc, root/khcallinone)

param(
	[string]$Out   = "$PWD\dist\khcoder",
	[string]$Cache = "$PWD\dist\cache"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Repo = (Resolve-Path "$PSScriptRoot\..").Path
$Here = $PSScriptRoot

$StrawberryUrl = 'https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/sp5.34.3.1/strawberry-perl-5.34.3.1-64bit-portable.zip'
$MariaDbVer    = '10.11.19'
$MariaDbUrl    = "https://archive.mariadb.org/mariadb-$MariaDbVer/winx64-packages/mariadb-$MariaDbVer-winx64.zip"
$RVer          = '4.6.2'
$RUrls         = @(
	"https://cloud.r-project.org/bin/windows/base/R-$RVer-win.exe",
	"https://cloud.r-project.org/bin/windows/base/old/$RVer/R-$RVer-win.exe"
)
$RtoolsUrl     = 'https://cloud.r-project.org/bin/windows/Rtools/rtools45/files/rtools45-6768-6492.exe'
$JreUrl        = 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jre/hotspot/normal/eclipse'
$TaggerUrl     = 'https://downloads.cs.stanford.edu/nlp/software/stanford-postagger-full-2018-10-16.zip'
$SegmenterUrl  = 'https://downloads.cs.stanford.edu/nlp/software/stanford-segmenter-2018-10-16.zip'
$MecabUrl      = 'https://github.com/ikegami-yukino/mecab/releases/download/v0.996.2/mecab-64-0.996.2.exe'
$PandocUrl     = 'https://github.com/jgm/pandoc/releases/download/2.7.3/pandoc-2.7.3-windows-i386.zip'

$PerlModules = @(
	# GUI
	'Tk', 'Tk::FontDialog', 'Tk::MatchEntry', 'Tk::WaitBox', 'Tk::Icon',
	# data / text
	'Algorithm::NaiveBayes', 'Clipboard', 'Clone', 'DBD::CSV', 'Excel::Writer::XLSX',
	'File::BOM', 'File::Copy::Recursive', 'Jcode', 'Encode::EUCJPMS',
	'Lingua::JA::Regular::Unicode', 'Lingua::Sentence', 'Lingua::Stem::Snowball',
	'MySQL::Backup', 'Net::Telnet', 'Proc::Background', 'Spreadsheet::ParseExcel',
	'Spreadsheet::ParseXLSX', 'Statistics::ChisqIndep', 'Statistics::Lite',
	'Text::CSV_XS', 'Text::Diff', 'Text::Iconv', 'Text::Unidecode', 'YAML',
	# Windows helpers
	'Win32::Process::Info', 'Win32::Process::List', 'Win32::SearchPath',
	'Win32::SystemInfo', 'Win32::DriveInfo', 'Devel::Platform::Info'
)

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Invoke-Native {
	param([string]$Exe, [string[]]$Arguments)
	& $Exe @Arguments
	if ($LASTEXITCODE -ne 0) { throw "$Exe exited with $LASTEXITCODE" }
}

function Get-File([string[]]$Urls, [string]$Name) {
	$dest = Join-Path $Cache $Name
	if (Test-Path $dest) { return $dest }
	foreach ($u in $Urls) {
		Write-Host "Downloading $u"
		& curl.exe -fsSL --retry 5 --retry-delay 10 -o "$dest.part" $u
		if ($LASTEXITCODE -eq 0) {
			Move-Item "$dest.part" $dest
			return $dest
		}
	}
	throw "Download failed: $Name"
}

function Expand-Zip([string]$Zip, [string]$Dest) {
	New-Item -ItemType Directory -Force $Dest | Out-Null
	Invoke-Native tar.exe @('-xf', $Zip, '-C', $Dest)
}

# Extract a zip whose content sits in one top-level folder; that folder becomes $Dest.
function Expand-ZipFlat([string]$Zip, [string]$Dest) {
	$tmp = "$Dest.tmp"
	Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
	Expand-Zip $Zip $tmp
	$inner = @(Get-ChildItem $tmp)
	if ($inner.Count -eq 1 -and $inner[0].PSIsContainer) {
		Move-Item $inner[0].FullName $Dest
		Remove-Item -Recurse -Force $tmp
	} else {
		Move-Item $tmp $Dest
	}
}

# Fill in the paths that kh_all_in_one.pm normally rewrites at start-up.
function Write-MysqlIni([string]$Template, [string]$Target, [string]$Base, [string]$Data, [string]$Screen) {
	$b = ($Base   -replace '\\', '/') + '/'
	$d = ($Data   -replace '\\', '/') + '/'
	$s = ($Screen -replace '\\', '/') + '/'
	(Get-Content $Template) |
		ForEach-Object {
			$_ -replace '^basedir = .+$',          "basedir = $b" `
			   -replace '^datadir = .+$',          "datadir = $d" `
			   -replace '^tmpdir = .+$',           "tmpdir = ${b}tmp/" `
			   -replace '^secure-file-priv = .+$', "secure-file-priv = $s"
		} |
		Set-Content -Encoding ascii $Target
}

function Wait-Port([int]$Port, [int]$Seconds) {
	$deadline = (Get-Date).AddSeconds($Seconds)
	while ((Get-Date) -lt $deadline) {
		$c = New-Object Net.Sockets.TcpClient
		try { $c.Connect('127.0.0.1', $Port); $c.Close(); return } catch { Start-Sleep 1 }
	}
	throw "Nothing listening on port $Port after $Seconds s"
}

Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Out, $Cache, "$Out\dep" | Out-Null
$Out = (Resolve-Path $Out).Path

#--------------------------------------------------------------------------
Step 'KH Coder source'
foreach ($i in 'kh_coder.pl', 'kh_lib', 'config', 'plugin_en', 'plugin_jp', 'LICENSE', 'README.md') {
	Copy-Item -Recurse "$Repo\$i" $Out
}
New-Item -ItemType Directory -Force "$Out\screen" | Out-Null
Copy-Item "$Here\kh_coder.bat", "$Here\README_WINDOWS.txt" $Out
Copy-Item "$Here\coder.ini" "$Out\config\coder.ini"

#--------------------------------------------------------------------------
Step 'Strawberry Perl + CPAN modules'
Expand-Zip (Get-File @($StrawberryUrl) 'strawberry.zip') "$Out\perl"
# Use only the bundled Perl (the runner image ships its own Strawberry in C:\Strawberry).
foreach ($v in 'PERL5LIB', 'PERL5OPT', 'PERL_LOCAL_LIB_ROOT', 'PERL_MB_OPT', 'PERL_MM_OPT') {
	Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
$env:PATH = "$Out\perl\perl\site\bin;$Out\perl\perl\bin;$Out\perl\c\bin;$env:PATH"
Invoke-Native perl @('-MDBD::mysql', '-e', 'print "Perl $^V, DBD::mysql $DBD::mysql::VERSION\n"')
$failed = @()
foreach ($m in $PerlModules) {
	& cpanm --notest --quiet $m
	if ($LASTEXITCODE -ne 0) { $failed += $m }
}
if ($failed) {
	Get-ChildItem "$env:USERPROFILE\.cpanm\work" -Recurse -Filter build.log -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail 80
	throw "CPAN modules failed: $($failed -join ', ')"
}

#--------------------------------------------------------------------------
Step "MariaDB $MariaDbVer"
$my = "$Out\dep\mysql"
Expand-ZipFlat (Get-File @($MariaDbUrl) 'mariadb.zip') $my
Remove-Item -Recurse -Force "$my\mysql-test", "$my\sql-bench", "$my\include" -ErrorAction SilentlyContinue
Get-ChildItem $my -Recurse -Include *.pdb, *.lib | Remove-Item -Force
foreach ($pair in @(@('mysqld.exe', 'mariadbd.exe'), @('mysqladmin.exe', 'mariadb-admin.exe'))) {
	if (-not (Test-Path "$my\bin\$($pair[0])")) { Copy-Item "$my\bin\$($pair[1])" "$my\bin\$($pair[0])" }
}
New-Item -ItemType Directory -Force "$my\tmp" | Out-Null
Copy-Item "$Here\khc.ini" "$my\khc.ini"

$data = "$Out\config\mysql_data"
$installDb = @('mariadb-install-db.exe', 'mysql_install_db.exe') | ForEach-Object { "$my\bin\$_" } |
	Where-Object { Test-Path $_ } | Select-Object -First 1
Invoke-Native $installDb @("--datadir=$data", '--password=khcallinone', '--port=3307')
Remove-Item "$data\my.ini" -ErrorAction SilentlyContinue

Write-MysqlIni "$Here\khc.ini" "$my\khc.build.ini" $my $data "$Out\screen"
$mysqld = Start-Process "$my\bin\mysqld.exe" -ArgumentList '--defaults-file=khc.build.ini', '--standalone' `
	-WorkingDirectory $my -PassThru -NoNewWindow
Wait-Port 3307 60
$sql = @"
CREATE USER 'khc'@'localhost' IDENTIFIED BY 'khc';
CREATE USER 'khc'@'127.0.0.1' IDENTIFIED BY 'khc';
CREATE USER 'khc'@'::1' IDENTIFIED BY 'khc';
GRANT ALL PRIVILEGES ON *.* TO 'khc'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'khc'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'khc'@'::1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
"@
$client = @('mariadb.exe', 'mysql.exe') | ForEach-Object { "$my\bin\$_" } | Where-Object { Test-Path $_ } | Select-Object -First 1
Invoke-Native $client @('-uroot', '-pkhcallinone', '--port=3307', '-h127.0.0.1', '-e', $sql)
# Same shutdown path KH Coder uses (mysql_exec::shutdown_db_server).
Invoke-Native "$my\bin\mysqladmin.exe" @('--user=khc', '--password=khc', '--port=3307', 'shutdown')
$mysqld.WaitForExit(60000) | Out-Null
Remove-Item "$my\khc.build.ini"
Get-ChildItem $data -File | Where-Object { $_.Extension -in '.err', '.pid', '.log' } | Remove-Item -Force

#--------------------------------------------------------------------------
Step "R $RVer + packages"
$rExe = Get-File $RUrls "R-$RVer-win.exe"
$p = Start-Process $rExe -Wait -PassThru -ArgumentList `
	'/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/NOICONS', '/TASKS=""', "/DIR=`"$Out\dep\R`""
if ($p.ExitCode -ne 0) { throw "R installer exited with $($p.ExitCode)" }

if (-not (Test-Path 'C:\rtools45\usr\bin\make.exe')) {
	$rt = Get-File @($RtoolsUrl) 'rtools45.exe'
	$p = Start-Process $rt -Wait -PassThru -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/DIR=C:\rtools45'
	if ($p.ExitCode -ne 0) { throw "Rtools installer exited with $($p.ExitCode)" }
}
$env:RTOOLS45_HOME = 'C:\rtools45'
$env:RTOOLS46_HOME = 'C:\rtools45'
Invoke-Native "$Out\dep\R\bin\x64\Rscript.exe" @('--vanilla', "$Here\install_r_pkgs.R")
Remove-Item -Recurse -Force "$Out\dep\R\doc\manual" -ErrorAction SilentlyContinue

#--------------------------------------------------------------------------
Step 'Java runtime'
Expand-ZipFlat (Get-File @($JreUrl) 'jre17.zip') "$Out\dep\AdoptOpenJDK64"

#--------------------------------------------------------------------------
Step 'Stanford POS Tagger + Segmenter'
$tg = "$Out\dep\stanford-postagger"
Expand-ZipFlat (Get-File @($TaggerUrl) 'stanford-postagger.zip') $tg
if (-not (Test-Path "$tg\stanford-postagger.jar")) {
	Copy-Item (Get-ChildItem "$tg\stanford-postagger-*.jar" | Where-Object { $_.Name -notmatch 'sources|javadoc' } | Select-Object -First 1).FullName "$tg\stanford-postagger.jar"
}
foreach ($ext in '', '.props') {
	if (-not (Test-Path "$tg\models\wsj-0-18-left3words-distsim.tagger$ext") -and (Test-Path "$tg\models\english-left3words-distsim.tagger$ext")) {
		Copy-Item "$tg\models\english-left3words-distsim.tagger$ext" "$tg\models\wsj-0-18-left3words-distsim.tagger$ext"
	}
}
Expand-ZipFlat (Get-File @($SegmenterUrl) 'stanford-segmenter.zip') "$Out\dep\stanford-segmenter"

#--------------------------------------------------------------------------
Step 'MeCab'
$mc = "$Out\dep\mecab"
$p = Start-Process (Get-File @($MecabUrl) 'mecab-64.exe') -Wait -PassThru -ArgumentList `
	'/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/NOICONS', "/DIR=`"$mc`""
if ($p.ExitCode -ne 0) { throw "MeCab installer exited with $($p.ExitCode)" }
Remove-Item "$mc\unins*" -Force -ErrorAction SilentlyContinue
# The installer writes an absolute dicdir; make it relative to mecabrc so the folder can move.
(Get-Content "$mc\etc\mecabrc") -replace '^\s*dicdir\s*=.*$', 'dicdir = $(rcpath)\..\dic\ipadic' |
	Set-Content -Encoding ascii "$mc\etc\mecabrc"
$dicInfo = & "$mc\bin\mecab.exe" -D -r "$mc\etc\mecabrc"
$dicInfo | Write-Host
if (-not ($dicInfo -match 'charset:\s*utf-?8')) {
	Write-Host 'Rebuilding IPADIC as UTF-8'
	$src = ($dicInfo | Select-String 'charset:\s*(\S+)').Matches[0].Groups[1].Value
	Invoke-Native "$mc\bin\mecab-dict-index.exe" @('-d', "$mc\dic\ipadic", '-o', "$mc\dic\ipadic", '-f', $src, '-t', 'utf-8')
	$dicInfo = & "$mc\bin\mecab.exe" -D -r "$mc\etc\mecabrc"
	if (-not ($dicInfo -match 'charset:\s*utf-?8')) { throw 'MeCab dictionary is not UTF-8' }
}

#--------------------------------------------------------------------------
Step 'pandoc'
Expand-Zip (Get-File @($PandocUrl) 'pandoc.zip') "$Out\dep"
if (-not (Test-Path "$Out\dep\pandoc-2.7.3-windows-i386\pandoc.exe")) { throw 'pandoc not where kh_all_in_one.pm looks for it' }

Step 'Done'
"{0:N0} MB in $Out" -f ((Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
