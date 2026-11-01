@echo off
rem Starts KH Coder with the bundled Perl. MariaDB and R are started by KH Coder itself.
setlocal
cd /d "%~dp0"
set "PATH=%~dp0perl\perl\site\bin;%~dp0perl\perl\bin;%~dp0perl\c\bin;%SystemRoot%\system32;%SystemRoot%;%SystemRoot%\System32\Wbem"
set PERL5LIB=
set PERL5OPT=
perl kh_coder.pl %*
if errorlevel 1 pause
