#!/bin/dash

#########################################################################
#                                                             _         #
#   ___ ___  _ __ ___  _ __  _ __ ___  ___ ___  ___  _ __ ___| |__      #
#  / __/ _ \| '_ ` _ \| '_ \| '__/ _ \/ __/ __|/ _ \| '__/ __| '_ \     #
# | (_| (_) | | | | | | |_) | | |  __/\__ \__ \ (_) | | _\__ \ | | |    #
#  \___\___/|_| |_| |_| .__/|_|  \___||___/___/\___/|_|(_)___/_| |_|    #
#                     |_|                                               #
#                                                                       #
#   A POSIX-compliant smart script for compressing videos with FFmpeg   #
#                                                                       #
#########################################################################

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -e

# --- Script Information ---
SCRIPT_NAME=$(basename "$0")

# --- Default Settings ---
DEFAULT_AUDIO_BITRATE="128k"
FFMPEG_PASSLOG_PREFIX="ffmpeg_twopass"
DEFAULT_CODEC="h264"

BITRATE_THRESHOLD_1080P_TO_720P=2000
BITRATE_THRESHOLD_720P_TO_480P=1000
MIN_ACCEPTABLE_VIDEO_BITRATE_KBPS=100

# --- ANSI Colors for Output (Optional) ---
C_BOLD=$(printf '\033[1m') C_GREEN=$(printf '\033[32m') C_YELLOW=$(printf '\033[33m')
C_BLUE=$(printf '\033[34m') C_CYAN=$(printf '\033[36m') C_RESET=$(printf '\033[0m')
# Uncomment for no colors:
# C_BOLD="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_RESET=""


# --- Helper Functions ---
check_dependencies() {
    for cmd in ffmpeg ffprobe bc; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            printf "%sError:%s Command '%s%s%s' not found. Please install it.\n" "$C_BOLD" "$C_RESET" "$C_YELLOW" "$cmd" "$C_RESET" >&2
            exit 1
        fi
    done
}

cleanup_log_files() {
    rm -f "${FFMPEG_PASSLOG_PREFIX}"-*.log "${FFMPEG_PASSLOG_PREFIX}"-*.log.mbtree "ffmpeg2pass-0.log" "ffmpeg2pass-0.log.mbtree"
}

usage() {
    printf "%s%s v%s%s - Intelligent Video Compressor\n" "$C_BOLD" "$SCRIPT_NAME" "$C_RESET"
    printf "\n"
    printf "%sUsage:%s %s <input_video> <target_size_MB> <resolution_height|auto> [options]\n" "$C_BOLD" "$C_RESET" "$0"
    printf "\n"
    printf "%sRequired arguments:%s\n" "$C_BOLD" "$C_RESET"
    printf "  %s<input_video>%s           Path to the input video file.\n" "$C_GREEN" "$C_RESET"
    printf "  %s<target_size_MB>%s        Desired output file size in Megabytes.\n" "$C_GREEN" "$C_RESET"
    printf "  %s<resolution_height|auto>%s Target video height (e.g., 720, 1080) or 'auto'.\n" "$C_GREEN" "$C_RESET"
    printf "\n"
    printf "%sOptions:%s\n" "$C_BOLD" "$C_RESET"
    printf "  %s-ns%s                     No sound: remove audio from the output video.\n" "$C_YELLOW" "$C_RESET"
    printf "  %s-fps <value>%s            Set target framerate (frames per second). E.g., 24, 30.\n" "$C_YELLOW" "$C_RESET"
    printf "                          If not specified, uses the original video's framerate.\n"
    printf "  %s-codec <h264|h265>%s      Set video codec. Default: %s.\n" "$C_YELLOW" "$C_RESET" "$DEFAULT_CODEC"
    printf "                          h265 (HEVC) offers better compression but is slower.\n"
    printf "  %s-h, --help%s             Display this help message and exit.\n" "$C_YELLOW" "$C_RESET"
    printf "\n"
    printf "%sExamples:%s\n" "$C_BOLD" "$C_RESET"
    printf "  %s video.mp4 10 auto\n" "$0"
    printf "  %s video.mp4 10 720 -ns -codec h265\n" "$0"
    printf "  %s video.mp4 10 auto -fps 24\n" "$0"
    exit 0
}

