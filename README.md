# 🎬 Smart Video Compressor Script Compressor

A POSIX-compliant smart script for compressing videos with FFmpeg. This script intelligently compresses video files to a user-defined target size while optimizing for quality. It automatically adjusts resolution and video bitrate based on the input video and target size, supports various codecs, and offers options for audio removal and framerate changes.

## ✨ Key Features

*   🎯 **Target Size Compression:** Specify the desired output file size in Megabytes.
*   🤖 **Automatic Resolution Adjustment:** Intelligently downscales video (e.g., 1080p → 720p → 480p) based on calculated bitrates to maintain quality. It won't upscale video.
*   🎞️ **Codec Support:** Choose between H.264 (default, good compatibility) and H.265/HEVC (better compression, slower encoding).
*   🔇 **Audio Removal:** Option to completely remove the audio track from the output video.
*   ⏱️ **Framerate Control:** Set a specific target framerate for the output video or retain the original.
*   ✌️ **Two-Pass Encoding:** Utilizes FFmpeg's two-pass encoding method for the best possible quality at the given target file size.
*   🖥️ **POSIX-Compliant:** Designed to run on UNIX-like systems using standard shell features.
*   🛠️ **Dependency Management:** Checks for required tools (`ffmpeg`, `ffprobe`, `bc`) before starting.
*   🎨 **User-Friendly Output:** Provides clear, colored console output (optional) summarizing settings and progress.
*   📝 **Flexible Naming:** Generates descriptive output filenames based on the chosen compression settings.

## ⚙️ How It Works

The script follows a series of steps to compress your video intelligently:

1.  **Initialization & Dependency Check:**
    *   Sets up essential variables and defines helper functions.
    *   Verifies that `ffmpeg`, `ffprobe`, and `bc` are installed and accessible in the system's PATH. If any are missing, it exits with an error.

2.  **Argument Parsing & Validation:**
    *   Parses command-line arguments: input video file, target size (MB), and target resolution (height in pixels or 'auto').
    *   Processes optional flags:
        *   `-ns`: No sound (removes audio).
        *   `-fps <value>`: Sets a target framerate.
        *   `-codec <h264|h265>`: Chooses the video codec.
        *   `-h` or `--help`: Displays the usage message.
    *   Validates inputs (e.g., target size is positive, input file exists, resolution is 'auto' or numeric).

3.  **Video Information Gathering:**
    *   Uses `ffprobe` to extract crucial metadata from the input video:
        *   Source width and height.
        *   Total duration in seconds.
        *   Original framerate (r_frame_rate).
        *   Pixel format (e.g., `yuv420p`, `yuvj420p`).

4.  **Bitrate Calculation:**
    *   **Total Target Bitrate:** Converts the `target_size_MB` into bits and divides by the video `DURATION_SECONDS` to get the overall target bitrate in bits per second (bps). This is then converted to kilobits per second (kbps).
        ```
        TARGET_SIZE_BITS = TARGET_SIZE_MB * 1024 * 1024 * 8
        TOTAL_BITRATE_BPS = TARGET_SIZE_BITS / DURATION_SECONDS
        TOTAL_BITRATE_KBPS = TOTAL_BITRATE_BPS / 1000
        ```
    *   **Video Bitrate:**
        *   If audio is kept (default), the script subtracts a `DEFAULT_AUDIO_BITRATE` (currently "128k") from the `TOTAL_BITRATE_KBPS` to determine the `VIDEO_BITRATE_KBPS`.
        *   If audio is removed (`-ns` flag), the `VIDEO_BITRATE_KBPS` is equal to `TOTAL_BITRATE_KBPS`.
    *   **Minimum Bitrate Check:** The script checks if the calculated `VIDEO_BITRATE_KBPS` is above a `MIN_ACCEPTABLE_VIDEO_BITRATE_KBPS` (100 kbps for H.264, adjusted lower for H.265 due to its efficiency). If it's too low, the script exits, as the quality would likely be unacceptable.

5.  **Resolution Adjustment (if `RESOLUTION_ARG` is 'auto'):**
    *   The script aims to maintain the best possible quality for the calculated `VIDEO_BITRATE_KBPS`.
    *   If the source video height is 1080p or higher, and the `VIDEO_BITRATE_KBPS` is below `BITRATE_THRESHOLD_1080P_TO_720P` (2000 kbps), the target height is automatically set to 720p.
    *   If the (potentially already adjusted) target height is 720p or higher, and the `VIDEO_BITRATE_KBPS` is below `BITRATE_THRESHOLD_720P_TO_480P` (1000 kbps), the target height is further reduced to 480p.
    *   The script ensures the final target height does not exceed the original video's height (no upscaling).
    *   The final target height is also adjusted to be an even number, as required by many video codecs.
    *   If a specific resolution height is provided by the user, it will be used, unless it's higher than the source video's height (in which case, source height is used).

