param (
  $BackupLocation = "", 
  $KmDataFolder = 'C:\ProgramData\nCipher\Key Management Data',
  $LogFile = "", 
  [switch]$Restore = $false,
  [switch]$IncludeADCS = $true
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

if (!$Restore)
{
    #create a folder in the target folder
    $currentDate = Get-Date
    $destinationFolder = Join-Path -Path $BackupLocation -ChildPath $currentDate.ToString("dd-MM-yyyy_hh-mm-ss")
    $destinationFolder = $destinationFolder + "-" + $scriptName

    $destinationKmdataFolder = Join-Path -Path $destinationFolder -ChildPath "kmdata-local"

    $destinationAdcsFolder = Join-Path -Path $destinationFolder -ChildPath "DBbackup"
    $destinationAdcsCertFolder = $destinationAdcsFolder
    $destinationAdcsCAPolicyFolder = $destinationAdcsFolder

    $sourceAdcsCertFolder = Join-Path -Path $env:windir -ChildPath \system32\certsrv\certenroll 
    $sourceAdcsCAPolicyFolder = $env:windir

    $sourceKmdata = $KmDataFolder

    if (Test-Path $destinationFolder)
    {
        #exists, what do we do?  Prompt or look for overwrite?
    }
    else
    {
        New-Item -Path $destinationFolder -Type Directory
    }
}
else
{
    $destinationKmdataFolder = $KmDataFolder

    $destinationAdcsCertFolder = Join-Path -Path $env:windir -ChildPath \system32\certsrv\certenroll 
    $destinationAdcsCAPolicyFolder = -Path $env:windir

    $sourceKmData = Join-Path -Path $BackupLocation -ChildPath "kmdata-local"
    $sourceADCS = Join-Path -Path $BackupLocation -ChildPath "DBbackup"
    $sourceAdcsCertFolder = $sourceADCS 
    $sourceAdcsCAPolicyFolder = $sourceADCS

}

try
{         
    .\CopyAndRecord.ps1 -CopyFrom $sourceKmData -CopyTo $destinationKmdataFolder -LogFile $LogFile -Recurse -ErrorAction stop
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

        # copy the cert files
        .\CopyAndRecord.ps1 -CopyFrom $sourceAdcsCertFolder -CopyTo $destinationAdcsCertFolder -Pattern "*.crt" -LogFile $LogFile
        .\CopyAndRecord.ps1 -CopyFrom $sourceAdcsCertFolder -CopyTo $destinationAdcsCertFolder -Pattern "*.crl" -LogFile $LogFile
        .\CopyAndRecord.ps1 -CopyFrom $sourceAdcsCAPolicyFolder -CopyTo $destinationAdcsCAPolicyFolder -Pattern "CAPolicy.inf" -LogFile $LogFile

        if (!$Restore)
        {

            # backup the cert database
            $certutilProgram = Join-Path -Path $env:windir -ChildPath "\system32\certutil.exe"
            $arguments = "-backupDB `"$destinationAdcsCertFolder`""
            $p = Start-Process $certutilProgram -ArgumentList $arguments -wait -NoNewWindow -passthru  -RedirectStandardOutput temp.fil -RedirectStandardError errors.txt

            if ($p.ExitCode -ne 0)
            {
                FailedBanner "certutil command failed"

                exit
            }
        }

        # export the registry configuation data
        $regProgram = Join-Path -Path $env:windir -ChildPath "\system32\reg.exe"
        $arguments = "export HKLM\system\currentcontrolset\services\certsvc\configuration caregistry.regr"
        $p = Start-Process $regProgram -ArgumentList $arguments -wait -NoNewWindow -passthru  -RedirectStandardOutput temp.fil -RedirectStandardError errors.txt

        $p.HasExited
        if ($p.ExitCode -ne 0)
        {
            FailedBanner "registry export command failed"
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
Write-Host Files copied to $BackupFolder

$copiedFiles | Format-Table -AutoSize -Property Filename, Digest, CopiedFrom

Write-Host "File details copied to" $LogFile




