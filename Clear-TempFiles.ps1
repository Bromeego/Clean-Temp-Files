# Calling PowerShell as Admin and setting Execution Policy to Bypass to avoid Cannot run Scripts error
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [switch]$Elevated,

    # Non-interactive mode: runs browser and application cache cleanup only (no prompts, no destructive ops)
    [switch]$CacheOnly
)

$ScriptVersion = '2.9.0'

$Script:Config = @{
    DownloadsRetentionDays      = 90
    InetLogRetentionDays        = 30
    System32LogRetentionMonths  = 2
    AzureLogRetentionDays       = 7
    OfficeCacheRetentionDays    = 7
    LFSAgentLogRetentionDays    = 30
    SotiLogRetentionYears       = 1
    CBSLogRetentionDays         = 14
    PantherLogRetentionDays     = 30
    FailedReqLogRetentionDays   = 30
    CTempThresholdBytes         = 500MB
    WUFolderThresholdBytes      = 1.5GB
    CTempPath                   = 'C:\Temp'
    ExcludedUsers               = @(
        'Public',
        'Default',
        'Default User',
        'All Users',
        'defaultuser0'
    )
}

$Script:CleanupStats = @{
    Failed = 0
}

function CheckAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Ask-YesNo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Question,

        [ValidateSet('Y', 'N')]
        [string]$Default = 'N'
    )

    if ($script:NonInteractive) {
        return $Default
    }

    $Answer = Read-Host "$Question (Y/N) [Default: $Default]"

    if ([string]::IsNullOrWhiteSpace($Answer)) {
        return $Default
    }

    if ($Answer -match '^(Y|y)') {
        return 'Y'
    }

    return 'N'
}

function Get-FolderSizeBytes {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return 0
    }

    $Size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum

    if ($null -eq $Size) {
        return 0
    }

    return [double]$Size
}

function Format-Size {
    param (
        [Parameter(Mandatory = $true)]
        [double]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return ('{0:N2} GB' -f ($Bytes / 1GB))
    }
    elseif ($Bytes -ge 1MB) {
        return ('{0:N2} MB' -f ($Bytes / 1MB))
    }
    elseif ($Bytes -ge 1KB) {
        return ('{0:N2} KB' -f ($Bytes / 1KB))
    }
    else {
        return ('{0:N0} Bytes' -f $Bytes)
    }
}

function Remove-FolderContents {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $Items = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue)

    foreach ($Item in $Items) {
        if ($PSCmdlet.ShouldProcess($Item.FullName, 'Remove')) {
            try {
                Remove-Item -Path $Item.FullName -Recurse -Force -ErrorAction Stop -Verbose
            }
            catch {
                $Script:CleanupStats.Failed++
                Write-Verbose "Failed to remove $($Item.FullName): $($_.Exception.Message)"
            }
        }
    }
}

function Remove-OldFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [datetime]$OlderThan,

        [string[]]$Extensions,

        [string]$FullNameMatch,

        [switch]$Recurse
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $Params = @{
        Path        = $Path
        File        = $true
        Force       = $true
        ErrorAction = 'SilentlyContinue'
    }

    if ($Recurse) {
        $Params.Recurse = $true
    }

    $Files = Get-ChildItem @Params | Where-Object { $_.LastWriteTime -lt $OlderThan }

    if ($Extensions) {
        $Files = $Files | Where-Object { $_.Extension -in $Extensions }
    }

    if ($FullNameMatch) {
        $Files = $Files | Where-Object { $_.FullName -match $FullNameMatch }
    }

    foreach ($File in $Files) {
        if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove')) {
            try {
                Remove-Item -Path $File.FullName -Force -ErrorAction Stop -Verbose
            }
            catch {
                $Script:CleanupStats.Failed++
                Write-Verbose "Failed to remove $($File.FullName): $($_.Exception.Message)"
            }
        }
    }
}

function Remove-ItemSafe {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$Recurse
    )

    if (-not (Test-Path $Path)) {
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Remove')) {
        try {
            Remove-Item -Path $Path -Recurse:$Recurse -Force -ErrorAction Stop -Verbose
        }
        catch {
            $Script:CleanupStats.Failed++
            Write-Verbose "Failed to remove ${Path}: $($_.Exception.Message)"
        }
    }
}

