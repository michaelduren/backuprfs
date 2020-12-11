param (
  $BackupDestination = "C:\test", 
  $LogFile = "copiedFiles.csv", 
  $KmDataSource = 'C:\ProgramData\nCipher\Key Management Data',
  [switch]$Restore = $false,
  [switch]$IncludeADCS = $false
)


####################################################################################
#
#  FailedBanner
#    
#
####################################################################################
function FailedBanner 
{
    param ($message)

    Write-Host "**********************************************************"
    Write-Host "*                                                        *"
    Write-Host "*                         FAILED                         *"
    Write-Host "*                                                        *"
    Write-Host "**********************************************************"
    Write-Host 
    Write-Host $message
    Write-Host 
}

####################################################################################
#
#  PassedBanner
#    
#
####################################################################################
function PassedBanner 
{
    param ($message)

    Write-Host "**********************************************************"
    Write-Host "*                                                        *"
    Write-Host "*                       Complete                         *"
    Write-Host "*                                                        *"
    Write-Host "**********************************************************"
    Write-Host 
}

if (Test-Path $LogFile)
{
    Remove-Item -Path $LogFile
}

# the script name is used in the target folder name
$scriptName = [io.path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

#create a folder in the target folder
$BackupFolder = Join-Path -Path $BackupDestination -ChildPath $currentDate.ToString("dd-MM-yyyy")
$BackupFolder = $BackupFolder + "-" + $scriptName

if (Test-Path $BackupFolder)
{
    #exists, what do we do?
}
else
{
    New-Item -Path $BackupFolder -Type Directory
}

$kmDataBackupFolder = Join-Path -Path $BackupFolder -ChildPath "kmdata-local"

try
{         
    if ($Restore)
    {
        .\CopyAndRecord.ps1 -CopyFrom $kmDataBackupFolder -CopyTo $KmDataSource -LogFile $LogFile -Recurse -ErrorAction stop
    }
    else
    {
        .\CopyAndRecord.ps1 -CopyFrom $KmDataSource -CopyTo $kmDataBackupFolder -LogFile $LogFile -Recurse -ErrorAction stop
    }
}
catch
{ 
    FailedBanner -message "Failed to copy HSM key management data"

    Write-Host $_
    exit
}


if ($IncludeADCS)
{
    try
    {         
        $dbBackupFolder = Join-Path -Path $BackupFolder -ChildPath "DBbackup"

        # copy the cert files
        .\CopyAndRecord.ps1 -CopyFrom $env:windir\system32\certsrv\certenroll -CopyTo $dbBackupFolder -Pattern "*.crt" -LogFile $LogFile
        .\CopyAndRecord.ps1 -CopyFrom $env:windir\system32\certsrv\certenroll -CopyTo $dbBackupFolder -Pattern "*.crl" -LogFile $LogFile
        .\CopyAndRecord.ps1 -CopyFrom $env:windir -CopyTo $dbBackupFolder -Pattern "CAPolicy.inf" -LogFile $LogFile

        # backup the cert database
        $certutilProgram = Join-Path -Path $env:windir -ChildPath "\system32\certutil.exe"
        $arguments = "-backupDB `"$dbBackupFolder`""
        $p = Start-Process $certutilProgram -ArgumentList $arguments -wait -NoNewWindow -passthru  -RedirectStandardOutput temp.fil -RedirectStandardError errors.txt

        if ($p.ExitCode -ne 0)
        {
            Write-Host "certutil command failed FAILED"
            exit
        }


        # export the registry configuation data
        $regProgram = Join-Path -Path $env:windir -ChildPath "\system32\reg.exe"
        $arguments = "export HKLM\system\currentcontrolset\services\certsvc\configuration caregistry.regr"
        $p = Start-Process $regProgram -ArgumentList $arguments -wait -NoNewWindow -passthru  -RedirectStandardOutput temp.fil -RedirectStandardError errors.txt

        $p.HasExited
        if ($p.ExitCode -ne 0)
        {
            Write-Host "FAILED"
            exit
        }    
    }
    catch
    { 
        Write-Host "FAILED"
        Write-Host $_
    }
}


# success if we reach this point
PassedBanner
$copiedFiles = Import-Csv -Path $LogFile 

Write-Host $copiedFiles.Count files copied.

$copiedFiles | Format-Table -AutoSize -Property Filename, Digest, CopiedFrom

Write-Host "File details copied to" $LogFile




