param (
  [Parameter(Mandatory=$true)]$CopyTo = "", 
  $LogFile = "", 
  $Pattern = "*",
  [switch]$Recurse = $false,
  [Parameter(Mandatory=$true)]$CopyFrom = "",
  [switch]$KmData = $false,
  [switch]$CertDb = $false
)

if ($LogFile.Length -gt 0)
{
    $currentDate = Get-Date
    $filesTransferred = New-Object System.Data.DataTable
    $filesTransferred.Columns.Add("Filename", "System.String") | Out-Null
    $filesTransferred.Columns.Add("CopiedFrom", "System.String") | Out-Null
    $filesTransferred.Columns.Add("CopiedTo", "System.String") | Out-Null
    $filesTransferred.Columns.Add("Digest", "System.String") | Out-Null
    $filesTransferred.Columns.Add("Date", "System.String") | Out-Null
}


####################################################################################
#
#  CopyAndRecord
#    
#
####################################################################################
function CopyAndRecord 
{
    param($parentFolder, $destinationParentFolder)

    # start with the files 
    $childItems = Get-ChildItem -Force -Path $parentFolder -File -Filter $Pattern
    if ($childItems.Count -gt 0)
    {
        foreach($item in $childItems)
        {
            $destinationItem = Join-Path -Path $destinationParentFolder -ChildPath $item.Name

            try 
            {
                $itemHash = Get-FileHash -Path $item.FullName -Algorithm SHA256 -errorAction stop
                Copy-Item -Force -Path $item.FullName -Destination $destinationItem -errorAction stop

                # record the detaisl of the file that was just copied
                $nRow = $filesTransferred.NewRow()
                $nRow.Filename = $item.Name
                $nRow.CopiedFrom = Split-Path -Path $item.FullName -Parent
                $nRow.CopiedTo = $destinationItem
                $nRow.Digest = $itemHash.Hash
                $nRow.Date = $currentDate.ToLocalTime()
                $filesTransferred.Rows.Add($nRow)
            }
            catch 
            {
                # tell the caller there was an error
                throw $_
            }
        }
    }

    if ($Recurse)
    {
        # recusively create and then copy the folders
        $childItems = Get-ChildItem -Path $parentFolder -Directory
        if ($childItems.Count -gt 0)
        {
            foreach($item in $childItems)
            {
                $destinationItem = Join-Path -Path $destinationParentFolder -ChildPath $item.Name
                try 
                {
                    if ((Test-Path -Path $destinationItem) -eq $false) 
                    { 
                        New-Item -Path $destinationItem -Type Directory
                    }
                }
                catch 
                {
                    # tell the caller there was an error
                    throw $_
                }

                try
                {
                    CopyAndRecord -parentFolder $item.FullName -destinationParentFolder $destinationItem
                }
                catch
                {
                    # this makes sure the recursion unwraps so the original caller gets the error
                    throw $_
                }
            }
        }
    }
}

if (Test-Path $CopyTo)
{
    #exists, what do we do?
}
else
{
    New-Item -Path $CopyTo -Type Directory
}

try
{    
    CopyAndRecord -parentFolder $CopyFrom $CopyTo

    if ($LogFile.Length -gt 0)
    {
        $filesTransferred | Export-Csv $LogFile -notypeinformation -Append
    }
}
catch
{ 
    throw $_
}