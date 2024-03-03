# Media Extractor

The `media_extractor.bash` script is designed for post-processing tasks, specifically the extraction of RAR files and validation of the extracted content. It supports working natively with Transmission post-processing but can be utilized for any other task or post-processing by providing two required arguments: `TORRENT_DIR` and `TORRENT_NAME`. Alternatively, if the environment variables `TR_TORRENT_DIR` and `TR_TORRENT_NAME` are set, no arguments are required, and the script will read the variables.

## Features

- Extraction of RAR files
- Validation of extracted content
- Native support for Transmission post-processing
- Default console logging with the option to output to file

## Usage

### Requirements
- Bash environment
- RAR files for extraction

### Installation

#### Option 1: Docker Setup
All steps are completed on the docker host. These steps add the script to the bind mount directory linked between the host and docker container. The script will live on the docker host but execute from the Transmission container.

1. Copy the `media_extractor.bash` into the directory you used for the bind mount (`/path/to/data:/config`).
2. Set the correct permissions on the script: `chmod +x media_extractor.bash`
3. Edit your `settings.json` file and update the "script-torrent-done-*" options.
   - `"script-torrent-done-enabled": true,`
   - `"script-torrent-done-filename": "/config/media_extractor.bash",`
4. Restart Transmission if it is running.

#### Option 2: Traditional Command Line
1. Download the `media_extractor.bash` script.
2. Set the correct permissions on the script: `chmod +x media_extractor.bash`
3. Run the script with the required arguments:
   ```bash
   bash media_extractor.bash "/etc/my_torrent_dir" "torrent_folder_name"
   ```

### Configuration
The script has several configuration options, and the default settings are as follows:

```bash
ENABLE_FILE_LOGGING=false
RECHECK_EXISTING_RAW=true
TEMP_EXTRACTION_DIRECTORY=""
FILE_EXTENSIONS=("mkv" "mp4" "mp3" "exe" "flac")
```
- ENABLE_FILE_LOGGING: Sets file logging. By default, it is set to false. If set to true, file logging will be enabled.
- RECHECK_EXISTING_RAW: Enables rechecking a RAR that has existing RAW files. By default, it is set to true.
- TEMP_EXTRACTION_DIRECTORY: Sets temporary extraction directory. By default, the archive file directory is used. Ideal for applications that can break the default extraction file path.
- FILE_EXTENSIONS: This variable is used to specify which file extensions need to be validated after extraction. By default, these are pre-set:
  ```bash
  FILE_EXTENSIONS=("mkv" "mp4" "mp3" "exe" "flac")
  ```
Any additional file extensions needed can be added to this variable. The script will extract any RAR file regardless of the FILE_EXTENSIONS, but the validation will throw an error suggesting "Manual validation is required."

### Logging
The script has file logging built-in but is disabled by default because logging may not be possible due to permissions if run inside a docker. Console output will always be sent, so if this is run in docker, the output would return to the host to be viewed by a monitoring agent such as Portainer or Grafana Loki.

### Additional Details
- Extracted media files will be extracted into the RAR file's root folder.
- The log file auto-clears at 1 Megabyte.

## Contributing
Contributions are welcome! Feel free to submit issues or pull requests to enhance and improve this Bash script.

## License
This project is licensed under the MIT License - see the LICENSE file for details.