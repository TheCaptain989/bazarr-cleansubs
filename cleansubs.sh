#!/bin/bash

# Script to remove common annoying scene branding and attribution from subtitle files
#  https://github.com/TheCaptain989/bazarr-cleansubs
# Works on properly formatted SRT files
# 
# Output is designed to be compatible with the Bazarr log file format
# Removed subtitle entries are included after the pipe symbol (|) and included in the Bazarr "Exception" details of each log entry

# Dependencies:
#  awk
#  dos2unix

# Exit codes:
#  0 - success
#  1 - no subtitle file specified on command line
#  5 - subtitle file not found
#  6 - unknown subtitle file type
# 10 - awk script failed to write temporary subtitle file

TEMPSUB="$1.tmp"
SUB="$1"
# Parking here for future use.
#RECYCLEBIN=$(python3 -c "import sqlite3
#conSql = sqlite3.connect('/config/db/bazarr.db')
#cursorObj = conSql.cursor()
#cursorObj.execute('SELECT Value from Config WHERE Key=\"recyclebin\"')
#print(cursorObj.fetchone()[0])
#conSql.close()")

if [ -z "$SUB" ]; then
  MSG="\nERROR: No subtitle file specified! Not called from Bazarr?"
  echo -n "$MSG"
  exit 1
fi

if [ ! -f "$SUB" ]; then
  MSG="\nERROR: Input file not found: \"$SUB\""
  echo -n "$MSG"
  exit 5
fi

if [[ "$SUB" != *.srt ]]; then
  # This script only works on SRT subtitles
  MSG="\nERROR: Expected SRT file. Incorrect file suffix: \"$SUB\""
  echo -n "$MSG"
  exit 6
fi

until [ ! -s "$TEMPSUB" ]; do
  # Temporary file already exists
  i=$((i+1))
  TEMPSUB="${TEMPSUB%%.*}.srt.$i.tmp"
done

cat "$SUB" | dos2unix | awk '
function escape_html(str){
  # escape HTML in subs
  gsub(/&/,"\\&amp;",str);gsub(/</,"\\&lt;",str);gsub(/>/,"\\&gt;",str);gsub(/"/,"\\&quot;",str)
  return str
}
BEGIN {
  RS=""     # one or more blank lines
  FS="\n"
  IGNORECASE=1
  MSGMAIN="<br/>cleansubs.sh<br/>Subtitle file: '"$SUB"'<br/>"
  TempSub="'"$TEMPSUB"'"
  indexdelta=0
}
$1 ~ /^\xef\xbb\xbf/ {
  if (NR == 1) { sub(/^\xef\xbb\xbf/,"") }    # Remove BOM for UTF-8 encoding
}
$1 ~ /^[0-9]+$/ {
  Entry=$1
  sub(Entry,"")
  Entry = Entry + indexdelta
}
$2 ~ /^[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2},[0-9]{1,3} --> [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2},[0-9]{1,3}$/ {
  Timestamp=$2
  sub(Timestamp,""); sub(/\n\n/,"")
}
/(subtitle[sd]? )?(precisely )?((re)?sync(ed|hronized)?|translation( and review)?|encoded|improved|provided|edited|production|created|extracted)( (&|and) correct(ed|ions))?( by|:) .*<\/font|opensubtitles|subscene|subtext:|purevpn|english (subtitles|- sdh)|trailers\.to/ {
  gsub(/\n/,"<br/>")
  MSGEXT=MSGEXT"Removing entry " (Entry - indexdelta)": " escape_html($0) "<br/>"
  indexdelta -= 1
  next
}
{
  if (Entry && Timestamp) {
    Newentry[++Entries] = Entry "\n" Timestamp "\n" $0
    Entry=""
    Timestamp=""
  } else {
    MSGEXT=MSGEXT"Skipping malformed entry " NR". Entry: " Entry,Timestamp,escape_html($0) "<br/>"
  }
}
END {
  if (NR == Entries) {
    MSGMAIN=MSGMAIN"No changes to subtitle file required. Total entries scanned: " NR
    printf MSGMAIN"|"MSGEXT
    exit 1
  }
  MSGMAIN=MSGMAIN"Original entries: " NR ". Total entries kept: " Entries
  MSGEXT=MSGEXT"Writing new temporary file: "TempSub""
  printf MSGMAIN"|"MSGEXT
  for (i = 1; i <= Entries; i++)
    print Newentry[i] "\n" >> TempSub
  close(TempSub)
}'

RC="${PIPESTATUS[2]}"  # captures awk exit status

if [ $RC == "0" ]; then
  # Check for script completion and non-empty file
  if [ -s "$TEMPSUB" ]; then
    mv "$TEMPSUB" "$SUB"
    MSG="<br/>Subtitle cleaned: $SUB"
    echo -n "$MSG"
  else
    MSG="<br/>ERROR: Script failed. Unable to locate or invalid file: \"$TEMPSUB\""
    echo -n "$MSG"
   exit 10
  fi
fi