# --- Argument Parsing and Validation ---
INPUT_FILE=""; TARGET_SIZE_MB=""; RESOLUTION_ARG=""; NO_SOUND_FLAG="false"; REQUESTED_FRAMERATE=""; CHOSEN_CODEC="$DEFAULT_CODEC"

# Check for help option first, as it doesn't require other args
for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
        usage
    fi
done

while [ "$#" -gt 0 ]; do
    case "$1" in
        -ns) NO_SOUND_FLAG="true"; shift ;;
        -fps)
            if [ -n "$2" ]; then
                case "$2" in
                    -*) # Next arg starts with '-', so -fps is missing its value
                        printf "%sError:%s -fps requires a value.\n" "$C_BOLD" "$C_RESET" >&2; usage ;;
                    *)  REQUESTED_FRAMERATE="$2"; shift 2 ;;
                esac
            else
                printf "%sError:%s -fps requires a value.\n" "$C_BOLD" "$C_RESET" >&2; usage
            fi ;;
        -codec)
            if [ -n "$2" ] && ( [ "$2" = "h264" ] || [ "$2" = "h265" ] ); then
                 CHOSEN_CODEC="$2"; shift 2
            else
                 printf "%sError:%s -codec must be 'h264' or 'h265'.\n" "$C_BOLD" "$C_RESET" >&2; usage
            fi ;;
        -*) printf "%sError:%s Unknown option: %s\n" "$C_BOLD" "$C_RESET" "$1" >&2; usage ;;
        *)
            if [ -z "$INPUT_FILE" ]; then INPUT_FILE="$1";
            elif [ -z "$TARGET_SIZE_MB" ]; then TARGET_SIZE_MB="$1";
            elif [ -z "$RESOLUTION_ARG" ]; then RESOLUTION_ARG="$1";
            else printf "%sError:%s Excessive args: %s\n" "$C_BOLD" "$C_RESET" "$1" >&2; usage; fi;
            shift ;;
    esac
done

if [ -z "$INPUT_FILE" ] || [ -z "$TARGET_SIZE_MB" ] || [ -z "$RESOLUTION_ARG" ]; then printf "%sError:%s Missing required args.\n" "$C_BOLD" "$C_RESET" >&2; usage; fi

# --- CORRECTED is_positive_number function ---
is_positive_number() {
    _val="$1"
    # Check for integer: one or more digits. Anchored.
    if expr "$_val" : '^[0-9]\{1,\}$' > /dev/null ; then
        return 0 # true, matched integer form
    # Check for float: one or more digits, a dot, one or more digits. Anchored.
    elif expr "$_val" : '^[0-9]\{1,\}\.[0-9]\{1,\}$' > /dev/null ; then
        return 0 # true, matched float form
    fi
    return 1 # false
}
# --- END CORRECTED is_positive_number function ---

if ! is_positive_number "$TARGET_SIZE_MB" || [ "$(echo "$TARGET_SIZE_MB <= 0" | bc -l)" -eq 1 ]; then printf "%sError:%s Target size must be a positive number.\n" "$C_BOLD" "$C_RESET" >&2; exit 1; fi
if [ ! -f "$INPUT_FILE" ]; then printf "%sError:%s Input file '%s%s%s' not found.\n" "$C_BOLD" "$C_RESET" "$C_YELLOW" "$INPUT_FILE" "$C_RESET" >&2; exit 1; fi
if [ "$RESOLUTION_ARG" != "auto" ] && ! expr "$RESOLUTION_ARG" : '^[0-9]\{1,\}$' > /dev/null; then printf "%sError:%s Resolution must be 'auto' or a numeric height.\n" "$C_BOLD" "$C_RESET" >&2; exit 1; fi

if [ -n "$REQUESTED_FRAMERATE" ]; then
    is_valid_framerate_format="false"
    # Check if it's a number (integer or float like NNN or NNN.NNN)
    if expr "$REQUESTED_FRAMERATE" : '^[0-9]\{1,\}$' > /dev/null; then # Integer
        is_valid_framerate_format="true"
    elif expr "$REQUESTED_FRAMERATE" : '^[0-9]\{1,\}\.[0-9]\{1,\}$' > /dev/null; then # Float
        is_valid_framerate_format="true"
    # Check if it's a fraction (NNN/NNN)
    elif expr "$REQUESTED_FRAMERATE" : '^[0-9]\{1,\}/[0-9]\{1,\}$' > /dev/null; then # Fraction
        is_valid_framerate_format="true"
    fi

    if [ "$is_valid_framerate_format" != "true" ]; then
         printf "%sError:%s -fps value '%s' is invalid.\n" "$C_BOLD" "$C_RESET" "$REQUESTED_FRAMERATE" >&2; exit 1;
    fi
