# Bazarr cleansubs
A shell script to automatically remove common annoying scene branding and attribution entries from subtitle files.
Only .SRT format subtitles are supported.

## Usage

1. Place the `cleansubs.sh` shell script file in the root directory of Bazarr
2. Configure a custom script from the Bazarr Settings->Subtitles screen to call:

   **`/config/cleansubs.sh "{{subtitles}}" ;`**

   from the **Post-processing command** field.  **Note the double quotes!**

**NOTE:** The original subtitle file will be deleted/overwritten and permanently lost.

### Syntax

The script accepts one argument:

`<subtitle_file>`

The argument is the full path and file name to a subtitle file.

![cleansubs](.assets/bazarr-settings-subtitles.png)

### Logs
Logs are integrated into the Bazarr log file. The text output of the script is designed to be compatible with the Bazarr log file format. This has been tested with Bazarr version(s):
* v0.8.2.4 - v0.9.0.5

*Example log entry with no changes*  
![normal log](.assets/bazarr-log1.png)

*Example log entry post cleaning*  
![cleaned subtitle log](.assets/bazarr-log2.png)

Removed subtitle entries are included in the Bazarr "Exception" details of each log entry.  
![cleaned subtitle log detail](.assets/bazarr-log2-detail.png)

___
# Credits

[Bazarr](https://www.bazarr.media/)  
[LinuxServer.io Bazarr](https://hub.docker.com/r/linuxserver/bazarr) container
