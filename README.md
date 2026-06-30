# Clean Browser Cache and Recycle Bin

A PowerShell script for Windows that frees disk space by clearing browser caches, temp folders, logs, and vendor-specific caches. Originally created by [Lemtek](https://github.com/lemtek/Powershell/blob/master/Clear_Browser_Caches) and maintained by [Bromeego](https://github.com/Bromeego/Clean-Temp-Files) with contributions from the community.

**Current version: 2.9.0**

## Requirements

- Windows 10 or later (Windows Server supported for many tasks)
- Administrator privileges (the script self-elevates via UAC)
- Windows PowerShell 5.1 or PowerShell 7 (`pwsh`)

## Usage

### Interactive (default)

Right-click PowerShell and choose **Run as Administrator**, then:

```powershell
Set-Location C:\path\to\Clean-Temp-Files
powershell.exe -ExecutionPolicy Bypass -File .\Clear-TempFiles.ps1
```

The script prompts for UAC elevation if not already running as admin. Destructive operations default to **No**.

### Cache-only mode (non-interactive)

For scheduled tasks or unattended runs that should only clear browser and application caches:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Clear-TempFiles.ps1 -CacheOnly
```

This skips all prompts and runs **Tier 1** cleanup only (see below). No recycle bin, Downloads purge, `Windows.old`, or system maintenance.

### Preview changes (WhatIf)

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Clear-TempFiles.ps1 -WhatIf
```

Shows what would be removed without deleting anything.

## Cleanup tiers

### Tier 1 — runs automatically (or with `-CacheOnly`)

- Browser caches: Firefox, Chrome, Edge, IE/legacy Edge, Chromium, Opera, Yandex
- Delivery Optimization cache
- Microsoft Teams `previous` / `stage` folders
- SnagIt crash dumps
- Dropbox cache
- Office GrooveFileCache (files older than 7 days)

Cookies and local storage are **not** cleared, so users stay signed in to websites.

### Tier 2 — runs in full mode only (no prompt)

- User `%TEMP%`, WER, AppCache, CrashDumps
- `%windir%\Temp`, ProgramData WER
- CBS logs (older than 14 days), System32 LogFiles (older than 2 months)
- Memory dumps, Panther/setup logs, IIS logs
- HP `C:\swsetup`, HP SoftPaq cache
- Azure VM logs, LFSAgent logs, SOTI MobiControl logs, Cylance logs

### Tier 3 — prompted (default: No)

- Downloads files older than 90 days (all users)
- Empty all users' recycle bins
- Force-close Edge/Chrome/Firefox before cache cleanup
- Clear print spooler queue
- Clean `C:\Temp` (only if folder exists and exceeds 500 MB)
- Reset Windows Update (`SoftwareDistribution`) if folder exceeds 1.5 GB
- Delete `C:\Windows.old`

## Configuration

Retention windows and thresholds are defined at the top of `Clear-TempFiles.ps1` in the `$Script:Config` hashtable. For example, to change Downloads retention from 90 days:

```powershell
DownloadsRetentionDays = 90   # change this value in $Script:Config
```

## Logging

A transcript is saved to `%USERPROFILE%\Cleanup{date}.log` and opened when the script finishes.

## Warnings

- This is an **admin tool**. Run only on systems you manage and understand.
- Tier 2 actions include deleting security product logs (Cylance) and forensic artifacts (memory dumps, WER).
- Force-closing browsers may cause unsaved tab data loss.
- Deleting `C:\Windows.old` prevents rollback to a previous Windows version.
- Locked or in-use files are skipped; a summary is shown at the end if any removals failed.

## Changelog

### v2.9.0

- Added script version, centralized configuration (`$Script:Config`)
- Added `-CacheOnly` for non-interactive cache cleanup
- Added `-WhatIf` support for previewing removals
- Replaced deprecated `Get-WmiObject` with `Get-CimInstance`
- Fixed silent exit when elevation fails
- Fixed recycle bin section indentation
- Added failure summary for items that could not be removed
- Expanded README with usage, tiers, and warnings
- Added MIT license

### v2.8.2

- Added cleaning of Windows Error Reporting and CBS (Component-Based Servicing) folders

### v2.8.1

- Added cleaning of Inetpub logfiles directory
- Added cleaning of user CrashDumps directory

### v2.8

- Added cleaning of Microsoft Teams previous version folder
- Added Dropbox cache cleaning - Found on [bluPhy](https://github.com/bluPhy/Clean-Temp-Files) - Thanks!
- Added SnagIt CrashDump cleaning
- Added Yandex Browser
- Added another Cache folder for Internet Explorer/Edge
- Added clearing of Firefox OfflineCache folder
- Added deleting of files older than 90 days within User\Downloads Folder
- Removed unneeded command from Firefox cleaning
- Fixed command for Firefox cleaning
- Split Internet Explorer, User Temp Folders, Opera and Chromium to their own sections
- Split Opera and Chromium sections into their own
- Renamed Internet Explorer section to Internet Explorer & Edge
- Expanded the -EA parameter to read the full name
- Fixed output error on line 37 - Found on [bluPhy](https://github.com/bluPhy/Clean-Temp-Files) - Thanks!
- Updated README.md with proper formatting

### v2.7

- Borrowed Chromium and Opera Cleaning - Credit [Anst-foto](https://github.com/anst-foto/Powershell)
- Redone Recycle Bin cleaning. Will ask for confirmation at the start of the script then will clean All Users Recycle Bin - Credit [Chris Rakowitz](https://community.spiceworks.com/scripts/show_download/3677-empty-recycle-bins)
- Translate SID to User account when running the Recycle Bin Cleaning for nicer output. If SID cannot be translated then just show SID

### v2.6

- Fixes from Github which were not pulled from Master
- Fixed C:\users\\%username% could not be found if the profiledir points to another directory - Credit [Mahagon](https://github.com/Mahagon/Powershell)
- Amend Clear Internet Explorer Output - Credit [Watnabe](https://github.com/Watnabe/Powershell)

### v2.5

- Added Disk Size, Free Space, % Free. Before and After - Code Borrowed from [Technet Article](https://gallery.technet.microsoft.com/scriptcenter/Clean-up-your-C-Drive-bc7bb3ed)
- Write to Text File
- Tabbed in code, cleaner to read
- Updated Alias' to Full Content for easier maintenance

### v2.4

- Resolved *.default issue, issue was with the file path name not with *.default, but issue resolved

### v2.3

- Added Cache2 to Mozilla directories but found that *.default is not working

### v2.2

- Added Cyan colour to verbose output

### v2.1

- Added the location 'C:\Windows\Temp\*' and 'C:\`$recycle.bin\'

### v2

- Changed the retrieval of user list to dir the c:\users folder and export to csv

### v1

- Compiled script