6.  **FFmpeg Command Construction & Execution (Two-Pass Encoding):**
    *   **Video Filters (`-vf`):**
        *   `scale=-2:TARGET_HEIGHT`: If scaling is needed, this filter resizes the video to the `FINAL_TARGET_HEIGHT` while maintaining the aspect ratio (the `-2` ensures the width is also an even number).
        *   `format=yuv420p`: This filter is added to ensure the output pixel format is `yuv420p`, which is widely compatible. It's particularly important if scaling occurs or if the input is `yuvj420p` (common from some cameras, representing full range JPEG colors).
    *   **Color Range Handling:** If the input pixel format is `yuvj420p`, the script adds `-color_range pc` (for FFmpeg versions that support it) or implies its handling during input to FFmpeg, and then specifies `-color_range 1` (for TV/limited range) in the output options. This helps prevent washed-out colors when converting from full range to limited range YUV.
    *   **Pass 1:**
        *   FFmpeg is run with `-pass 1`.
        *   Key options:
            *   `-c:v libx264` or `libx265` (selected video codec).
            *   `-b:v VIDEO_BITRATE_KBPSk` (target video bitrate).
            *   `-r FINAL_FRAMERATE` (target framerate).
            *   `-pix_fmt yuv420p`
            *   `-color_range 1` (output color range for compatibility)
            *   `-preset medium` (a balance between encoding speed and compression efficiency).
            *   `-an` (no audio for pass 1).
            *   Output is directed to `/dev/null` (or NUL on Windows, though this is a POSIX script).
            *   A log file (`ffmpeg_twopass-*.log`) is generated by FFmpeg, containing analysis data.
    *   **Pass 2:**
        *   FFmpeg is run with `-pass 2`.
        *   Uses the same video settings as Pass 1 (bitrate, codec, filters, etc.).
        *   Reads the log file generated in Pass 1 for optimized encoding.
        *   **Audio Handling:**
            *   If audio is kept: `-c:a aac -b:a DEFAULT_AUDIO_BITRATE` is added to encode audio using the AAC codec.
            *   If `-ns` is used: `-an` is added to exclude audio.
        *   The final compressed video is written to the `OUTPUT_FILE`.

7.  **Output Filename Generation:**
    *   The output filename is constructed with the following pattern:
        `<original_filename_no_ext>_compressed_<target_size_MB>MB_<final_resolution_height>p[_<codec>][_<framerate>fps][_nosound].<original_extension>`
    *   Optional parts like `_h265`, `_24fps`, or `_nosound` are added if those options were used and differ from defaults/original.

8.  **Cleanup:**
    *   The FFmpeg log files (e.g., `ffmpeg_twopass-*.log`, `ffmpeg_twopass-*.log.mbtree`) are removed.

9.  **Final Report:**
    *   The script prints the path to the output file and its actual size, comparing it to the target size.
    *   A warning is displayed if the actual size deviates significantly (by more than a 10% tolerance, minimum 1MB) from the target.

## 🛠️ Prerequisites/Dependencies

To use this script, you need the following command-line tools installed on your system:

*   **FFmpeg:** The core multimedia framework for video and audio processing.
    *   `ffmpeg`: The command-line tool for performing encoding, decoding, muxing, demuxing, etc.
    *   `ffprobe`: A tool for analyzing media streams and extracting metadata. (Usually included with FFmpeg installations).
*   **bc (Basic Calculator):** A command-line utility for performing arithmetic operations. The script uses `bc` for bitrate and other numerical calculations.

---

**Installation Examples:**

Most package managers can install these tools. Here are some common examples:

*   **Debian/Ubuntu & derivatives:**
    ```bash
    sudo apt update
    sudo apt install ffmpeg bc
    ```

*   **Fedora & RHEL-based systems:**
    ```bash
    sudo dnf install ffmpeg bc  # Or use 'yum' on older systems
    ```

*   **macOS (using Homebrew):**
    ```bash
    brew install ffmpeg bc
    ```

*   **Arch Linux & derivatives:**
    ```bash
    sudo pacman -S ffmpeg bc
    ```

Please consult your operating system's documentation or package manager for the specific commands if your system is not listed above.

## 🚀 Usage

1.  **Make the script executable:**
    ```bash
    chmod +x compressor.sh
    ```

