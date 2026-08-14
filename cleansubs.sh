#!/bin/bash

# Script to remove common annoying scene branding and attribution from subtitle files
#  https://github.com/TheCaptain989/bazarr-cleansubs
# Works on properly formatted SRT files.
# RegEx is English only.
# 
# Most output is designed to be compatible with the Bazarr log file format
# Removed subtitle entries are included after the pipe symbol (|) and included in the Bazarr "Exception" details of each log entry

# NOTE: ShellCheck linter directives appear as comments

# Dependencies:
#  awk
#  dos2unix
#  stat
#  basename
#  dirname
#  printenv
#  mktemp

# Exit codes:
#  0 - success
#  1 - no subtitle file specified on command line
#  2 - log file is not writable
#  4 - required binary not found
#  5 - subtitle file not found
#  6 - unknown subtitle file type
# 10 - awk script failed to write temporary subtitle file
# 11 - awk script failed in an unknown way
# 20 - general error

### Global variables
function initialize_variables {
  # Initialize variables
  
  export cleansubs_script=$(basename "$0")
  export cleansubs_ver="1.5.0"
  export cleansubs_pid=$$
  export cleansubs_log=/config/log/cleansubs.log
  export cleansubs_maxlogsize=512000
  export cleansubs_maxlog=2
  export cleansubs_debug=0
  export cleansubs_multiline=0
}

