#Calling Powershell as Admin and setting Execution Policy to Bypass to avoid Cannot run Scripts error
([switch]$Elevated)
function CheckAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if ((CheckAdmin) -eq $false) {
    if ($elevated) {
        # could not elevate, quit
    }
    else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -ExecutionPolicy Bypass -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition)) | Out-Null
    }
    Exit
}

# Rename Title Window
$host.ui.RawUI.WindowTitle = "Clean Browser Temp Files"

Function Cleanup {
    # Set Date for Log
    $LogDate = Get-Date -Format "MM-d-yy-HHmm"

    # Ask for confirmation to delete users Downloaded files - Anything older than 90 days
    $DeleteOldDownloads = Read-Host "Would you like to delete files older than 90 days in the Downloads folder for All Users? (Y/N)"
    
    # Set Deletion Date for Downloads Folder
    $DelDownloadsDate = (Get-Date).AddDays(-90)

    # Set Deletion Date for Inetpub Log Folder
    $DelInetLogDate = (Get-Date).AddDays(-30)

    # Set Deletion Date for System32 Log Folder
    $System32LogDate = (Get-Date).AddMonths(-2)

    # Set Deletion Date for Azure Logs Folder
    $DelAZLogDate = (Get-Date).AddDays(-7)

    # Set Deletion Date for Office File Cache Folder
    $DelOfficeCacheDate = (Get-Date).AddDays(-7)

    # Set Deletion Date for LFSAgent Logs Folder
    $DelLFSAGentLogDate = (Get-Date).AddDays(-30)

    # Set Deletion Date for SotiMobicontroller Logs
    $DelSotiLogDate = (Get-Date).AddYears(-1)

    # Ask for Confirmation to Empty Recycle Bin for All Users
    $CleanBin = Read-Host "Would you like to empty the Recycle Bin for All Users? (Y/N)"

    # Get the size of the Windows Updates folder (SoftwareDistribution)
    $WUfoldersize = (Get-ChildItem "C:\Windows\SoftwareDistribution" -Recurse | Measure-Object Length -s).sum / 1Gb

    # Ask the user if they would like to clean the Windows Update folder
    if ($WUfoldersize -gt 1.5) {
        Write-Host "The Windows Update folder is" ("{0:N2} GB" -f $WUFoldersize)
        $CleanWU = Read-Host "Do you want clean the Software Distribution folder and reset Windows Updates? (Y/N)"
    }

    # Get Disk Size
    $Before = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq "3" } | Select-Object SystemName,
    @{ Name = "Drive" ; Expression = { ( $_.DeviceID ) } },
    @{ Name = "Size (GB)" ; Expression = { "{0:N1}" -f ( $_.Size / 1gb) } },
    @{ Name = "FreeSpace (GB)" ; Expression = { "{0:N1}" -f ( $_.Freespace / 1gb ) } },
    @{ Name = "PercentFree" ; Expression = { "{0:P1}" -f ( $_.FreeSpace / $_.Size ) } } |
    Format-Table -AutoSize | Out-String

    # Define log file location
    $Cleanuplog = "C:\users\$env:USERNAME\Cleanup$LogDate.log"

    # Start Logging
    Start-Transcript -Path "$CleanupLog"

    # Create list of users
    Write-Host -ForegroundColor Green "Getting the list of Users`n"
    $Users = Get-ChildItem "C:\Users" | Select-Object Name
    $users = $Users.Name 

    # Begin!
    Write-Host -ForegroundColor Green "Beginning Script...`n"

    # Clear Firefox Cache
    Write-Host -ForegroundColor Green "Clearing Firefox Cache`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles") {
            Remove-Item -Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles\*\cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles\*\cache2\entries\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles\*\thumbnails\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles\*\cookies.sqlite" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles\*\webappsstore.sqlite" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles\*\chromeappsstore.sqlite" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Mozilla\Firefox\Profiles\*\OfflineCache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        }
        Write-Host -ForegroundColor Yellow "Done...`n"
    }
    # Clear Google Chrome
    Write-Host -ForegroundColor Green "Clearing Google Chrome Cache`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data") {
            Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default\Cache2\entries\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default\Cookies" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default\Media Cache" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default\Cookies-Journal" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default\JumpListIconsOld" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            # Comment out the following line to remove the Chrome Write Font Cache too.
            # Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default\ChromeDWriteFontCache" -Recurse -Force -ErrorAction SilentlyContinue -Verbose

            # Check Chrome Profiles. It looks as though when creating profiles, it just numbers them Profile 1, Profile 2 etc.
            $Profiles = Get-ChildItem -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data" | Select-Object Name | Where-Object Name -Like "Profile*"
            foreach ($Account in $Profiles) {
                $Account = $Account.Name 
                Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\$Account\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
                Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\$Account\Cache2\entries\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose 
                Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\$Account\Cookies" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
                Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\$Account\Media Cache" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
                Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\$Account\Cookies-Journal" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
                Remove-Item -Path "C:\Users\$user\AppData\Local\Google\Chrome\User Data\$Account\JumpListIconsOld" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            }
        }
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Clear Internet Explorer & Edge
    Write-Host -ForegroundColor Yellow "Clearing Internet Explorer & Edge Cache`n"
    Foreach ($user in $Users) {
        Remove-Item -Path "C:\Users\$user\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        Remove-Item -Path "C:\Users\$user\AppData\Local\Microsoft\Windows\INetCache\* " -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        Remove-Item -Path "C:\Users\$user\AppData\Local\Microsoft\Windows\WebCache\* " -Recurse -Force -ErrorAction SilentlyContinue -Verbose
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Chromium
    Write-Host -ForegroundColor Yellow "Clearing Chromium Cache`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\AppData\Local\Chromium") {
            Remove-Item -Path "C:\Users\$user\AppData\Local\Chromium\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Chromium\User Data\Default\GPUCache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Chromium\User Data\Default\Media Cache" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Chromium\User Data\Default\Pepper Data" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Chromium\User Data\Default\Application Cache" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        }
        Write-Host -ForegroundColor Yellow "Done...`n" 
    }
    
    # Clear Opera
    Write-Host -ForegroundColor Yellow "Clearing Opera Cache`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\AppData\Local\Opera Software") {
            Remove-Item -Path "C:\Users\$user\AppData\Local\Opera Software\Opera Stable\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        } 
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Clear Yandex
    Write-Host -ForegroundColor Yellow "Clearing Yandex Cache`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\AppData\Local\Yandex") {
            Remove-Item -Path "C:\Users\$user\AppData\Local\Yandex\YandexBrowser\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Yandex\YandexBrowser\User Data\Default\GPUCache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Yandex\YandexBrowser\User Data\Default\Media Cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Yandex\YandexBrowser\User Data\Default\Pepper Data\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Yandex\YandexBrowser\User Data\Default\Application Cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Yandex\YandexBrowser\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        } 
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Clear User Temp Folders
    Write-Host -ForegroundColor Yellow "Clearing User Temp Folders`n"
    Foreach ($user in $Users) {
        Remove-Item -Path "C:\Users\$user\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        Remove-Item -Path "C:\Users\$user\AppData\Local\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        Remove-Item -Path "C:\Users\$user\AppData\Local\Microsoft\Windows\AppCache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        Remove-Item -Path "C:\Users\$user\AppData\Local\CrashDumps\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Windows Temp Folder
    Write-Host -ForegroundColor Yellow "Clearing Windows Temp Folder`n"
    Remove-Item -Path "C:\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
    Remove-Item -Path "C:\Windows\Logs\CBS\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
    Remove-Item -Path "C:\ProgramData\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
    
    # Only grab log files sitting in the root of the Logfiles directory
    $Sys32Files = Get-ChildItem -Path "C:\Windows\System32\LogFiles" | Where-Object { ($_.name -like "*.log") -and ($_.lastwritetime -lt $System32LogDate) }
    foreach ($File in $Sys32Files) {
        Remove-Item -Path "C:\Windows\System32\LogFiles\$($file.name)" -Force -ErrorAction SilentlyContinue -Verbose
    }
    Write-Host -ForegroundColor Yellow "Done...`n"          

    # Clear Inetpub Logs Folder
    if (Test-Path "C:\inetpub\logs\LogFiles\") {
        Write-Host -ForegroundColor Yellow "Clearing Inetpub Logs Folder`n"
        $Folders = Get-ChildItem -Path "C:\inetpub\logs\LogFiles\" | Select-Object Name
        foreach ($Folder in $Folders) {
            $folder = $Folder.Name
            Remove-Item -Path "C:\inetpub\logs\LogFiles\$Folder\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose | Where-Object LastWriteTime -LT $DelInetLogDate
        }
        Write-Host -ForegroundColor Yellow "Done...`n" 
    }

    # Delete Microsoft Teams Previous Version files
    Write-Host -ForegroundColor Yellow "Clearing Teams Previous version`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\AppData\Local\Microsoft\Teams\") {
            Remove-Item -Path "C:\Users\$user\AppData\Local\Microsoft\Teams\previous\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\AppData\Local\Microsoft\Teams\stage\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        } 
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Delete SnagIt Crash Dump files
    Write-Host -ForegroundColor Yellow "Clearing SnagIt Crash Dumps`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\AppData\Local\TechSmith\SnagIt") {
            Remove-Item -Path "C:\Users\$user\AppData\Local\TechSmith\SnagIt\CrashDumps\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        } 
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear Dropbox
    Write-Host -ForegroundColor Yellow "Clearing Dropbox Cache`n"
    Foreach ($user in $Users) {
        if (Test-Path "C:\Users\$user\Dropbox\") {
            Remove-Item -Path "C:\Users\$user\Dropbox\.dropbox.cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Remove-Item -Path "C:\Users\$user\Dropbox*\.dropbox.cache\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        }
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Clear HP Support Assistant Installation Folder
    if (Test-Path "C:\swsetup") {
        Remove-Item -Path "C:\swsetup" -Force -ErrorAction SilentlyContinue -Verbose
    } 

    # Delete files older than 90 days from Downloads folder
    if ($DeleteOldDownloads -eq 'Y') { 
        Write-Host -ForegroundColor Yellow "Deleting files older than 90 days from User Downloads folder`n"
        Foreach ($user in $Users) {
            $UserDownloads = "C:\Users\$user\Downloads"
            $OldFiles = Get-ChildItem -Path "$UserDownloads\" -Recurse -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -LT $DelDownloadsDate
            foreach ($file in $OldFiles) {
                Remove-Item -Path "$UserDownloads\$file" -Force -ErrorAction SilentlyContinue -Verbose
            }
        }
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete files older than 7 days from Azure Log folder
    if (Test-Path "C:\WindowsAzure\Logs") {
        Write-Host -ForegroundColor Yellow "Deleting files older than 7 days from Azure Log folder`n"
        $AzureLogs = "C:\WindowsAzure\Logs"
        $OldFiles = Get-ChildItem -Path "$AzureLogs\" -Recurse -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -LT $DelAZLogDate
        foreach ($file in $OldFiles) {
            Remove-Item -Path "$AzureLogs\$file" -Force -ErrorAction SilentlyContinue -Verbose
        }
        Write-Host -ForegroundColor Yellow "Done...`n"
    } 

    # Delete files older than 7 days from Office Cache Folder
    Write-Host -ForegroundColor Yellow "Clearing Office Cache Folder`n"
    Foreach ($user in $Users) {
        $officecache = "C:\Users\$user\AppData\Local\Microsoft\Office\16.0\GrooveFileCache"
        if (Test-Path $officecache) {
            $OldFiles = Get-ChildItem -Path "$officecache\" -Recurse -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -LT $DelOfficeCacheDate 
            foreach ($file in $OldFiles) {
                Remove-Item -Path "$officecache\$file" -Force -ErrorAction SilentlyContinue -Verbose
            }
        } 
    }
    Write-Host -ForegroundColor Yellow "Done...`n"

    # Delete files older than 30 days from LFSAgent Log folder https://www.lepide.com/
    if (Test-Path "C:\Windows\LFSAgent\Logs") {
        Write-Host -ForegroundColor Yellow "Deleting files older than 30 days from LFSAgent Log folder`n"
        $LFSAgentLogs = "C:\Windows\LFSAgent\Logs"
        $OldFiles = Get-ChildItem -Path "$LFSAgentLogs\" -Recurse -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -LT $DelLFSAGentLogDate
        foreach ($file in $OldFiles) {
            Remove-Item -Path "$LFSAgentLogs\$file" -Force -ErrorAction SilentlyContinue -Verbose
        }
        Write-Host -ForegroundColor Yellow "Done...`n"
    }         

    # Delete SOTI MobiController Log files older than 1 year
    if (Test-Path "C:\Program Files (x86)\SOTI\MobiControl") {
        Write-Host -ForegroundColor Yellow "Deleting SOTI MobiController Log files older than 1 year`n"
        $SotiLogFiles = Get-ChildItem -Path "C:\Program Files (x86)\SOTI\MobiControl" | Where-Object { ($_.name -like "*Device*.log" -or $_.name -like "*Server*.log" ) -and ($_.lastwritetime -lt $DelSotiLogDate) }
        foreach ($File in $SotiLogFiles) {
            Remove-Item -Path "C:\Program Files (x86)\SOTI\MobiControl\$($file.name)" -Force -ErrorAction SilentlyContinue -Verbose
        }
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete old Cylance Log files
    if (Test-Path "C:\Program Files\Cylance\Desktop") {
        Write-Host -ForegroundColor Yellow "Deleting Old Cylance Log files`n"
        $OldCylanceLogFiles = Get-ChildItem -Path "C:\Program Files\Cylance\Desktop" | Where-Object name -Like "cylog-*.log"
        foreach ($File in $OldCylanceLogFiles) {
            Remove-Item -Path "C:\Program Files\Cylance\Desktop\$($file.name)" -Force -ErrorAction SilentlyContinue -Verbose
        }
        Write-Host -ForegroundColor Yellow "Done...`n"
    }

    # Delete Windows Updates Folder (SoftwareDistribution) and reset the Windows Update Service
    if ($CleanWU -eq 'Y') { 
        Write-Host -ForegroundColor Yellow "Restarting Windows Update Service and Deleting SoftwareDistribution Folder`n"
        # Stop the Windows Update service
        try {
            Stop-Service -Name wuauserv
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Warning "$ErrorMessage" 
        }
        # Delete the folder
        Remove-Item "C:\Windows\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue -Verbose
        Start-Sleep -s 3

        # Start the Windows Update service
        try {
            Start-Service -Name wuauserv
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Warning "$ErrorMessage" 
        }
        Write-Host -ForegroundColor Yellow "Done..."
        Write-Host -ForegroundColor Yellow "Please rerun Windows Update to pull down the latest updates `n"
    }

    # Empty Recycle Bin
    if ($Cleanbin -eq 'Y') {
        Write-Host -ForegroundColor Green "Cleaning Recycle Bin`n"
        $ErrorActionPreference = 'SilentlyContinue'
        $RecycleBin = "C:\`$Recycle.Bin"
        $BinFolders = Get-ChildItem $RecycleBin -Directory -Force

        Foreach ($Folder in $BinFolders) {
            # Translate the SID to a User Account
            $objSID = New-Object System.Security.Principal.SecurityIdentifier ($folder)
            try {
                $objUser = $objSID.Translate( [System.Security.Principal.NTAccount])
                Write-Host -Foreground Yellow -Background Black "Cleaning $objUser Recycle Bin"
            }
            # If SID cannot be Translated, Throw out the SID instead of error
            catch {
                $objUser = $objSID.Value
                Write-Host -Foreground Yellow -Background Black "$objUser"
            }
            $Files = @()

            if ($PSVersionTable.PSVersion -Like "*2*") {
                $Files = Get-ChildItem $Folder.FullName -Recurse -Force
            }
            else {
                $Files = Get-ChildItem $Folder.FullName -File -Recurse -Force
                $Files += Get-ChildItem $Folder.FullName -Directory -Recurse -Force
            }

            $FileTotal = $Files.Count

            for ($i = 1; $i -le $Files.Count; $i++) {
                $FileName = Select-Object -InputObject $Files[($i - 1)]
                Write-Progress -Activity "Recycle Bin Clean-up" -Status "Attempting to Delete File [$i / $FileTotal]: $FileName" -PercentComplete (($i / $Files.count) * 100) -Id 1
                Remove-Item -Path $Files[($i - 1)].FullName -Recurse -Force
            }
            Write-Progress -Activity "Recycle Bin Clean-up" -Status "Complete" -Completed -Id 1
        }
        Write-Host -ForegroundColor Green "Done`n `n"
    }

    Write-Host -ForegroundColor Green "All Tasks Done!`n`n"


    # Get Drive size after clean
    $After = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq "3" } | Select-Object SystemName,
    @{ Name = "Drive" ; Expression = { ( $_.DeviceID ) } },
    @{ Name = "Size (GB)" ; Expression = { "{0:N1}" -f ( $_.Size / 1gb) } },
    @{ Name = "FreeSpace (GB)" ; Expression = { "{0:N1}" -f ( $_.Freespace / 1gb ) } },
    @{ Name = "PercentFree" ; Expression = { "{0:P1}" -f ( $_.FreeSpace / $_.Size ) } } |
    Format-Table -AutoSize | Out-String

    # Sends some before and after info for ticketing purposes
    Write-Host -ForegroundColor Green "Before: $Before"
    Write-Host -ForegroundColor Green "After: $After"

    # Another reminder about running Windows update if needed as it would get lost in all the scrolling text.
    if ($CleanWU -eq 'Y') { 
        Write-Host -ForegroundColor Yellow "`nPlease rerun Windows Update to pull down the latest updates. `n"
    }

    # Read some of the output before going away
    Start-Sleep -s 15

    # Completed Successfully!
    # Open Text File
    Invoke-Item $Cleanuplog

    # Stop Script
    Stop-Transcript
}

$TempItems = Get-ChildItem "C:\Temp" -Recurse
if ($TempItems.count -gt 1) {
    Write-Warning "There are files within C:\Temp, please verify that important files are out of this location"
    $Cont = Read-Host "Continue with the cleanup script [Y/N]"
    if ($cont -eq "Y") { 
        Cleanup
    }
    else {
        Write-Host "Please check the files within C:\Temp before running the script again"
        Start-Sleep -Seconds 5
    }
}
else {
    Cleanup
}