function Get-DiskSpaceReport {
    Get-CimInstance -ClassName Win32_LogicalDisk |
        Where-Object { $_.DriveType -eq 3 } |
            Select-Object SystemName,
            @{ Name = 'Drive'; Expression = { $_.DeviceID } },
            @{ Name = 'Size (GB)'; Expression = { '{0:N1}' -f ($_.Size / 1GB) } },
            @{ Name = 'FreeSpace (GB)'; Expression = { '{0:N1}' -f ($_.FreeSpace / 1GB) } },
            @{ Name = 'PercentFree'; Expression = { '{0:P1}' -f ($_.FreeSpace / $_.Size) } } |
                Format-Table -AutoSize |
                    Out-String
}

if ((CheckAdmin) -eq $false) {
    if ($Elevated) {
        Write-Error 'Administrator privileges are required. Elevation was denied or failed.'
        exit 1
    }
    else {
        # Detecting PowerShell (powershell.exe) or PowerShell Core (pwsh)
        if ($IsCoreCLR) {
            $PowerShellCmdLine = 'pwsh.exe'
        }
        else {
            $PowerShellCmdLine = 'powershell.exe'
        }

        $CommandLine = "-NoProfile -ExecutionPolicy Bypass -File `"" + $MyInvocation.MyCommand.Path + "`" " + ($MyInvocation.UnboundArguments -join ' ')
        if ($CacheOnly) {
            $CommandLine += ' -CacheOnly'
        }
        if ($WhatIfPreference) {
            $CommandLine += ' -WhatIf'
        }
        $CommandLine += ' -Elevated'
        Start-Process "$PSHOME\$PowerShellCmdLine" -Verb RunAs -ArgumentList $CommandLine
    }

    exit
}

# Rename Title Window
$host.UI.RawUI.WindowTitle = 'Clean Temp Files'

function Cleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ()
    $script:NonInteractive = $CacheOnly.IsPresent
    $Script:CleanupStats.Failed = 0

    Write-Host -ForegroundColor Cyan "Clean Temp Files v$ScriptVersion`n"

    if ($CacheOnly) {
        Write-Host -ForegroundColor Yellow 'CacheOnly mode: running browser and application cache cleanup only.'
        Write-Host -ForegroundColor Yellow 'Destructive operations and system maintenance tasks are skipped.`n'
    }

    # Set Date for Log
    $LogDate = Get-Date -Format 'MM-d-yy-HHmm'

    # Set Deletion Dates from configuration
    $DelDownloadsDate = (Get-Date).AddDays(-$Script:Config.DownloadsRetentionDays)
    $DelInetLogDate = (Get-Date).AddDays(-$Script:Config.InetLogRetentionDays)
    $System32LogDate = (Get-Date).AddMonths(-$Script:Config.System32LogRetentionMonths)
    $DelAZLogDate = (Get-Date).AddDays(-$Script:Config.AzureLogRetentionDays)
    $DelOfficeCacheDate = (Get-Date).AddDays(-$Script:Config.OfficeCacheRetentionDays)
    $DelLFSAgentLogDate = (Get-Date).AddDays(-$Script:Config.LFSAgentLogRetentionDays)
    $DelSotiLogDate = (Get-Date).AddYears(-$Script:Config.SotiLogRetentionYears)
    $DelCBSLogDate = (Get-Date).AddDays(-$Script:Config.CBSLogRetentionDays)
    $DelPantherLogDate = (Get-Date).AddDays(-$Script:Config.PantherLogRetentionDays)
    $DelFailedReqLogDate = (Get-Date).AddDays(-$Script:Config.FailedReqLogRetentionDays)
    $CTempPath = $Script:Config.CTempPath

    # Prompt options
    $DeleteOldDownloads = Ask-YesNo -Question "Would you like to delete files older than $($Script:Config.DownloadsRetentionDays) days in the Downloads folder for All Users?" -Default 'N'
    $CleanBin = Ask-YesNo -Question 'Would you like to empty the Recycle Bin for All Users?' -Default 'N'
    $CloseBrowsers = Ask-YesNo -Question 'Would you like to close Edge/Chrome/Firefox before cleaning browser cache?' -Default 'N'
    $CleanPrintSpooler = Ask-YesNo -Question 'Would you like to clear the print spooler queue? This will remove stuck print jobs' -Default 'N'

    # C:\Temp handling. Only ask if the folder exists and is larger than the configured threshold.
    $CleanCTemp = 'N'

    if (Test-Path $CTempPath) {
        $CTempSizeBytes = Get-FolderSizeBytes -Path $CTempPath
        $CTempSizeFormatted = Format-Size -Bytes $CTempSizeBytes

        if ($CTempSizeBytes -gt $Script:Config.CTempThresholdBytes) {
            Write-Host -ForegroundColor Yellow "$CTempPath currently contains approximately $CTempSizeFormatted."
            $CleanCTemp = Ask-YesNo -Question "Would you like to clean $CTempPath?" -Default 'N'
        }
        else {
            Write-Host -ForegroundColor Cyan "$CTempPath exists but is only approximately $CTempSizeFormatted. Skipping $CTempPath cleanup."
        }
    }
    else {
        Write-Host -ForegroundColor Cyan "$CTempPath does not exist. Skipping $CTempPath cleanup."
    }

    # Ask the user if they would like to clean the Windows Update folder
    $CleanWU = 'N'

    if (Test-Path "$env:windir\SoftwareDistribution") {
        $WUFolderSizeBytes = Get-FolderSizeBytes -Path "$env:windir\SoftwareDistribution"

        if ($WUFolderSizeBytes -gt $Script:Config.WUFolderThresholdBytes) {
            Write-Host "The Windows Update folder is $(Format-Size -Bytes $WUFolderSizeBytes)"
            $CleanWU = Ask-YesNo -Question 'Do you want to clean the Software Distribution folder and reset Windows Updates?' -Default 'N'
        }
    }

    # Windows.old prompt
    $CleanWindowsOld = 'N'

    if (Test-Path 'C:\Windows.old') {
        $WindowsOldSizeBytes = Get-FolderSizeBytes -Path 'C:\Windows.old'
        Write-Host -ForegroundColor Yellow "C:\Windows.old exists and is approximately $(Format-Size -Bytes $WindowsOldSizeBytes)."
        Write-Host -ForegroundColor Yellow 'Deleting this may prevent rollback to a previous Windows version.'
        $CleanWindowsOld = Ask-YesNo -Question 'Would you like to delete C:\Windows.old?' -Default 'N'
    }

    # Get Disk Size Before
    $Before = Get-DiskSpaceReport

    # Define log file location
    $CleanupLog = "$env:USERPROFILE\Cleanup$LogDate.log"

    # Start Logging
    Start-Transcript -Path "$CleanupLog"

    # Create list of users
    Write-Host -ForegroundColor Green "Getting the list of Users`n"

    $ExcludedUsers = $Script:Config.ExcludedUsers

    $Users = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $ExcludedUsers -notcontains $_.Name } |
            Select-Object -ExpandProperty Name

    # Begin
    Write-Host -ForegroundColor Green "Beginning Script...`n"

    if ($CloseBrowsers -eq 'Y') {
        Write-Host -ForegroundColor Yellow "Closing Edge, Chrome, and Firefox`n"
        taskkill /F /IM msedge.exe 2>$null
        taskkill /F /IM chrome.exe 2>$null
        taskkill /F /IM firefox.exe 2>$null
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Clear Firefox Cache
    Write-Host -ForegroundColor Green "Clearing Firefox Cache`n"
    foreach ($User in $Users) {
        $FirefoxProfilePath = "C:\Users\$User\AppData\Local\Mozilla\Firefox\Profiles"

        if (Test-Path $FirefoxProfilePath) {
            Remove-FolderContents -Path "$FirefoxProfilePath\*\cache"
            Remove-FolderContents -Path "$FirefoxProfilePath\*\cache2\entries"
            Remove-FolderContents -Path "$FirefoxProfilePath\*\thumbnails"
            Remove-FolderContents -Path "$FirefoxProfilePath\*\OfflineCache"

            # Skipping Firefox cookies/local storage to avoid signing users out of websites:
            # cookies.sqlite
            # webappsstore.sqlite
            # chromeappsstore.sqlite
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Google Chrome Cache
    Write-Host -ForegroundColor Green "Clearing Google Chrome Cache`n"
    foreach ($User in $Users) {
        $ChromeUserData = "C:\Users\$User\AppData\Local\Google\Chrome\User Data"

        if (Test-Path $ChromeUserData) {
            Remove-FolderContents -Path "$ChromeUserData\Default\Cache"
            Remove-FolderContents -Path "$ChromeUserData\Default\Cache2\entries"
            Remove-FolderContents -Path "$ChromeUserData\Default\Media Cache"
            Remove-FolderContents -Path "$ChromeUserData\Default\JumpListIconsOld"

            # Skipping Chrome Cookies and Cookies-Journal to avoid signing users out of websites.

            # Comment out the following line to remove the Chrome Write Font Cache too.
            # Remove-FolderContents -Path "$ChromeUserData\Default\ChromeDWriteFontCache"

            # Check Chrome Profiles. It looks as though when creating profiles, it just numbers them Profile 1, Profile 2 etc.
            $Profiles = Get-ChildItem -Path $ChromeUserData -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'Profile*' }

            foreach ($BrowserProfile in $Profiles) {
                Remove-FolderContents -Path "$ChromeUserData\$($BrowserProfile.Name)\Cache"
                Remove-FolderContents -Path "$ChromeUserData\$($BrowserProfile.Name)\Cache2\entries"
                Remove-FolderContents -Path "$ChromeUserData\$($BrowserProfile.Name)\Media Cache"
                Remove-FolderContents -Path "$ChromeUserData\$($BrowserProfile.Name)\JumpListIconsOld"

                # Skipping Chrome profile Cookies and Cookies-Journal to avoid signing users out of websites.
            }
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Internet Explorer & Old Edge Cache
    Write-Host -ForegroundColor Yellow "Clearing Internet Explorer & Old Edge Cache`n"
    foreach ($User in $Users) {
        Remove-FolderContents -Path "C:\Users\$User\AppData\Local\Microsoft\Windows\Temporary Internet Files"
        Remove-FolderContents -Path "C:\Users\$User\AppData\Local\Microsoft\Windows\INetCache"
        Remove-FolderContents -Path "C:\Users\$User\AppData\Local\Microsoft\Windows\WebCache"
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Edge Chromium Cache
    Write-Host -ForegroundColor Yellow "Clearing Edge Chromium Cache`n"
    foreach ($User in $Users) {
        $EdgeUserData = "C:\Users\$User\AppData\Local\Microsoft\Edge\User Data"

        if (Test-Path $EdgeUserData) {
            Remove-FolderContents -Path "$EdgeUserData\Default\Cache"

            # Skipping Edge Cookies and Cookies-Journal to avoid signing users out of websites.

            # Comment out the following line to remove the Edge Write Font Cache too.
            # Remove-FolderContents -Path "$EdgeUserData\Default\EdgeDWriteFontCache"

            # Check Edge Profiles. It looks as though when creating profiles, it just numbers them Profile 1, Profile 2 etc.
            $Profiles = Get-ChildItem -Path $EdgeUserData -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'Profile*' }

            foreach ($BrowserProfile in $Profiles) {
                Remove-FolderContents -Path "$EdgeUserData\$($BrowserProfile.Name)\Cache"

                # Skipping Edge profile Cookies and Cookies-Journal to avoid signing users out of websites.
            }
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Chromium
    Write-Host -ForegroundColor Yellow "Clearing Chromium Cache`n"
    foreach ($User in $Users) {
        $ChromiumPath = "C:\Users\$User\AppData\Local\Chromium\User Data\Default"

        if (Test-Path $ChromiumPath) {
            Remove-FolderContents -Path "$ChromiumPath\Cache"
            Remove-FolderContents -Path "$ChromiumPath\GPUCache"
            Remove-FolderContents -Path "$ChromiumPath\Media Cache"
            Remove-FolderContents -Path "$ChromiumPath\Pepper Data"
            Remove-FolderContents -Path "$ChromiumPath\Application Cache"
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Opera
    Write-Host -ForegroundColor Yellow "Clearing Opera Cache`n"
    foreach ($User in $Users) {
        $OperaCache = "C:\Users\$User\AppData\Local\Opera Software\Opera Stable\Cache"
        Remove-FolderContents -Path $OperaCache
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Yandex
    Write-Host -ForegroundColor Yellow "Clearing Yandex Cache`n"
    foreach ($User in $Users) {
        $YandexPath = "C:\Users\$User\AppData\Local\Yandex\YandexBrowser\User Data\Default"
        $YandexTemp = "C:\Users\$User\AppData\Local\Yandex\YandexBrowser\Temp"

        if (Test-Path $YandexPath) {
            Remove-FolderContents -Path "$YandexPath\Cache"
            Remove-FolderContents -Path "$YandexPath\GPUCache"
            Remove-FolderContents -Path "$YandexPath\Media Cache"
            Remove-FolderContents -Path "$YandexPath\Pepper Data"
            Remove-FolderContents -Path "$YandexPath\Application Cache"
        }

        Remove-FolderContents -Path $YandexTemp
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Delivery Optimization Cache
    $DeliveryOptimizationPath = "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"

    if (Test-Path $DeliveryOptimizationPath) {
        Write-Host -ForegroundColor Yellow "Clearing Delivery Optimization Cache`n"
        Remove-FolderContents -Path $DeliveryOptimizationPath
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    if (-not $CacheOnly) {
    # Clear User Temp Folders
    Write-Host -ForegroundColor Yellow "Clearing User Temp Folders`n"
    foreach ($User in $Users) {
        Remove-FolderContents -Path "C:\Users\$User\AppData\Local\Temp"
        Remove-FolderContents -Path "C:\Users\$User\AppData\Local\Microsoft\Windows\WER"
        Remove-FolderContents -Path "C:\Users\$User\AppData\Local\Microsoft\Windows\AppCache"
        Remove-FolderContents -Path "C:\Users\$User\AppData\Local\CrashDumps"
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Windows Temp Folders
    Write-Host -ForegroundColor Yellow "Clearing Windows Temp Folders`n"

    if ($CleanCTemp -eq 'Y') {
        if (Test-Path $CTempPath) {
            Write-Host -ForegroundColor Yellow "Clearing $CTempPath`n"
            Remove-FolderContents -Path $CTempPath
        }
        else {
            Write-Host -ForegroundColor Cyan "$CTempPath does not exist. Skipping $CTempPath cleanup.`n"
        }
    }
    else {
        Write-Host -ForegroundColor Cyan "Skipping $CTempPath cleanup`n"
    }

    Remove-FolderContents -Path "$env:windir\Temp"
    Remove-FolderContents -Path "$env:ProgramData\Microsoft\Windows\WER"

    # CBS logs can be actively used, so only delete older files.
    if (Test-Path "$env:windir\Logs\CBS") {
        Write-Host -ForegroundColor Yellow "Deleting CBS logs older than $($Script:Config.CBSLogRetentionDays) days`n"
        Remove-OldFiles -Path "$env:windir\Logs\CBS" -OlderThan $DelCBSLogDate -Recurse
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Only grab log files sitting in the root of the LogFiles directory
    Remove-OldFiles -Path "$env:windir\System32\LogFiles" -OlderThan $System32LogDate -Extensions '.log'

    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Windows memory dump files
    Write-Host -ForegroundColor Yellow "Clearing Windows memory dump files`n"
    Remove-ItemSafe -Path "$env:windir\MEMORY.DMP"
    Remove-FolderContents -Path "$env:windir\Minidump"
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear old Windows setup / Panther logs
    Write-Host -ForegroundColor Yellow "Clearing old Windows setup / Panther logs`n"

    $PantherPaths = @(
        "$env:windir\Panther",
        "$env:windir\inf"
    )

    foreach ($Path in $PantherPaths) {
        if (Test-Path $Path) {
            Remove-OldFiles -Path $Path -OlderThan $DelPantherLogDate -Extensions '.log', '.etl'
        }
    }

    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Inetpub Logs Folder
    if (Test-Path 'C:\inetpub\logs\LogFiles\') {
        Write-Host -ForegroundColor Yellow "Clearing Inetpub Logs Folder`n"
        Remove-OldFiles -Path 'C:\inetpub\logs\LogFiles\' -OlderThan $DelInetLogDate -Recurse
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Clear IIS Failed Request Logs Folder
    if (Test-Path 'C:\inetpub\logs\FailedReqLogFiles') {
        Write-Host -ForegroundColor Yellow "Clearing IIS Failed Request Logs older than 30 days`n"
        Remove-OldFiles -Path 'C:\inetpub\logs\FailedReqLogFiles' -OlderThan $DelFailedReqLogDate -Recurse
        Write-Host -ForegroundColor Yellow "Done...`n"
    }
    }

    # Delete Microsoft Teams Previous Version files
    Write-Host -ForegroundColor Yellow "Clearing Teams Previous Version`n"
    foreach ($User in $Users) {
        $TeamsPath = "C:\Users\$User\AppData\Local\Microsoft\Teams"

        if (Test-Path $TeamsPath) {
            Remove-FolderContents -Path "$TeamsPath\previous"
            Remove-FolderContents -Path "$TeamsPath\stage"
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Delete SnagIt Crash Dump files
    Write-Host -ForegroundColor Yellow "Clearing SnagIt Crash Dumps`n"
    foreach ($User in $Users) {
        $SnagitPath = "C:\Users\$User\AppData\Local\TechSmith\SnagIt"

        if (Test-Path $SnagitPath) {
            Remove-FolderContents -Path "$SnagitPath\CrashDumps"
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Dropbox
    Write-Host -ForegroundColor Yellow "Clearing Dropbox Cache`n"
    foreach ($User in $Users) {
        Remove-FolderContents -Path "C:\Users\$User\Dropbox\.dropbox.cache"
        Remove-FolderContents -Path "C:\Users\$User\Dropbox*\.dropbox.cache"
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Delete files older than 90 days from Downloads folder
    if ($DeleteOldDownloads -eq 'Y') {
        Write-Host -ForegroundColor Yellow "Deleting files older than $($Script:Config.DownloadsRetentionDays) days from User Downloads folder`n"

        foreach ($User in $Users) {
            $UserDownloads = "C:\Users\$User\Downloads"

            if (Test-Path $UserDownloads) {
                Remove-OldFiles -Path $UserDownloads -OlderThan $DelDownloadsDate -Recurse
            }
        }

        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete files older than 7 days from Office Cache Folder
    Write-Host -ForegroundColor Yellow "Clearing Office Cache Folder`n"
    foreach ($User in $Users) {
        $OfficeCache = "C:\Users\$User\AppData\Local\Microsoft\Office\16.0\GrooveFileCache"

        if (Test-Path $OfficeCache) {
            Remove-OldFiles -Path $OfficeCache -OlderThan $DelOfficeCacheDate -Recurse
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    if (-not $CacheOnly) {
    # Clear HP Support Assistant Installation Folder
    if (Test-Path 'C:\swsetup') {
        Write-Host -ForegroundColor Yellow "Clearing HP Support Assistant Installation Folder C:\swsetup`n"
        Remove-ItemSafe -Path 'C:\swsetup' -Recurse
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Clear HP Support Framework SoftPaq Cache
    $HPSoftPaqPath = 'C:\ProgramData\HP\HP Support Framework\Softpaq'

    if (Test-Path $HPSoftPaqPath) {
        Write-Host -ForegroundColor Yellow "Clearing HP Support Framework SoftPaq Cache`n"

        # Keep the SoftPaq folder itself, but remove any files/folders inside it.
        Remove-FolderContents -Path $HPSoftPaqPath

        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete files older than 7 days from Azure Log folder
    if (Test-Path 'C:\WindowsAzure\Logs') {
        Write-Host -ForegroundColor Yellow "Deleting files older than 7 days from Azure Log folder`n"
        Remove-OldFiles -Path 'C:\WindowsAzure\Logs' -OlderThan $DelAZLogDate -Recurse
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete files older than 30 days from LFSAgent Log folder https://www.lepide.com/
    if (Test-Path "$env:windir\LFSAgent\Logs") {
        Write-Host -ForegroundColor Yellow "Deleting files older than 30 days from LFSAgent Log folder`n"
        Remove-OldFiles -Path "$env:windir\LFSAgent\Logs" -OlderThan $DelLFSAgentLogDate -Recurse
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete SOTI MobiController Log files older than 1 year
    if (Test-Path 'C:\Program Files (x86)\SOTI\MobiControl') {
        Write-Host -ForegroundColor Yellow "Deleting SOTI MobiController Log files older than 1 year`n"

        $SotiLogFiles = Get-ChildItem -Path 'C:\Program Files (x86)\SOTI\MobiControl' -File -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -like '*Device*.log' -or $_.Name -like '*Server*.log') -and
                ($_.LastWriteTime -lt $DelSotiLogDate)
            }

        foreach ($File in $SotiLogFiles) {
            Remove-Item -Path $File.FullName -Force -ErrorAction SilentlyContinue -Verbose
        }

        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete old Cylance Log files
    if (Test-Path 'C:\Program Files\Cylance\Desktop') {
        Write-Host -ForegroundColor Yellow "Deleting Old Cylance Log files`n"

        $OldCylanceLogFiles = Get-ChildItem -Path 'C:\Program Files\Cylance\Desktop' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'cylog-*.log' }

        foreach ($File in $OldCylanceLogFiles) {
            Remove-Item -Path $File.FullName -Force -ErrorAction SilentlyContinue -Verbose
        }

        Write-Host -ForegroundColor Yellow "Done...`n"
    }
    }

    # Clear print spooler queue if requested
    if ($CleanPrintSpooler -eq 'Y') {
        Write-Host -ForegroundColor Yellow "Clearing print spooler queue`n"

        try {
            Stop-Service Spooler -Force -ErrorAction Stop
            Remove-FolderContents -Path "$env:windir\System32\spool\PRINTERS"
            Start-Service Spooler -ErrorAction Stop
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Warning "$ErrorMessage"

            try {
                Start-Service Spooler -ErrorAction SilentlyContinue
            }
            catch {
                # Ignore secondary failure
            }
        }

        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete Windows.old if requested
    if ($CleanWindowsOld -eq 'Y') {
        if (Test-Path 'C:\Windows.old') {
            Write-Host -ForegroundColor Yellow "Deleting C:\Windows.old`n"
            Remove-ItemSafe -Path 'C:\Windows.old' -Recurse
            Write-Host -ForegroundColor Yellow "Done...`n"
        }
    }

    # Delete Windows Updates Folder SoftwareDistribution and reset the Windows Update Service
    if ($CleanWU -eq 'Y') {
        Write-Host -ForegroundColor Yellow "Restarting Windows Update Service and Deleting SoftwareDistribution Folder`n"

        try {
            Stop-Service -Name wuauserv -Force -ErrorAction Stop
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Warning "$ErrorMessage"
        }

        Remove-ItemSafe -Path "$env:windir\SoftwareDistribution" -Recurse
        Start-Sleep -Seconds 3

        try {
            Start-Service -Name wuauserv -ErrorAction Stop
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Warning "$ErrorMessage"
        }

        Write-Host -ForegroundColor Yellow 'Done...'
        Write-Host -ForegroundColor Yellow "Please rerun Windows Update to pull down the latest updates`n"
    }

    # Empty Recycle Bin
    if ($CleanBin -eq 'Y') {
        Write-Host -ForegroundColor Green "Cleaning Recycle Bin`n"

        $RecycleBin = "C:\`$Recycle.Bin"
        $BinFolders = Get-ChildItem $RecycleBin -Directory -Force -ErrorAction SilentlyContinue

        foreach ($Folder in $BinFolders) {
            # Translate the SID to a User Account
            try {
                $ObjSID = New-Object System.Security.Principal.SecurityIdentifier ($Folder.Name)
                $ObjUser = $ObjSID.Translate([System.Security.Principal.NTAccount])
                Write-Host -ForegroundColor Yellow -BackgroundColor Black "Cleaning $ObjUser Recycle Bin"
            }
            catch {
                $ObjUser = $Folder.Name
                Write-Host -ForegroundColor Yellow -BackgroundColor Black "Cleaning $ObjUser Recycle Bin"
            }

            # Force array output so += does not fail when only one file is returned
            $Files = @(
                Get-ChildItem $Folder.FullName -File -Recurse -Force -ErrorAction SilentlyContinue
            )

            $Directories = @(
                Get-ChildItem $Folder.FullName -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending
            )

            $ItemsToDelete = @($Files + $Directories)
            $ItemTotal = $ItemsToDelete.Count

            if ($ItemTotal -eq 0) {
                Write-Host -ForegroundColor Cyan "Recycle Bin is already empty for $ObjUser`n"
                continue
            }

            for ($i = 1; $i -le $ItemTotal; $i++) {
                $Item = $ItemsToDelete[($i - 1)]

                Write-Progress `
                    -Activity "Recycle Bin Clean-up" `
                    -Status "Attempting to Delete Item [$i / $ItemTotal]: $($Item.FullName)" `
                    -PercentComplete (($i / $ItemTotal) * 100) `
                    -Id 1

                if ($PSCmdlet.ShouldProcess($Item.FullName, 'Remove')) {
                    try {
                        Remove-Item -Path $Item.FullName -Recurse -Force -ErrorAction Stop
                    }
                    catch {
                        $Script:CleanupStats.Failed++
                        Write-Verbose "Failed to remove $($Item.FullName): $($_.Exception.Message)"
                    }
                }
            }

            Write-Progress -Activity "Recycle Bin Clean-up" -Status "Complete" -Completed -Id 1
        }

        Write-Host -ForegroundColor Green "Done`n `n"
    }

    Write-Host -ForegroundColor Green "All Tasks Done!`n`n"

    # Get Drive size after clean
    $After = Get-DiskSpaceReport

    # Report WinSxS and Installer folder sizes
    $WinSxSPath = "$env:windir\WinSxS"
    $InstallerPath = "$env:windir\Installer"

    $WinSxSSizeBytes = Get-FolderSizeBytes -Path $WinSxSPath
    $InstallerSizeBytes = Get-FolderSizeBytes -Path $InstallerPath

    Write-Host -ForegroundColor Green "Before: $Before"
    Write-Host -ForegroundColor Green "After: $After"

    Write-Host -ForegroundColor Cyan "`nAdditional folder size report:"
    Write-Host -ForegroundColor Cyan "$WinSxSPath size: $(Format-Size -Bytes $WinSxSSizeBytes)"
    Write-Host -ForegroundColor Cyan "$InstallerPath size: $(Format-Size -Bytes $InstallerSizeBytes)"

    Write-Host -ForegroundColor Yellow "`nDo NOT manually delete files from WinSxS or Installer."
    Write-Host -ForegroundColor Yellow 'If WinSxS is large, consider running the following command from an elevated PowerShell or Command Prompt:'
    Write-Host -ForegroundColor Yellow 'Dism.exe /Online /Cleanup-Image /StartComponentCleanup'
    Write-Host -ForegroundColor Yellow "This can take some time, especially on older machines or servers.`n"

    # Another reminder about running Windows update if needed as it would get lost in all the scrolling text.
    if ($CleanWU -eq 'Y') {
        Write-Host -ForegroundColor Yellow "`nPlease rerun Windows Update to pull down the latest updates.`n"
    }

    if ($Script:CleanupStats.Failed -gt 0) {
        Write-Host -ForegroundColor Yellow "`nCleanup completed with $($Script:CleanupStats.Failed) item(s) that could not be removed (locked, in use, or access denied)."
        Write-Host -ForegroundColor Yellow 'Check the transcript log for verbose details.`n'
    }

    # Read some of the output before going away
    if (-not $CacheOnly) {
        Start-Sleep -Seconds 15

        # Open Text File
        Invoke-Item $CleanupLog
    }
    else {
        Write-Host -ForegroundColor Cyan "Transcript saved to: $CleanupLog"
    }

    # Stop Transcript
    Stop-Transcript
}

Cleanup