### Functions
function main {
  # Main script execution

  initialize_variables
  pre_process_command_line "$@"
  init_log
  check_for_bazarr
  process_command_line "$@"
  check_required_binaries
  log_first_debug_messages "$@"
  check_subtitle
  clean_subtitle
  replace_original_subtitle
}
function usage {
  # Short usage

  usage="Try '$cleansubs_script --help' for more information."
  echo "$usage" >&2
}
function long_usage {
  # Long usage

  usage="$cleansubs_script   Version: $cleansubs_ver
Subtitle processing script designed for use with Bazarr

Source: https://github.com/TheCaptain989/bazarr-cleansubs

Usage:
  $0 {-f|--file} <subtitle_file> [{-l|--log} <log_file>] [{-d|--debug} [<level>]]

Options and Arguments:
  -f, --file <subtitle_file>       Subtitle file in SRT format
                                   In Bazarr, this is normally set to
                                   \"{{subtitles}}\"
  -l, --log <log_file>             Log filename
                                   [default: /config/log/cleansubs.log]
  -d, --debug [<level>]            Enable debug logging
                                   level is optional, between 1-3
                                   1 is lowest, 3 is highest
                                   [default: 1]
      --help                       Display this help and exit
      --version                    Display script version and exit

Example:
  $cleansubs_script -f \"{{subtitles}}\" ;                                    # As used in Bazarr
  $cleansubs_script -f \"/video/The Muppet Show 02x13 - Zero Mostel.en.srt\"  # When used standalone on the command line
"
  echo "$usage"
}
function pre_process_command_line {
  # Pre-process the command line, handling only the options that must be resolved
  # before logging begins. The remaining arguments are returned in cleansubs_args, which
  # process_command_line restores with: eval set -- "$cleansubs_args"

  local pos_params
  while (( "$#" )); do
    case "$1" in
      -l|--log)
        # Log file
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
          export cleansubs_log="$2"
          shift 2
        else
          echo "Error: Invalid option: $1 requires an argument." >&2
          usage
          exit 1
        fi
      ;;
      --help)
        # Display full usage
        long_usage
        exit 0
      ;;
      --version)
        # Display version
        echo "$cleansubs_script $cleansubs_ver"
        exit 0
      ;;
      *)
        # Preserve every other argument for process_command_line
        # This quoting and printf/sed fixes all special shell characters in files names
        pos_params="$pos_params '$(printf %s "$1" | sed "s/'/'\\\\''/g")'"
        shift
      ;;
    esac
  done
  export cleansubs_args="$pos_params"
}
function process_command_line {
  # Process arguments, either from the command line or from the environment variable
  # The log, help, and version options are handled earlier, by pre_process_command_line

  # Restore the command line, minus the options already consumed
  eval set -- "$cleansubs_args"

  # Process arguments
  # Taken from Drew Stokes post 3/24/2015:
  #  https://medium.com/@Drew_Stokes/bash-argument-parsing-54f3b81a6a8f
  local pos_params
  while (( "$#" )); do
    case "$1" in
      -d|--debug )
        # Enable debugging, with optional level
        if [ -n "$2" ] && [ ${2:0:1} != "-" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
          export cleansubs_debug=$2
          shift 2
        else
          export cleansubs_debug=1
          shift
        fi
      ;;
      -f|--file )
        # Subtitle file
        if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
          export cleansubs_file="$2"
          shift 2
        else
          local message="Invalid option: $1 requires an argument."
          echo "Error|$message" | log
          echo "Error: $message" >&2
          usage
          exit 1
        fi
      ;;
      -*)
        # Unknown option
        local message="Unknown option: $1"
        echo "Error|$message" | log
        echo "Error: $message" >&2
        usage
        exit 20
      ;;
      *)
        # Preserve positional arguments
        # This quoting and printf/sed fixes all special shell characters in files names
        local pos_params="$pos_params '$(printf %s "$1" | sed "s/'/'\\\\''/g")'"
        shift
      ;;
    esac
  done
  # Set positional arguments in their proper place
  eval set -- "$pos_params"

  # Check for and assign positional arguments. Named override positional.
  if [ -n "$1" ]; then
    if [ -n "$cleansubs_file" ]; then
      local message="Both positional and named arguments set for subtitle file. Using $cleansubs_file"
      echo "Warning|$message" | log
      echo "Warning: $message" >&2
    else
      [ $cleansubs_debug -ge 1 ] && echo "Debug|Using positional argument for subtitle file: $1" | log
      export cleansubs_file="$1"
    fi
  fi
}
function log {(
  # Write piped message to log file
  # Can still go over cleansubs_maxlog if read line is too long
  # Must include whole function in subshell for read to work!
  
  while read -r; do
    # shellcheck disable=2046
    echo $(date +"%Y-%m-%d %H:%M:%S.%1N")"|[$cleansubs_pid]$REPLY" >>"$cleansubs_log"
    local cleansubs_filesize=$(stat -c %s "$cleansubs_log")
    if [ $cleansubs_filesize -gt $cleansubs_maxlogsize ]; then
      for i in $(seq $((cleansubs_maxlog-1)) -1 0); do
        [ -f "${cleansubs_log::-4}.$i.log" ] && mv "${cleansubs_log::-4}."{$i,$((i+1))}".log"
      done
      [ -f "${cleansubs_log::-4}.log" ] && mv "${cleansubs_log::-4}.log" "${cleansubs_log::-4}.0.log"
      touch "$cleansubs_log"
    fi
  done
)}
function end_script {
  # Exit program
  
  # Cool bash feature
  local message="Info|Completed in $((SECONDS/60))m $((SECONDS%60))s"
  echo "$message" | log
  [ "$1" != "" ] && export cleansubs_exitstatus=$1
  [ $cleansubs_debug -ge 1 ] && echo "Debug|Exit code ${cleansubs_exitstatus:-0}" | log
  exit ${cleansubs_exitstatus:-0}
}
function change_exit_status {
  # Set exit status code, but only if it is not already set

  local exit_status="$1" # Exit status code to set
  if [ -z "$cleansubs_exitstatus" ]; then
    export cleansubs_exitstatus="$exit_status"
  fi
}
function init_log {
  # Log file initialization

  # Check that log path exists
  if [ ! -d "$(dirname "$cleansubs_log")" ]; then
    [ $cleansubs_debug -ge 1 ] && echo "Debug: Log file path does not exist: '$(dirname "$cleansubs_log")'. Using log file in current directory."
    export cleansubs_log=./cleansubs.txt
  fi

  # Check that the log file exists
  if [ ! -f "$cleansubs_log" ]; then
    echo "Info: Creating a new log file: $cleansubs_log"
    touch "$cleansubs_log"
  fi

  # Check that the log file is writable
  if [ ! -w "$cleansubs_log" ]; then
    echo "Error: Log file '$cleansubs_log' is not writable or does not exist." >&2
    export cleansubs_log=/dev/null
    change_exit_status 2
  fi
}
function check_required_binaries {
  # Check for required binaries

  for cleansubs_needed_file in "/usr/bin/dos2unix" "/usr/bin/awk"; do
    if [ ! -f "$cleansubs_needed_file" ]; then
      local message="$cleansubs_needed_file is required by this script"
      echo "Error|$message" | log
      echo "Error: $message" >&2
      end_script 4
    fi
  done
}
function log_first_debug_messages {
  # First log messages
  # The original, unprocessed command line is passed in as the arguments

  if [ $cleansubs_debug -ge 1 ]; then
    # Log Debug state
    local message="Running ${cleansubs_script} version ${cleansubs_ver} with debug logging level ${cleansubs_debug}. Subtitle file: $cleansubs_file"
    echo "Debug|$message" | log
    echo "Debug: $message"

    # Log command line parameters
    [ $# -ne 0 ] && echo "Debug|Command line arguments are '$*'" | log
  fi

  # Log environment
  [ $cleansubs_debug -ge 2 ] && printenv | sort | sed 's/^/Debug|/' | log
}
function check_for_bazarr {
  # Log when not called from Bazarr

  if [ -z "$BAZARR_VERSION" ]; then
    [ $cleansubs_debug -ge 1 ] && echo "Debug|Not called from Bazarr. Using multiline output." | log
    export cleansubs_multiline=1
  fi
}
function check_subtitle {
  # Subtitle file checks

  # Check if subtitle file variable is blank
  if [ -z "$cleansubs_file" ]; then
    local message="No subtitle file specified! -f option not specified on command line."
    echo "Error|$message" | log
    echo "Error: $message" >&2
    usage 
    end_script 1
  fi

  # Check if source subtitle exists
  if [ ! -f "$cleansubs_file" ]; then
    local message="Input file not found: \"$cleansubs_file\""
    echo "Error|$message" | log
    echo "Error: $message" >&2
    usage
    end_script 5
  fi

  # Check if subtitle is in the expected format
  # This script only works on SRT subtitles
  if [[ "$cleansubs_file" != *.srt ]]; then
    local message="Expected SRT file. Incorrect file suffix: \"$cleansubs_file\""
    echo "Error|$message" | log
    echo "Error: $message" >&2
    usage
    end_script 6
  fi

  # Create temporary filename
  local basename="$(basename -- "${cleansubs_file}")"
  local fileroot="${basename%.*}"
  export cleansubs_tempsub="$(dirname -- "${cleansubs_file}")/$(mktemp -u -- "${fileroot:0:5}.tmp.XXXXXX")"
  [ $cleansubs_debug -ge 1 ] && echo "Debug|Using temporary file \"$cleansubs_tempsub\"" | log
}
function clean_subtitle {
  # Main subtitle cleaning function

  # shellcheck disable=SC2002
  cat "$cleansubs_file" | dos2unix | awk -v Debug=$cleansubs_debug \
  -v SubTitle="$cleansubs_file" \
  -v TempSub="$cleansubs_tempsub" \
  -v MultiLine=$cleansubs_multiline '
  function escape_html(str){
    # escape HTML in subs
    # This was needed in older versions of Bazarr that did not escape log entries.
    # It is not used currently, but leaving here for posterity.
    gsub(/&/, "\\&amp;", str); gsub(/</, "\\&lt;", str); gsub(/>/, "\\&gt;", str); gsub(/"/, "\\&quot;", str)
    return str
  }
  BEGIN {
    RS = ""     # one or more blank lines
    FS = "\n"
    IGNORECASE = 1
    # Adds line feed to output when not called from Bazarr
    if (MultiLine == 1) NL = "\n"
    # This is required because BusyBox awk will not honor shell exported functions, so piping fails.
    writelog = "while read -r; do echo $(date +\"%Y-%m-%d %H:%M:%S.%1N\")\"|[$cleansubs_pid]$REPLY\" >>\"$cleansubs_log\"; done"
    # Start a new log entry
    print "Info|Starting run for subtitle file: " SubTitle | writelog
    MSGMAIN = "cleansubs.sh: Subtitle file: " SubTitle "; "
    indexdelta = 0
  }
  # Check for Byte Order Mark
  $1 ~ /^\xef\xbb\xbf/ {
    # Remove BOM from UTF-8 encoded file
    if (Debug >= 1) print "Debug|Removing BOM from UTF-8 encoded file." | writelog
    if (NR == 1) { sub(/^\xef\xbb\xbf/, "") }
  }
  # Get entry number
  $1 ~ /^[0-9]+$/ {
    Entry = $1
    sub(Entry, "")
    Entry = Entry + indexdelta
  }
  # Get timestamp
  $2 ~ /^[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}[,.][0-9]{1,3} --> [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}[,.][0-9]{1,3}$/ {
    Timestamp = $2
    sub(Timestamp, ""); sub(/\n\n/, "")
  }
  # Match on objectionable strings
  /^(subtitle[sd] )?(precisely )?((re)?sync(ed|hronized)?|encoded|improved|production|extracted|correct(ed|ions)|subtitle[sd]|downloaded|conformed)( (&|and) correct(ed|ions))?( by|from|:) |Captioning made possible by|captioning performed by|performance of captions|opensubtitles|subscene|subtext:|purevpn|english (subtitles|(- )?sdh)|trailers\.to|osdb\.link|thepiratebay\.|explosiveskull|gioni666|twitter\.com|flixify|YTS\.MX|saveanilluminati\.com|isubdb\.com|ADMITME\.APP|addic7ed\.com|sumnix|crazykyootie|mstoll|DivX|TLF subTeam|openloadflix\.com|blogspot\.com|visiontext|movieddl\.me|allsubs\.org|YT[SX](-MOVIE)?\.(COM|MX)|subtitrari\.pro|sab\.bz|cenflix\.co/ {
    # This was needed in older versions of Bazarr that did not escape log entries. 
    # gsub(/\n/, "<br/>")
    print "Info|Removing entry " (Entry - indexdelta) ": (" Timestamp ") " gensub(/\n/, "<br/>", "g", $0) | writelog
    MSGEXT = MSGEXT "Removing entry " (Entry - indexdelta) ": " $0 "\\n" NL
    indexdelta -= 1
    next
  }
  # Do this for every line
  {
    if (Entry && Timestamp) {
      # Generate a newly renumbered entry
      Newentry[++Entries] = Entry "\n" Timestamp "\n" $0
      Entry = ""
      Timestamp = ""
    } else {
      # Add to Bazarr Exception log
      print "Info|Skipping malformed entry " NR ": " gensub(/\n/, "<br/>", "g", $0) | writelog
      MSGEXT = MSGEXT "Skipping malformed entry " NR ": " $0 "\\n" NL
    }
  }
  END {
    if (NR == Entries) {
      # No changes to file
      print "Info|No changes to subtitle file required. Total entries scanned: " NR | writelog
      MSGMAIN = MSGMAIN "No changes to subtitle file required. Total entries scanned: " NR NL
      printf "%s", MSGMAIN
      exit 1
    }
    # Write new subtitle file
    print "Info|Original entries: " NR ". Total entries kept: " Entries | writelog
    if (Debug >= 1) print "Debug|Writing new temporary file: " TempSub | writelog
    MSGMAIN = MSGMAIN "Original entries: " NR ". Total entries kept: " Entries
    printf "%s", MSGMAIN "|" MSGEXT
    for (i = 1; i <= Entries; i++)
      print Newentry[i] "\n" >> TempSub
    close(TempSub)
  }'

  local return="${PIPESTATUS[2]}"  # captures awk exit status
  [ $cleansubs_debug -ge 2 ] && echo "Debug|awk exited with code: $return" | log

  # No changes to subtitle file needed.  Do nothing.
  if [ $return -eq 1 ]; then
    :
    end_script
  fi

  # awk script failed in an unknown way
  if [ $return -ne 0 ]; then
    local message="Script encountered an unknown error processing subtitle: $cleansubs_file"
    echo "Error|$message" | log
    echo "Error: $message" >&2
    end_script 11
  fi

  # Check for non-empty file
  if [ ! -s "$cleansubs_tempsub" ]; then
    local message="Unable to locate or invalid cleaned file: $cleansubs_tempsub"
    echo "Error|$message" | log
    echo "Error: $message" >&2
    end_script 10
  fi
}
function replace_original_subtitle {
  # Overwrite the original subtitle file with the new file

  local result
  [ $cleansubs_debug -ge 1 ] && echo "Debug|Renaming \"$cleansubs_tempsub\" to \"$cleansubs_file\"" | log
  result=$(mv -f "$cleansubs_tempsub" "$cleansubs_file")
  local return=$?; [ $return -ne 0 ] && {
    local message=$(echo -e "[$return] Unable to rename temp subtitle: \"$cleansubs_tempsub\" to: \"$cleansubs_file\".  Halting.\nmv returned: $result" | awk '{print "Error|"$0}')
    echo "$message" | log
    echo "$message" >&2
    end_script 6
  }
}
### End Functions

# Do not execute if this script is being sourced from a test script
if [[ ! "${BASH_SOURCE[1]}" =~ test_.*\.sh$ ]]; then
  main "$@"
  end_script
fi
