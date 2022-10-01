#!/bin/bash

# Script to remove common annoying scene branding and attribution from subtitle files
#  https://github.com/TheCaptain989/bazarr-cleansubs
# Works on properly formatted SRT files.
# RegEx is English only.
# 
# Most output is designed to be compatible with the Bazarr log file format
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
# 11 - awk script failed in an unknown way

### Variables
export cleansubs_script=$(basename "$0")
export cleansubs_tempsub="$1.tmp"
export cleansubs_sub="$1"

# Parking here for future use.
#RECYCLEBIN=$(python3 -c "import sqlite3
#conSql = sqlite3.connect('/config/db/bazarr.db')
#cursorObj = conSql.cursor()
#cursorObj.execute('SELECT Value from Config WHERE Key=\"recyclebin\"')
#print(cursorObj.fetchone()[0])
#conSql.close()")

### Functions
function usage {
  usage="
$cleansubs_script
Subtitle processing script designed for use with Bazarr

Source: https://github.com/TheCaptain989/bazarr-cleansubs

Usage:
  $0 <subtitle>

Options:
  <subtitle>     subtitle file in SRT format

Example:
  $cleansubs_script \"/video/The Muppet Show 02x13 - Zero Mostel.en.srt\"     # When used standalone on the command line
  $cleansubs_script \"{{subtitles}}\" ;                                       # As used in Bazarr
"
  >&2 echo "$usage"
}

# Check for required command line argument
if [ -z "$cleansubs_sub" ]; then
  MSG="\nERROR: No subtitle file specified! Not called from Bazarr?"
  echo -n "$MSG"
  usage
  exit 1
fi

# Check for existence of subtitle file
if [ ! -f "$cleansubs_sub" ]; then
  MSG="\nERROR: Input file not found: \"$cleansubs_sub\""
  echo -n "$MSG"
  usage
  exit 5
fi

# Check if subtitle is in the expected format
if [[ "$cleansubs_sub" != *.srt ]]; then
  # This script only works on SRT subtitles
  MSG="\nERROR: Expected SRT file. Incorrect file suffix: \"$cleansubs_sub\""
  echo -n "$MSG"
  usage
  exit 6
fi

# Generate temporary file name
until [ ! -s "$cleansubs_tempsub" ]; do
  # Temporary file already exists
  i=$((i+1))
  cleansubs_tempsub="${cleansubs_tempsub%%.*}.srt.$i.tmp"
done

#### BEGIN MAIN
cat "$cleansubs_sub" | dos2unix | awk -v SubTitle="$cleansubs_sub" \
-v TempSub="$cleansubs_tempsub" '
function escape_html(str){
  # escape HTML in subs
  gsub(/&/,"\\&amp;",str);gsub(/</,"\\&lt;",str);gsub(/>/,"\\&gt;",str);gsub(/"/,"\\&quot;",str)
  return str
}
BEGIN {
  RS=""     # one or more blank lines
  FS="\n"
  IGNORECASE=1
  # Start a new log entry
  MSGMAIN="cleansubs.sh: Subtitle file: " SubTitle "; "
  indexdelta=0
}
# Check for Byte Order Mark
$1 ~ /^\xef\xbb\xbf/ {
  # Remove BOM from UTF-8 encoded file
  if (NR == 1) { sub(/^\xef\xbb\xbf/,"") }
}
# Get entry number
$1 ~ /^[0-9]+$/ {
  Entry=$1
  sub(Entry,"")
  Entry = Entry + indexdelta
}
# Get timestamp
$2 ~ /^[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2},[0-9]{1,3} --> [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2},[0-9]{1,3}$/ {
  Timestamp=$2
  sub(Timestamp,""); sub(/\n\n/,"")
}
# Match on objectionable strings
/(subtitle[sd]? )?(precisely )?((re)?sync(ed|hronized)?|encoded|improved|production|extracted)( (&|and) correct(ed|ions))?( by|:) |opensubtitles|subscene|subtext:|purevpn|english (subtitles|- sdh)|trailers\.to|osdb\.link|thepiratebay\.|explosiveskull|twitter\.com|flixify|YTS\.ME|saveanilluminati\.com|isubdb\.com|ADMITME\.APP|addic7ed\.com|sumnix|crazykyootie/ {
  # gsub(/\n/,"<br/>")
  MSGEXT=MSGEXT"Removing entry " (Entry - indexdelta)": " $0 "\\n"
  indexdelta -= 1
  next
}
# Do this for every line
{
  if (Entry && Timestamp) {
    # Generate a newly renumbered entry
    Newentry[++Entries] = Entry "\n" Timestamp "\n" $0
    Entry=""
    Timestamp=""
  } else {
    # Add to Bazarr Exception log
    MSGEXT=MSGEXT "Skipping malformed entry " NR ". Entry: " Entry","Timestamp","$0 "\\n"
  }
}
END {
  if (NR == Entries) {
    # No changes to file
    MSGMAIN=MSGMAIN "No changes to subtitle file required. Total entries scanned: " NR
    printf MSGMAIN
    exit 1
  }
  # Write new subtitle file
  MSGMAIN=MSGMAIN "Original entries: " NR ". Total entries kept: " Entries
  MSGEXT=MSGEXT "Writing new temporary file: " TempSub ""
  printf MSGMAIN "|" MSGEXT
  for (i = 1; i <= Entries; i++)
    print Newentry[i] "\n" >> TempSub
  close(TempSub)
}'

#### END MAIN

RC="${PIPESTATUS[2]}"  # captures awk exit status

if [ $RC == "0" ]; then
  # Check for script completion and non-empty file
  if [ -s "$cleansubs_tempsub" ]; then
    mv "$cleansubs_tempsub" "$cleansubs_sub"
    MSG="\nSubtitle cleaned: $cleansubs_sub"
    echo -n "$MSG"
    exit 0
  else
    MSG="\nERROR: Script failed. Unable to locate or invalid file: \"$cleansubs_tempsub\""
    echo -n "$MSG"
   exit 10
  fi
elif [ $RC == "1" ]; then
  # No changes to subtitle file needed.  Do nothing.
  :
  exit 0
else
  # awk script failed in an unknown way
  MSG="\nERROR: Script encountered an unknown error processing subtitle: $cleansubs_sub"
  echo -n "$MSG"
  exit 11
fi
