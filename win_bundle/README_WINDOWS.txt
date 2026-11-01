KH Coder 3 (source build) for Windows x64
=========================================

Built from the GPL source at https://github.com/ko-ichi-h/khcoder with
win_bundle\build.ps1. This is the open-source beta, not the official
commercial "KH Coder 5" package.

How to run
----------
1. Extract the zip to a short path without non-ASCII characters,
   e.g. C:\khcoder  (avoid Desktop/Downloads folders with Japanese/Chinese names).
2. Double-click kh_coder.bat.
   A console window opens (keep it open), then the KH Coder window.
   The first start takes a little longer while MariaDB and R start.
3. If Windows Firewall asks about mysqld.exe, you can deny it: the database
   only listens on 127.0.0.1 port 3307.

Included
--------
  perl\                     Strawberry Perl 5.34 (portable) with Perl/Tk etc.
  dep\mysql\                MariaDB 10.11 (KH Coder starts/stops it itself)
  dep\R\                    R 4.6 with the packages KH Coder uses
  dep\AdoptOpenJDK64\       Eclipse Temurin Java 17 runtime
  dep\stanford-postagger\   English / Chinese POS tagging
  dep\stanford-segmenter\   Chinese word segmentation
  dep\mecab\                MeCab + IPADIC (UTF-8) for Japanese
  dep\pandoc-...\           pandoc (for .docx input)

Languages: English (Stanford POS Tagger or Snowball stemmer),
Japanese (MeCab), Chinese (Stanford). ChaSen, HanDic (Korean) and
FreeLing (other European languages) are not included.

Your projects and the database live in config\ inside this folder,
so copy the whole folder to back up or move it.