2.  **Run the script:**

    The script's help message provides a concise overview of its arguments and options:

    ```bash
    ./compressor.sh -h
    ```

    This will output:
    ```
    compressor.sh v - Intelligent Video Compressor

    Usage: ./compressor.sh <input_video> <target_size_MB> <resolution_height|auto> [options]

    Required arguments:
      <input_video>           Path to the input video file.
      <target_size_MB>        Desired output file size in Megabytes.
      <resolution_height|auto> Target video height (e.g., 720, 1080) or 'auto'.

    Options:
      -ns                     No sound: remove audio from the output video.
      -fps <value>            Set target framerate (frames per second). E.g., 24, 30.
                              If not specified, uses the original video's framerate.
      -codec <h264|h265>      Set video codec. Default: h264.
                              h265 (HEVC) offers better compression but is slower.
      -h, --help             Display this help message and exit.

    Examples:
      ./compressor.sh video.mp4 10 auto
      ./compressor.sh video.mp4 10 720 -ns -codec h265
      ./compressor.sh video.mp4 10 auto -fps 24
    ```

    *(Note: The actual version number might differ in the script's output).*

---

### 📋 Examples:

Here are a few common use cases:

*   **Compress `my_video.mp4` to approximately 50MB, automatically adjusting resolution:**
    ```bash
    ./compressor.sh my_video.mp4 50 auto
    ```

*   **Compress `input.mov` to 20MB, targeting 720p height, and remove audio:**
    ```bash
    ./compressor.sh input.mov 20 720 -ns
    ```

*   **Compress `holidays.mkv` to 100MB, using the H.265 (HEVC) codec for better compression, keeping original resolution (by using 'auto' and assuming bitrate is sufficient):**
    ```bash
    ./compressor.sh holidays.mkv 100 auto -codec h265
    ```

*   **Compress `lecture_recording.webm` to 75MB, automatically adjusting resolution, and changing framerate to 24 fps:**
    ```bash
    ./compressor.sh lecture_recording.webm 75 auto -fps 24
    ```

*   **Compress `short_clip.mp4` to 5MB, targeting 480p specifically:**
    ```bash
    ./compressor.sh short_clip.mp4 5 480
    ```

## ⚠️ Important Considerations & Notes

*    codecs:
    *   **H.264 (libx264):** This is the default codec. It offers a good balance between compression quality, encoding speed, and wide compatibility across devices and platforms.
    *   **H.265/HEVC (libx265):** This codec provides significantly better compression than H.264, meaning you can achieve smaller file sizes for the same visual quality, or better quality for the same file size. However, encoding with H.265 is considerably slower and may not be supported by older devices or software.
*   **Two-Pass Encoding:** The script uses a two-pass encoding strategy by default.
    *   **Pass 1:** FFmpeg analyzes the video to gather information about its complexity.
    *   **Pass 2:** FFmpeg uses the data from Pass 1 to make more informed decisions about bitrate allocation during the actual encoding process.
    *   This method generally results in better quality and more accurate file sizes compared to single-pass encoding, especially when targeting a specific size, but it takes roughly twice as long.
*   **Bitrate Thresholds & Automatic Resolution:**
    *   The script uses `BITRATE_THRESHOLD_1080P_TO_720P` (default: 2000 kbps) and `BITRATE_THRESHOLD_720P_TO_480P` (default: 1000 kbps) in 'auto' resolution mode.
    *   If the calculated video bitrate for the current resolution falls below these thresholds, the script will attempt to downscale the video to the next lower standard resolution (e.g., 1080p -> 720p). This is a heuristic to try and preserve acceptable visual quality when the bitrate is too low for a higher resolution.
    *   These thresholds are defined near the top of the script and can be adjusted if you have different preferences.
*   **Pixel Format (`yuvj420p`) and Color Range:**
    *   Some source videos, particularly those from digital cameras or screen recordings, might use the `yuvj420p` pixel format, which implies full-range (JPEG/PC) color levels. Standard video typically uses limited-range (TV) color levels.
    *   The script attempts to handle this by specifying the input color range if `yuvj420p` is detected and sets the output color range to limited (`-color_range 1` or `mpeg`). This, combined with the `format=yuv420p` filter, helps prevent "washed-out" or incorrect colors in the output video.
*   **Minimum Bitrate:**
    *   The script enforces a `MIN_ACCEPTABLE_VIDEO_BITRATE_KBPS` (default: 100 kbps for H.264, 70% of that for H.265). If the calculated video bitrate (after accounting for audio and target file size) falls below this, the script will exit. This is to prevent encoding videos that would likely be of extremely poor quality.
*   **Shell Script Portability:**
    *   The script is written to be POSIX-compliant and uses `#!/bin/dash` (which often links to a more minimal shell than bash). This aims for wider compatibility across different UNIX-like systems. However, slight variations in shell behavior or available utilities could theoretically occur.
*   **Filename Sanitization:** The script does not perform extensive input/output filename sanitization beyond what the shell and FFmpeg handle. Be mindful of special characters in filenames if you encounter issues.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Please feel free to:

*   Report a bug by opening an issue.
*   Suggest a new feature or enhancement by opening an issue.
*   Submit a pull request with improvements to the script or documentation.

If you plan to make significant changes, please open an issue first to discuss what you would like to change.

## 📜 License

This project is currently under [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.en.html).
