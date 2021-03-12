# About
A shell script to automatically remove common annoying scene branding and attribution entries from subtitle files.
Only .SRT format subtitles are supported.

# Installation
1. Place the `cleansubs.sh` shell script file in the root directory of Bazarr, usually `/config`
2. Configure a custom script from the Bazarr *Settings* > *Subtitles* screen to call:

   **`/config/cleansubs.sh "{{subtitles}}" ;`**

   from the **Post-processing command** field.  **Note the double quotes!**

   *Example*  
   ![cleansubs](.assets/bazarr-settings-subtitles.png)


   >**NOTE:** The original subtitle file will be deleted/overwritten and permanently lost.

## Usage
The script is not configurable.  
The string matching only supports English at this time.

### Syntax
The script accepts one argument:

`<subtitle_file>`

The argument is the full path and file name to a subtitle file. In Bazarr, you should use the `{{subtitles}}` variable.

### Logs
Logs are integrated into the Bazarr log file. The text output of the script is designed to be compatible with the Bazarr log file format. This has been tested with Bazarr version(s):
* v0.8.2.4 - v0.9.3

*Example log entry with no changes*  
![normal log](.assets/bazarr-log1.png)

*Example log entry post cleaning*  
![cleaned subtitle log](.assets/bazarr-log2.png)

Removed subtitle entries are included in the Bazarr "Exception" details of each log entry.  
![cleaned subtitle log detail](.assets/bazarr-log2-detail.png)

___
# Credits

This would not be possible without the following:

[Bazarr](https://www.bazarr.media/)  
[LinuxServer.io Bazarr](https://hub.docker.com/r/linuxserver/bazarr) container
