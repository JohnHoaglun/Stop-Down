# Version Locations

## Current values

| Value | Current | Authority | Locations |
| --- | --- | --- | --- |
| Marketing version | 1.0 | Xcode build setting | `Stop-Down` target `MARKETING_VERSION` |
| Build number | 7 | Xcode build setting | `Stop-Down` target `CURRENT_PROJECT_VERSION` |

`GENERATE_INFOPLIST_FILE` is `YES`, so `CFBundleShortVersionString` and `CFBundleVersion` are derived from the build settings; there is no separate hand-maintained `Info.plist` version. Increase the build number once per completed file-changing delivery; change marketing version only for intentional releases.
