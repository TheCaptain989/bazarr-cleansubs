# About
A shell script to automatically remove common annoying scene branding and attribution entries from subtitle files.
Only .SRT format subtitles are supported.

# Installation
1. Place the `cleansubs.sh` shell script file in the root directory of Bazarr, usually `/config`
2. Configure a custom script from the Bazarr *Settings* > *Subtitles* screen by typing the following in the **Post-processing command** field (Note the double quotes!):  
   **`/config/cleansubs.sh "{{subtitles}}" ;`**  

   *Example*  
   ![cleansubs](.assets/bazarr-settings-subtitles.png "Bazarr subtitles settings")


   >**NOTE:** The original subtitle file will be deleted/overwritten and permanently lost.

## Usage Details
The script is not configurable.  
The string matching only supports English at this time.

### Syntax
The syntax for the command-line is:  
`cleansubs.sh <subtitle_file>`

Where:

Argument|Description
---|---
<subtitle_file>|The full path and file name to a subtitle file. In Bazarr, you should use the `{{subtitles}}` variable.

### Logs
Logs are integrated into the Bazarr log file. The text output of the script is designed to be compatible with the Bazarr log file format. This has been tested with Bazarr version(s):
- v0.8.2.4 - v1.3.0

*Example log entry with no changes*  
![normal log](.assets/bazarr-log1.png "Bazarr log entry")

*Example log entry post cleaning*  
![cleaned subtitle log](.assets/bazarr-log2.png "Bazarr log entry")

Removed subtitle entries are included in the Bazarr "Exception" details of each log entry.  
![cleaned subtitle log detail](.assets/bazarr-log2-detail.png "Bazarr log traceback")

___

# Credits

This would not be possible without the following:

[Bazarr](https://www.bazarr.media/ "Bazarr homepage")  
[LinuxServer.io Bazarr](https://hub.docker.com/r/linuxserver/bazarr "Bazarr Docker container") container
