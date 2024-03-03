#!/bin/bash

# ############################################
# ###############Global Variables#############
# ############################################
# Sets file logging
ENABLE_FILE_LOGGING=false
# Enables rechecking a RAR that has existing RAW files
RECHECK_EXISTING_RAW=true
# Optional temporary extraction directory
# Leave empty to extract to the archive file directory
TEMP_EXTRACTION_DIRECTORY=""
# Add or remove extensions as needed
FILE_EXTENSIONS=("mkv" "mp4" "mp3" "exe" "flac")
# ############################################

# ############################################
# ################Short Usage Notes###########
# ############################################
# 1. Some post-processing programs require this file to have the correct permissions.
#     - chmod +x media_extractor.bash
# 2. This script supports passing arguments and the default Transmission variables.
#     - Argument Example: bash media_extractor.bash "/etc/my_torrent_dir" "torrent_folder_name"
#     - Transmission Example: bash media_extractor.bash
#       - Supported Environment Variables:
#         - TORRENT_DIR
#         - TORRENT_NAME
# ############################################
# ############################################

# Function to set file logging
function set_logging() {
  # Gets the current directory for the script.
  # This works for aliases, source, bash-c, symbolic links, etc.
  source="${bash_source[0]}"
  # Loops source
  while [ -h "$source" ]; do
    # Gets DIR and hides output
    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    # Gets source
    source="$(readlink "$source")"
    # If the source is a symlink, this will set the path to where the symlink file is located
    [[ $source != /* ]] && source="$dir/$source"
  done
  # Sets script directory
  scriptDIR="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"

  # Sets log path
  # Script dir is used by default
  # This is needed when using bind mounts with docker
  logFile="$scriptDIR/media_extractor.log"

  # Log cleanup in case it gets too big
  # Sets the minimum log size in bytes
  # Setting to 1 Megabyte
  minimumLogSize=1000000
  # Checks if the log file exists
  if test -f "$logFile"; then
    # Gets actual log file size
    actualLogSize=$(wc -c <"$logFile")
    if [ "$actualLogSize" -ge $minimumLogSize ]; then
      # Clears log file
      truncate -s 0 "$logFile"
    fi
  fi
}

# Function to output print messages and/or logging
function notification() {
  local log_message="$1"
  local log_console=${2:-false}

  if [[ "$ENABLE_FILE_LOGGING" == true && "$log_console" != true ]]; then
    printf "$log_message" | (tee -a "${logFile}")
  elif [[ "$ENABLE_FILE_LOGGING" == true && "$log_console" == true ]]; then
    printf "$log_message" >> "${logFile}"
  elif [[ "$ENABLE_FILE_LOGGING" == false && "$log_console" != true ]]; then
    printf "$log_message"
  fi
}

function handle_error() {
  local error_message="$1"
  notification "%s\n$(date)|Error|$error_message"
  # Blank line
  echo ""
  # Pauses for 3 seconds before exit to allow writes to console
  sleep 3
  exit
}

# Function to find files with specific extensions
function find_files() {
    local directory="$1"
    local extensions=("$2")

    # Find files with specified extensions
    find "$directory" -type f -iname "*.${extensions[0]}" -o \
                         -iname "*.${extensions[1]}" -o \
                         -iname "*.${extensions[2]}" -o \
                         -iname "*.${extensions[3]}"
}

# Function to get all raw file paths
function get_raw_file_paths() {
  local torrent_path="$1"

  # Finds all raw files based on approved extensions
  raw_list=()
  for extension in "${FILE_EXTENSIONS[@]}"; do
    files=$(find_files "$torrent_path" "$extension")
    raw_list+=("$files")
  done

  media_raw_full_path_names=""
  # Required to remove empty elements and help clean up any trailing newlines
  for file in "${raw_list[@]}"; do
    # Skip empty elements
    [[ -n "$file" ]] && media_raw_full_path_names+="$file"$'\n'
  done
  # Convert raw files array to a string
  media_raw_full_path_names="${media_raw_full_path_names%$'\n'}"  # Remove trailing newline

  echo "${media_raw_full_path_names}"
}

# Function make string lowercase
function to_lower_case() {
  local string="$1"
  echo "${string,,}"  # Use parameter expansion to convert to lowercase
}

# Function to check if the raw file exists by itself or if the extraction was successful
function file_path_validation() {
  local media_raw_full_path_names="$1"
  local media_rar_full_path_names="$2"

  # Checks if the extractor was required. No RAR file means only the raw needs to be validated
  if [ -z "$media_rar_full_path_names" ]; then
    # Loops through each RAW file (1 or many)
    while IFS= read -r media_raw_full_path_name; do
      # Check if the file path exists
      if [[ -f "$media_raw_full_path_name" ]]; then
        notification "%s\n$(date)|Success|RAW file validation passed for: $(basename "$media_raw_full_path_name")"
      else
        if [ -z "$media_raw_full_path_names" ]; then
          notification "%s\n$(date)|Warning|RAW file validation could not be completed because approved validation extensions ($(IFS=,; echo "${FILE_EXTENSIONS[*]}")) found no matching files. Manual validation is required"
        else
          handle_error "RAW file validation failed for: $(basename "$media_raw_full_path_name"). Manual intervention is required"
        fi
      fi
    done <<<"$media_raw_full_path_names"
  else
    # Convert newline-separated lists to arrays
    # If spaces are in the file path they will stay together
    IFS=$'\n' read -d '' -ra media_raw_files <<< "$media_raw_full_path_names"
    IFS=$'\n' read -d '' -ra media_rar_files <<< "$media_rar_full_path_names"
    
    # Find matching and missing files
    matching_files=()
    missing_files=()
    approved_unrar_raw_file_names=()
    for rar_base_name in "${media_rar_files[@]}"; do
      # Pulls the original RAR file names out of the RAR with the file extension
      # 'awk' will remove extra blank spaces, so any file names with multiple blanks will need to be trimmed to a single blank space. The 'media_raw_file' below will need to be adjusted to only include single blanks
      orig_rar_info=$(unrar l "$rar_base_name" | awk '{
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && $(i+1) ~ /^[0-9]{2}:[0-9]{2}$/) {
            # Extract and print from the next field to the end of the line.
            for (j = i + 2; j <= NF; j++) {
              printf "%s ", $j
            }
            printf "\n"
          }
        }
      }')

      # Converts the RAR info to an array
      IFS=$'\n' read -r -d '' -a unrar_info_array <<< "$orig_rar_info"

      # Loop through each element in the array and extract the basename
      # Depending on the array the file path may contain part of a folder path
      for ((i = 0; i < ${#unrar_info_array[@]}; i++)); do
        file_name=$(basename "${unrar_info_array[$i]}")
        unrar_info_array[$i]=$(echo "$file_name" | sed 's/[[:space:]]*$//')
      done

      # Loop through the unrar_info_array
      # This is the information inside the RAR to use the file names for checks
      for file in "${unrar_info_array[@]}"; do
        # Extract the file extension without the leading dot
        unrar_listed_files_extension=$(basename "$file" | awk -F '.' '{print $NF}' | tr -d '[:space:]')

        # Removes the case from the raw file to match the rar that has the case removed
        lower_case_unrar_info_match_file=("$(to_lower_case "$(dirname "$rar_base_name")/$file")")
 
        # Check if the extension matches any extension in the FILE_EXTENSIONS array
        for approved_extraction_extension in "${FILE_EXTENSIONS[@]}"; do
          # Tracks if a raw file and file listed from the unrar file list matched or not
          match_found="false"

          # Only matches file extensions listed in the rar info and the global extension variable
          if [[ "$unrar_listed_files_extension" == "$approved_extraction_extension" ]]; then
            # Adds approved files in the unrar info that need to be tracked based on the matching extension
            approved_unrar_raw_file_names+=("$file")  # Append to the array

            # Loops through to add the original RAW file with the extension
            for media_raw_file in "${media_raw_files[@]}"; do
              # Removes the case from the raw file to match the rar that has the case removed and any extra banks in the name because of the awk unrar file name extraction removes any blank over 1 space
              # Note: If the awk is ever changed this will need to be adjusted so the 'if' below matches
              lower_case_media_raw_file_single_blanks=$(to_lower_case "$media_raw_file" | tr -s ' ')
              # Keeps the normal blanks, but lower cases because this output will be used for comparison
              lower_case_media_raw_file=("$(to_lower_case "$media_raw_file")")
              
              # Checks if the original matching rar file path is similar to a raw file
              # This is required to get the original file and extension for the file path test
              if [[ "$lower_case_media_raw_file_single_blanks" == "$lower_case_unrar_info_match_file" ]]; then
                # Adds the lower_case_media_raw_file because this contains the full path.
                matching_files+=("$lower_case_media_raw_file")
                match_found="true"
                break
              fi
            done

            # If no match the file should have exited, but it was not found
            if [ "$match_found" == "false" ]; then
              missing_files+=("$lower_case_unrar_info_match_file")
            fi
          fi
        done
       
      done
    done

    # Matching RAW
    for file in "${matching_files[@]}"; do
      # Checks if the file exists
      if [[ -f "$file" ]]; then
        notification "%s\n$(date)|Success|RAW file validation passed for: $(basename "$file")"
      else
        handle_error "RAW file validation failed for: $(basename "$file"). Manual intervention is required"
      fi
    done

    # If both entries are empty it means no file extensions matched
    if [[ ${#approved_unrar_raw_file_names[@]} -eq 0 && ${#matching_files[@]} -eq 0 ]]; then
      notification "%s\n$(date)|Warning|RAW file validation could not complete because approved validation extensions ($(IFS=,; echo "${FILE_EXTENSIONS[*]}")) do not match the extracted files ($(IFS=,; echo "${unrar_info_array[*]}")). Manual validation is required"
    else
      # Checks if the unrar RAR file info count does not match the raw files in the directory
      if [[ ${#approved_unrar_raw_file_names[@]} -ne ${#matching_files[@]} ]]; then
        # Get the number of files in each array
        approved_unrar_raw_file_names_count=${#approved_unrar_raw_file_names[@]}
        matching_files_count=${#matching_files[@]}

        # Calculate the difference in file counts
        count_missing_files=$(( approved_unrar_raw_file_names_count - matching_files_count ))

        # Using the notification function instead of the handle_error function to show the missing files before existing
        notification "%s\n$(date)|Error|Some RAW file(s) did not get extracted. Missing $count_missing_files out of $approved_unrar_raw_file_names_count. See below:"
        
        for file in "${missing_files[@]}"; do
          notification "%s\n$(date)|Error|RAW file validation failed for: $(basename "$file"). Manual intervention is required"
        done
      fi
    fi

  fi

  # Blank line before bulk output
  notification "%s\n"
}

# Function for RAR file extracting
function extract_torrent() {
  local torrent_dir="$1"
  local torrent_name="$2"
  local media_rar_full_path_names="$3"

  notification "%s\n$(date)|Info|Extraction is required for torrent: $torrent_name"
  notification "%s\n$(date)|Info|Media Directory = /$torrent_dir"
  if [ -n "$TEMP_EXTRACTION_DIRECTORY" ]; then
    notification "%s\n$(date)|Info|Temporary Extraction Directory = $TEMP_EXTRACTION_DIRECTORY"
  fi
  notification "%s\n$(date)|Info|RAR Files Needing Extracted = $(wc -l <<<"$media_rar_full_path_names")"

  line_number=0
  # Loops through each RAR file (1 or many)
  while IFS= read -r media_rar_full_path_name; do
    # Check if the file path exists
    if [[ -f "$media_rar_full_path_name" ]]; then
      line_number=$((line_number + 1))
      if [[ $line_number -ge 2 ]]; then
        notification "%s\n$(date)|Info|Processing $line_number of $(wc -l <<<"$media_rar_full_path_names")"
      else
        notification "%s\n$(date)|Info|Processing $line_number of $(wc -l <<<"$media_rar_full_path_names")"
      fi

      # Extract the RAR subdirectory directory path using dirname
      media_rar_subdirectory_path="$(dirname "$media_rar_full_path_name")"
      media_rar_last_subdirectory_name="$(basename "$media_rar_subdirectory_path")"
      # Extract the RAR file name.
      media_rar_filename="$(basename -a "$media_rar_full_path_name")"

      notification "%s\n$(date)|Info|Media RAR Full Path Discovered = $media_rar_full_path_name"
      notification "%s\n$(date)|Info|Media RAR Sub Directory Path= $media_rar_subdirectory_path"
      notification "%s\n$(date)|Info|Media RAR Last Sub Directory Name= $media_rar_last_subdirectory_name"
      notification "%s\n$(date)|Info|Media RAR File Name = $media_rar_filename"
      notification "%s\n$(date)|Info|Compressed Media Details Below"
      # Blank line before bulk output
      notification "%s\n"
      # Logs console and log
      notification "%s\n------------------------------------------------------------------------------------------------------------------------------"
      # Blank line
      echo ""

      # ################################################################################################################
      # FIFO is needed for unrar console/log file pipe. Needs defined peruse.
      # Some shells do not support process substitution with 'tee,' making sure the output gets put into the output stream.
      # FIFO is a special file that allows multiple reads/writes and passes data internally without writing to the filesystem, which will allow piped output to be shown.
      # Use Case: The transmission docker created by linux.io will not work with 'tee,' but this allows the output to work correctly.
      # ################################################################################################################
      fifo=$(mktemp -u)
      mkfifo "$fifo"
      cat "$fifo" &

      # Gets RAR file details
      # Two different 'tee' commands
      #   - 1st: tee $fifo allows output to the console when storing to a variable.
      compressed_file_details=$(unrar l "$media_rar_full_path_name" | tee "$fifo")
      
      # Sends console output for notifications to the log file.
      notification "$compressed_file_details" true

      # Blank line
      echo ""
      # Logs console and log
      notification "%s\n------------------------------------------------------------------------------------------------------------------------------"
      # Blank line
      notification "%s\n"

      # FIFO is needed for unrar console/log file pipe. Needs defined peruse.
      fifo=$(mktemp -u)
      mkfifo "$fifo"
      cat "$fifo" &

      # Logs console and log
      notification "$compressed_file_details" true
      notification "%s\n$(date)|Info|Starting Media Extraction For: $media_rar_last_subdirectory_name"
      notification "%s\n$(date)|Info|Please wait....."
      # Blank line before bulk output
      notification "%s\n"
      # Logs console and log
      notification "%s\n------------------------------------------------------------------------------------------------------------------------------"
      # Blank line
      notification "%s\n"
      
      # This section of code uses unrar to extract the media file.
      if [ -n "$TEMP_EXTRACTION_DIRECTORY" ]; then
        # Checks that the path is a directory
        if [ -d "$TEMP_EXTRACTION_DIRECTORY" ]; then
          # Verifies the user has permission to write
          if [ -w "$(dirname "$TEMP_EXTRACTION_DIRECTORY")" ]; then
            # Create the folder in TEMP_EXTRACTION_DIRECTORY
            mkdir -p "$TEMP_EXTRACTION_DIRECTORY/$media_rar_last_subdirectory_name"

            # Create the media_temp_subdirectory_path variable
            media_temp_subdirectory_path="$TEMP_EXTRACTION_DIRECTORY/$media_rar_last_subdirectory_name"

            # Validate that the path exists
            if [ -d "$media_temp_subdirectory_path" ]; then
              # Extract files to a temporary directory and capture output into the variable
              compressed_file_details=$(unrar e -r -o- "$media_rar_full_path_name" "$media_rar_subdirectory_path" -y "${media_temp_subdirectory_path}/" 2>&1 | tee "$fifo")

              # Move contents from media_temp_subdirectory_path to media_rar_subdirectory_path and apture stderr only
              move_file_error_output=$( { mv "$media_temp_subdirectory_path"/* "$media_rar_subdirectory_path/" 2>&1 >/dev/null; } )

              # Delete the temporary directory
              rm -rf "$media_temp_subdirectory_path"

              # Delete the temporary directory
              if ! rm -rf "$media_temp_subdirectory_path"; then
                compressed_file_details="Failed to delete temporary directory"
              fi
            else
                compressed_file_details="Temporary subdirectory extraction directory path is not valid"
            fi
          else
              compressed_file_details="No write permissions on the temp extraction directory"
          fi
        else
          compressed_file_details="Temporary extraction directory path is not valid"
        fi
      else
        # Verifies the user has permission to write
        if [ -w "$(dirname "$media_rar_full_path_name")" ]; then
          # Normal extraction without temporary directory and capture output into the variable
          compressed_file_details=$(unrar e -r -o- "$media_rar_full_path_name" "$media_rar_subdirectory_path" 2>&1 | tee "$fifo")
        else
            compressed_file_details="No write permissions on the archive directory"
        fi
      fi

      # Sends console output for notifications to the log file.
      notification "$compressed_file_details" true

      # Blank line
      echo ""
      # Log and append file
      notification "%s\n------------------------------------------------------------------------------------------------------------------------------"
      # Blank line
      echo ""

      # Checks if any errors occurred during the move
      if [ -n "$move_file_error_output" ]; then
        notification "%s\n$(date)|Warning|Files from $media_temp_subdirectory_path to $media_rar_subdirectory_path had issues moving. This will only be an issue during the file validation check if the file extension is in the FILE_EXTENSIONS variable\n\nSee below for the issues that occurred during the move:\n$move_file_error_output\n"
      fi

      # Log and append file
      notification "%s\n$(date)|Info|Validating file(s) extracted"

      # This section of the code validates if the extraction process was successful or not
      if [[ "$compressed_file_details" == *"All OK"* || "$compressed_file_details" == *"No files to extract"* ]]; then
        notification "%s\n$(date)|Success|RAW extraction validation passed for: $media_rar_filename"

        # Log and append file
        notification "%s\n$(date)|Info|Validating if raw files exists in $media_rar_subdirectory_path"
        # Searches for dynamic raw files based on the file extensions after the extraction process
        media_raw_full_path_names=("$(get_raw_file_paths "$media_rar_subdirectory_path")")

        # Confirms the content that was extracted matches what was listed in the rar
        file_path_validation "$media_raw_full_path_names" "$media_rar_full_path_name"
      elif [[ "$compressed_file_details" == *"%"* && "$compressed_file_details" == *"Program aborted"* ]]; then
        handle_error "RAW extraction validation failed during extraction for: $media_rar_filename. Another program may have tried copying before the extraction was completed. Manual intervention is required"
      elif [[ "$compressed_file_details" == *"No write permissions on the archive directory"* ]]; then
        handle_error "RAW extraction validation failed for: $media_rar_filename because of write permissions to the archive directory"
      elif [[ "$compressed_file_details" == *"No write permissions on the temp extraction directory"* ]]; then
        handle_error "RAW extraction validation failed for: $media_rar_filename because of write permissions to the temp extraction directory"
      elif [[ "$compressed_file_details" == *"Temporary extraction directory path is not valid"* ]]; then
        handle_error "RAW extraction validation failed for: $media_rar_filename because the temp extraction directory is not valid"
      elif [[ "$compressed_file_details" == *"Temporary subdirectory extraction directory path is not valid"* ]]; then
        handle_error "RAW extraction validation failed for: $media_rar_filename because the temp subdirectory extraction directory is not valid"
      elif [[ "$compressed_file_details" == *"Failed to delete temporary directory"* ]]; then
        handle_error "Failed to delete temporary directory: $media_temp_subdirectory_path"
      else
        handle_error "RAW extraction validation failed for: $media_rar_filename. Manual intervention is required"
      fi
    else
      handle_error "RAW file not found for: $fileName. Manual intervention is required"
    fi
  done <<<"$media_rar_full_path_names"
}

if [[ "$ENABLE_FILE_LOGGING" == true ]]; then
  set_logging
fi

notification "#######################################################################################"
notification "%s\n##############################Starting Media Extractor#################################"
notification "%s\n#######################################################################################"

# Check if TR_TORRENT_DIR is set
if [ -n "$TR_TORRENT_DIR" ]; then
  TORRENT_DIR="$TR_TORRENT_DIR"
else
  # If not set, use the provided argument $1
  if [ -n "$1" ]; then
    TORRENT_DIR="$1"
  else
    handle_error "TR_TORRENT_DIR is not set. An environment variable or passing argument must be provided for the torrent directory"
  fi
fi

# Check if TR_TORRENT_NAME is set
if [ -n "$TR_TORRENT_NAME" ]; then
  TORRENT_NAME="$TR_TORRENT_NAME"
else
   # If not set, use the provided argument $2
  if [ -n "$2" ]; then
    TORRENT_NAME="$2"
  else
    handle_error "TR_TORRENT_NAME is not set. An environment variable or passing argument must be provided for the torrent name"
  fi
fi

# Check if the path does not exist
if [ ! -d "/$TORRENT_DIR/$TORRENT_NAME" ]; then
    handle_error "The path to the rar file is not valid: /$TORRENT_DIR/$TORRENT_NAME. Please check the TORRENT_DIR and/or TORRENT_NAME"
fi

# Searches for static RAR files
media_rar_full_path_names=$(find "/$TORRENT_DIR/$TORRENT_NAME" -name *".rar")

# Searches for dynamic raw files based on the file extensions
media_raw_full_path_names=("$(get_raw_file_paths "/$TORRENT_DIR/$TORRENT_NAME")")

# General notification for a completed torrent
if [[ -n "$media_raw_full_path_names" || -n "$media_rar_full_path_names" ]]; then
  # Torrent Downloaded successfully.
  notification "%s\n$(date)|Info|The following torrent completed downloading: $TORRENT_NAME"
fi

# Check which file types are in the media downloaded folder
# This is used to determine if a RAR file needs to be extracted
if [[ -n "$media_rar_full_path_names" ]] && [[ -z "$media_raw_full_path_names" ]]; then
  extract_torrent "$TORRENT_DIR" "$TORRENT_NAME" "$media_rar_full_path_names"
  # Pauses for 3 seconds before exit to allow writes to console
  sleep 3
  exit
elif [[ -n "$media_raw_full_path_names" ]] && [[ -n "$media_rar_full_path_names" ]]; then
  # Notifying both RAR and RAW both exist
  notification "%s\n$(date)|Info|RAR and RAW files were found in torrent: $TORRENT_NAME. [This is not common unless a manual extraction occurred]"

  # Rechecks the RAW files because some already exist and the recheck flag was enabled
  if [[ "$RECHECK_EXISTING_RAW" == true ]]; then
    extract_torrent "$TORRENT_DIR" "$TORRENT_NAME" "$media_rar_full_path_names"
  else
    file_path_validation "$media_raw_full_path_names" "$media_rar_full_path_names"
  fi
  # Pauses for 3 seconds before exit to allow writes to console
  sleep 3
  exit
elif [[ -n "$media_raw_full_path_names" ]] && [[ -z "$media_rar_full_path_names" ]]; then
  # Notifying only RAW files exist and no extraction is required
  notification "%s\n$(date)|Info|Only RAW files were found in torrent: $TORRENT_NAME"
  notification "%s\n$(date)|Info|No RAR extraction is required"

  file_path_validation "$media_raw_full_path_names" "$media_rar_full_path_names"
  # Pauses for 3 seconds before exit to allow writes to console
  sleep 3
  exit
elif [[ -z "$media_raw_full_path_names" ]] && [[ -z "$media_rar_full_path_names" ]]; then
  # Notifying both RAR and RAW do not exist
  notification "%s\n$(date)|Warning|No RAR or RAW files were found to match the required file extensions (${FILE_EXTENSIONS[*]})"
  # Blank line
  echo ""
  # Pauses for 3 seconds before exit to allow writes to console
  sleep 3
  exit
fi
