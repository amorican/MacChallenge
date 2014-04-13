# MacChallenge

A coding exercise: Build a Mac OS video recorder application.

## Requirements

https://docs.google.com/document/d/1VuIzReoE81YoKl4Be2z0TcBEphqxEsxZXU0G5v-yWnw/edit

## Notes

1. There is no specific requirement on how/when the output may be saved, for a simple solution the save panel is displayed upon stopping a recording. Also, the app will open the output file in an external app when it’s saved.

2. The output composed video (i.e. captured video/audio plus caption) is generated and saved in an asynchronous process after the user clicks “Save” on the Save panel. I have added a progress indicator in the upper right hand corner of the app window so the user knows when the export process is still running.
