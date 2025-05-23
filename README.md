# Changelang

Changelang is a cli tool to change the default language/audio track for media.

Invoke with a media file as an argument:

```
> changelang media.mkv
```

changelang will list the audio tracks and denote the default track with an asterisk, and list the language and other details for each audio track. 
It then prompts the user for the new default audio track, which you can specify via number. The file is changed in-place to have a new default language. If no number is specified, the file is not changed.

```
[1] * (fra): opus, 48000 Hz, 5.1, fltp
[2]   (eng): opus, 48000 Hz, 5.1, fltp

Set default: 
```

When passed an optional `-l <language code>`, e.g. `-l eng`, changelang will set the default language of the file to the first audio track that matches the selected language. If no audio track matches the indicated language, no change is made.