fi


check_dependencies
printf "\n%s===== %s v%s - Video Compression Start =====%s\n\n" "$C_BOLD" "$SCRIPT_NAME" "$C_RESET"
BASE_NAME=$(basename "$INPUT_FILE"); EXTENSION="${BASE_NAME##*.}"; FILENAME_NO_EXT="${BASE_NAME%.*}"
cleanup_log_files

printf "%sGathering video information...%s\n" "$C_BLUE" "$C_RESET"
SOURCE_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=s=x:p=0 "$INPUT_FILE")
SOURCE_HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=s=x:p=0 "$INPUT_FILE")
DURATION_SECONDS=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
ORIGINAL_FRAMERATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
INPUT_PIX_FMT=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")

if [ -z "$SOURCE_WIDTH" ] || [ -z "$SOURCE_HEIGHT" ] || [ -z "$DURATION_SECONDS" ] || [ -z "$ORIGINAL_FRAMERATE" ] || [ -z "$INPUT_PIX_FMT" ] || [ "$(echo "$DURATION_SECONDS <= 0" | bc -l)" -eq 1 ]; then
    printf "%sError:%s Could not retrieve all necessary video information from '%s'.\n" "$C_BOLD" "$C_RESET" "$INPUT_FILE" >&2; cleanup_log_files; exit 1; fi

printf "\n%s--- Settings Summary ---%s\n" "$C_BOLD" "$C_RESET"
printf "  %sInput File:%s         %s (%s)\n" "$C_CYAN" "$C_RESET" "$INPUT_FILE" "$INPUT_PIX_FMT"
printf "  %sOriginal Resolution:%s %sx%s\n" "$C_CYAN" "$C_RESET" "$SOURCE_WIDTH" "$SOURCE_HEIGHT"
printf "  %sOriginal Framerate:%s  %s\n" "$C_CYAN" "$C_RESET" "$ORIGINAL_FRAMERATE"
printf "  %sDuration:%s            %s seconds\n" "$C_CYAN" "$C_RESET" "$DURATION_SECONDS"
printf "\n  %sTarget Size:%s        %sMB\n" "$C_CYAN" "$C_RESET" "$TARGET_SIZE_MB"
printf "  %sRequested Resolution:%s %s\n" "$C_CYAN" "$C_RESET" "$RESOLUTION_ARG"
printf "  %sChosen Codec:%s        %s\n" "$C_CYAN" "$C_RESET" "$CHOSEN_CODEC"
if [ "$NO_SOUND_FLAG" = "true" ]; then printf "  %sAudio:%s                Will be removed\n" "$C_CYAN" "$C_RESET"; else printf "  %sAudio:%s                Kept (Bitrate: %s)\n" "$C_CYAN" "$C_RESET" "$DEFAULT_AUDIO_BITRATE"; fi
FINAL_FRAMERATE=$ORIGINAL_FRAMERATE
if [ -n "$REQUESTED_FRAMERATE" ]; then FINAL_FRAMERATE="$REQUESTED_FRAMERATE"; if [ "$FINAL_FRAMERATE" != "$ORIGINAL_FRAMERATE" ]; then printf "  %sTarget Framerate:%s     %s fps %s(Changed)%s\n" "$C_CYAN" "$C_RESET" "$FINAL_FRAMERATE" "$C_YELLOW" "$C_RESET"; else printf "  %sTarget Framerate:%s     %s fps (Matches original)\n" "$C_CYAN" "$C_RESET" "$FINAL_FRAMERATE"; fi
else printf "  %sTarget Framerate:%s     %s fps (Using original)\n" "$C_CYAN" "$C_RESET" "$FINAL_FRAMERATE"; fi

