# Changelang

CLI tool to change default audio/subtitle tracks in media files.

**Usage:**
`changelang <file> [-a <lang|0>] [-s <lang|0>]`

*   `<file>`: Path to media file.
*   `-a <lang|0>`: Set default audio to language `lang`. `0` clears default audio.
*   `-s <lang|0>`: Set default subtitle to language `lang`. `0` clears default subtitle.

If no -a or -s parameters are passed, `changelang` will lists audio and subtitle tracks and prompt for new defaults in turn.

**Examples:**
*   `changelang media.mkv` (Interactive mode)
*   `changelang media.mkv -a eng -s jpn` (Set English audio, Japanese subtitle)
*   `changelang media.mkv -s 0` (Clear default subtitle)

## changeall.sh

A simple wrapper to:
* `find` files in current directory tree with a given extention, 
* for each file: run `changelang`, applying the rest of `changeall.sh`'s arguments

**Example**
* `changeall.sh mkv -s 0` (Clear subtitles for all mkv files in the current directory tree)