TARGET_SIZE_BITS=$(echo "$TARGET_SIZE_MB * 1024 * 1024 * 8" | bc); TOTAL_BITRATE_BPS=$(echo "scale=0; $TARGET_SIZE_BITS / $DURATION_SECONDS" | bc); TOTAL_BITRATE_KBPS=$(echo "scale=0; $TOTAL_BITRATE_BPS / 1000" | bc)
if [ "$NO_SOUND_FLAG" = "true" ]; then VIDEO_BITRATE_KBPS=$TOTAL_BITRATE_KBPS; else AUDIO_BITRATE_KBPS_VALUE=$(echo "$DEFAULT_AUDIO_BITRATE" | sed 's/k//I'); VIDEO_BITRATE_KBPS=$(echo "$TOTAL_BITRATE_KBPS - $AUDIO_BITRATE_KBPS_VALUE" | bc); fi
printf "\n  %sCalculated Total Bitrate:%s %s kbps\n" "$C_CYAN" "$C_RESET" "$TOTAL_BITRATE_KBPS"
if [ "$NO_SOUND_FLAG" != "true" ]; then printf "  %sCalculated Video Bitrate:%s %s kbps (Audio: %s kbps)\n" "$C_CYAN" "$C_RESET" "$VIDEO_BITRATE_KBPS" "$AUDIO_BITRATE_KBPS_VALUE"; else printf "  %sCalculated Video Bitrate:%s %s kbps (No audio)\n" "$C_CYAN" "$C_RESET" "$VIDEO_BITRATE_KBPS"; fi
effective_min_bitrate=$MIN_ACCEPTABLE_VIDEO_BITRATE_KBPS; if [ "$CHOSEN_CODEC" = "h265" ]; then effective_min_bitrate=$(echo "$MIN_ACCEPTABLE_VIDEO_BITRATE_KBPS * 0.7" | bc); fi
if [ -z "$VIDEO_BITRATE_KBPS" ]; then
    printf "\n%sError:%s Video bitrate could not be calculated (possibly due to zero duration or target size).\n" "$C_BOLD" "$C_RESET" >&2; cleanup_log_files; exit 1;
fi
if [ "$(echo "$VIDEO_BITRATE_KBPS < $effective_min_bitrate" | bc -l)" -eq 1 ]; then printf "\n%sError:%s Calculated video bitrate (%s kbps) is below the effective minimum (%s kbps) for codec %s.\n" "$C_BOLD" "$C_RESET" "$VIDEO_BITRATE_KBPS" "$effective_min_bitrate" "$CHOSEN_CODEC" >&2; cleanup_log_files; exit 1; fi

FINAL_TARGET_HEIGHT=$SOURCE_HEIGHT; SCALE_NEEDED=false
if [ "$RESOLUTION_ARG" = "auto" ]; then EFFECTIVE_BITRATE_FOR_CURRENT_RES=$VIDEO_BITRATE_KBPS
    if [ "$SOURCE_HEIGHT" -ge 1080 ] && [ "$(echo "$EFFECTIVE_BITRATE_FOR_CURRENT_RES < $BITRATE_THRESHOLD_1080P_TO_720P" | bc -l)" -eq 1 ]; then FINAL_TARGET_HEIGHT=720; fi
    if [ "$FINAL_TARGET_HEIGHT" -ge 720 ] && [ "$SOURCE_HEIGHT" -ge 720 ] && [ "$(echo "$EFFECTIVE_BITRATE_FOR_CURRENT_RES < $BITRATE_THRESHOLD_720P_TO_480P" | bc -l)" -eq 1 ] && [ "$FINAL_TARGET_HEIGHT" -eq 720 ]; then FINAL_TARGET_HEIGHT=480; fi
    if [ "$FINAL_TARGET_HEIGHT" -gt "$SOURCE_HEIGHT" ]; then FINAL_TARGET_HEIGHT=$SOURCE_HEIGHT; fi
    if [ $((FINAL_TARGET_HEIGHT % 2)) -ne 0 ]; then FINAL_TARGET_HEIGHT=$((FINAL_TARGET_HEIGHT - 1)); fi
else USER_REQUESTED_HEIGHT="$RESOLUTION_ARG"; if [ "$USER_REQUESTED_HEIGHT" -gt "$SOURCE_HEIGHT" ]; then FINAL_TARGET_HEIGHT=$SOURCE_HEIGHT; else FINAL_TARGET_HEIGHT=$USER_REQUESTED_HEIGHT; fi
    if [ $((FINAL_TARGET_HEIGHT % 2)) -ne 0 ]; then FINAL_TARGET_HEIGHT=$((FINAL_TARGET_HEIGHT - 1)); fi; fi

if [ "$FINAL_TARGET_HEIGHT" -lt "$SOURCE_HEIGHT" ]; then SCALE_NEEDED=true;
elif [ "$RESOLUTION_ARG" != "auto" ] && [ "$FINAL_TARGET_HEIGHT" -lt "$RESOLUTION_ARG" ]; then if [ $((SOURCE_WIDTH % 2)) -ne 0 ]; then SCALE_NEEDED=true; fi
elif [ "$FINAL_TARGET_HEIGHT" -ne "$SOURCE_HEIGHT" ] || [ $((SOURCE_WIDTH % 2)) -ne 0 ]; then SCALE_NEEDED=true; fi


# Construct VF_STRING
VF_STRING=""
NEEDS_FORMAT_FILTER=false

if [ "$SCALE_NEEDED" = "true" ] ; then
    VF_STRING="scale=-2:${FINAL_TARGET_HEIGHT}"
    NEEDS_FORMAT_FILTER=true
fi

if [ "$INPUT_PIX_FMT" = "yuvj420p" ] && [ "$SCALE_NEEDED" != "true" ]; then
    NEEDS_FORMAT_FILTER=true
fi

if [ "$NEEDS_FORMAT_FILTER" = "true" ]; then
    if [ -n "$VF_STRING" ]; then
        VF_STRING="${VF_STRING},format=yuv420p"
    else
        VF_STRING="format=yuv420p"
    fi
fi


# Display final resolution message
if [ "$SCALE_NEEDED" = "true" ] && [ "$FINAL_TARGET_HEIGHT" -lt "$SOURCE_HEIGHT" ]; then
    printf "  %sFinal Resolution:%s       %sp %s(Downscaled)%s\n" "$C_CYAN" "$C_RESET" "$FINAL_TARGET_HEIGHT" "$C_YELLOW" "$C_RESET"
elif [ "$SCALE_NEEDED" = "true" ] && [ "$RESOLUTION_ARG" != "auto" ] && [ "$FINAL_TARGET_HEIGHT" -lt "$RESOLUTION_ARG" ]; then
     printf "  %sFinal Resolution:%s       %sp %s(Original, not upscaled to %sp)%s\n" "$C_CYAN" "$C_RESET" "$FINAL_TARGET_HEIGHT" "$C_YELLOW" "$RESOLUTION_ARG" "$C_RESET"
elif [ "$NEEDS_FORMAT_FILTER" = "true" ]; then
    printf "  %sFinal Resolution:%s       %sp %s(Processed for format/range)%s\n" "$C_CYAN" "$C_RESET" "$FINAL_TARGET_HEIGHT" "$C_YELLOW" "$C_RESET"
else
    printf "  %sFinal Resolution:%s       %sp\n" "$C_CYAN" "$C_RESET" "$FINAL_TARGET_HEIGHT"
fi


OUTPUT_SUFFIX_CODEC=""; if [ "$CHOSEN_CODEC" != "$DEFAULT_CODEC" ]; then OUTPUT_SUFFIX_CODEC="_${CHOSEN_CODEC}"; fi
OUTPUT_SUFFIX_SOUND=""; if [ "$NO_SOUND_FLAG" = "true" ]; then OUTPUT_SUFFIX_SOUND="_nosound"; fi
OUTPUT_SUFFIX_FPS=""
if [ "$FINAL_FRAMERATE" != "$ORIGINAL_FRAMERATE" ]; then
    if expr "$FINAL_FRAMERATE" : '^[0-9]\{1,\}$' > /dev/null ; then
        CLEAN_FPS="$FINAL_FRAMERATE"
        OUTPUT_SUFFIX_FPS="_${CLEAN_FPS}fps"
    elif [ "$FINAL_FRAMERATE" = "30000/1001" ]; then OUTPUT_SUFFIX_FPS="_29.97fps";
    elif [ "$FINAL_FRAMERATE" = "24000/1001" ]; then OUTPUT_SUFFIX_FPS="_23.976fps";
    else OUTPUT_SUFFIX_FPS="_customfps"; fi
fi

OUTPUT_FILE="${FILENAME_NO_EXT}_compressed_${TARGET_SIZE_MB}MB_${FINAL_TARGET_HEIGHT}p${OUTPUT_SUFFIX_CODEC}${OUTPUT_SUFFIX_FPS}${OUTPUT_SUFFIX_SOUND}.${EXTENSION}"
printf "  %sOutput File:%s          %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_GREEN" "$OUTPUT_FILE" "$C_RESET"
if [ -n "$VF_STRING" ]; then
    printf "  %sVideo Filters Used:%s  %s%s%s\n" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$VF_STRING" "$C_RESET"
fi
printf "%s------------------------%s\n" "$C_BOLD" "$C_RESET"

# --- FFmpeg Command Construction ---

# Pass 1
printf "\n%s>>> Starting FFmpeg Pass 1...%s\n" "$C_BOLD" "$C_RESET"
set -- ffmpeg -y

if [ "$INPUT_PIX_FMT" = "yuvj420p" ]; then
    set -- "$@" -color_range pc
fi
set -- "$@" -i "$INPUT_FILE"

if [ "$CHOSEN_CODEC" = "h265" ]; then
    set -- "$@" -c:v libx265
else
    set -- "$@" -c:v libx264 -tune film
fi

set -- "$@" \
    -b:v "${VIDEO_BITRATE_KBPS}k" \
    -r "$FINAL_FRAMERATE" \
    -pix_fmt yuv420p \
    -color_range 1 \
    -passlogfile "$FFMPEG_PASSLOG_PREFIX" \
    -preset medium

if [ -n "$VF_STRING" ]; then
    set -- "$@" -vf "$VF_STRING"
fi

set -- "$@" -pass 1 -an -f mp4 /dev/null

printf "%sCommand:%s %s\n" "$C_CYAN" "$C_RESET" "$*"
"$@"

# Pass 2
printf "\n%s>>> Starting FFmpeg Pass 2...%s\n" "$C_BOLD" "$C_RESET"
set -- ffmpeg -y

if [ "$INPUT_PIX_FMT" = "yuvj420p" ]; then
    set -- "$@" -color_range pc
fi
set -- "$@" -i "$INPUT_FILE"

if [ "$CHOSEN_CODEC" = "h265" ]; then
    set -- "$@" -c:v libx265
else
    set -- "$@" -c:v libx264 -tune film
fi

set -- "$@" \
    -b:v "${VIDEO_BITRATE_KBPS}k" \
    -r "$FINAL_FRAMERATE" \
    -pix_fmt yuv420p \
    -color_range 1 \
    -passlogfile "$FFMPEG_PASSLOG_PREFIX" \
    -preset medium

if [ -n "$VF_STRING" ]; then
    set -- "$@" -vf "$VF_STRING"
fi

set -- "$@" -pass 2

if [ "$NO_SOUND_FLAG" = "true" ]; then
    set -- "$@" -an
else
    set -- "$@" -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE"
fi

set -- "$@" "$OUTPUT_FILE"

printf "%sCommand:%s %s\n" "$C_CYAN" "$C_RESET" "$*"
"$@"


cleanup_log_files
printf "\n%s===== Compression Complete! =====%s\n" "$C_BOLD" "$C_RESET"
printf "  %sOutput file generated:%s %s\n" "$C_GREEN" "$C_RESET" "$OUTPUT_FILE"
ACTUAL_SIZE_MB=$(du -m "$OUTPUT_FILE" | cut -f1)
printf "  %sActual file size:%s    %sMB (Target was %sMB)\n" "$C_CYAN" "$C_RESET" "$ACTUAL_SIZE_MB" "$TARGET_SIZE_MB"
TOLERANCE_RAW=$(echo "scale=0; $TARGET_SIZE_MB / 10" | bc)
TOLERANCE=${TOLERANCE_RAW:-1}
if [ -z "$TOLERANCE_RAW" ] || [ "$(echo "$TOLERANCE_RAW < 1" | bc -l)" -eq 1 ]; then
    TOLERANCE=1
fi

SIZE_DIFF=$(echo "$ACTUAL_SIZE_MB - $TARGET_SIZE_MB" | bc)
SIZE_DIFF_ABS=$SIZE_DIFF
if [ "$(expr substr "$SIZE_DIFF" 1 1)" = "-" ]; then
    SIZE_DIFF_ABS=$(expr substr "$SIZE_DIFF" 2 $(expr length "$SIZE_DIFF"))
fi
if [ -z "$SIZE_DIFF_ABS" ]; then SIZE_DIFF_ABS=0; fi

if [ "$(echo "$SIZE_DIFF_ABS > $TOLERANCE" | bc -l)" -eq 1 ]; then
   printf "  %sWarning:%s Final file size differs significantly from target.\n" "$C_YELLOW" "$C_RESET"
fi
printf "%s===============================%s\n\n" "$C_BOLD" "$C_RESET"
exit 0
