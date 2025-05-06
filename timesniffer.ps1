param(
    [Parameter(Mandatory=$true)][string]$TargetDir
)

$workingDir = Split-Path -Parent $MyInvocation.MyCommand.Definition 

# Look for subfolders matching Mft2Csv_....
$pattern   = 'Mft2Csv_*'
$folders   = Get-ChildItem -Path $workingDir -Directory |
             Where-Object Name -Like $pattern

# find the one with the latest timestamp in its name
$latestFolder = $folders |
    Sort-Object -Property Name |
    Select-Object -Last 1

# Derive the data CSV path
if ($latestFolder) {
	Write-Warning("Using previously generated MFT dump")
    $CsvPath = Join-Path -Path $latestFolder.FullName -ChildPath 'Mft.csv'
	$CsvAgeMinutes = (Get-Date) - (Get-Item $CsvPath).LastWriteTime
} else { 
	$CsvAgeMinutes = [timespan]::FromMinutes(9999) #to force a remake
}

#If it is older than 30 minutes redo the long MFT dumping process
if ($CsvAgeMinutes.TotalMinutes -gt 30) {
    Write-Host "MFT dump is older than 30 minutes (or missing). Regenerating it... This will take a while."

    # Run the Mft2Csv64 executable
		& "$workingDir\Mft2Csv64.exe" `
        "/Volume:C:" `
		"/OutputPath:$workingDir" `
        "/OutputFormat:all" `
        "/TimeZone:00.00" `
        "/Separator:," `
		"/TSPrecision:NanoSec"

    # locate the newly created folder
    $latest = Get-ChildItem $workingDir -Directory `
              | Where-Object Name -Like 'Mft2Csv_*' `
              | Sort-Object Name `
              | Select-Object -Last 1

    $CsvPath = Join-Path $latest.FullName 'mft.csv'
}

Write-Host "Loading MFT CSV from $CsvPath... This will take a while"
# Initialize hashtable for lookups
$lookup = @{}

#extract the target drive letter
$drive = Split-Path -Path $TargetDir -Qualifier
$relativeRoot = (Split-Path $TargetDir -NoQualifier).TrimEnd('\')
$targetPrefix = "$drive$relativeRoot\"

# Load TextFieldParser for streaming CSV parse
Add-Type -AssemblyName 'Microsoft.VisualBasic' 
$parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($CsvPath) 
$parser.SetDelimiters('|', ',')
$parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited

# Read header and map columns
$header = $parser.ReadFields()
$idx = @{
	FileName   = [array]::IndexOf($header, 'FN_FileName')
    FilePath   = [array]::IndexOf($header, 'FilePath')
    SI_MTime   = [array]::IndexOf($header, 'SI_MTime')
    FN_MTime   = [array]::IndexOf($header, 'FN_MTime')
	SI_ATime   = [array]::IndexOf($header, 'SI_ATime')
    FN_ATime   = [array]::IndexOf($header, 'FN_ATime')
	SI_CTime   = [array]::IndexOf($header, 'SI_CTime')
    FN_CTime   = [array]::IndexOf($header, 'FN_CTime')
	SI_ETime   = [array]::IndexOf($header, 'SI_RTime') #They use "R" for record instead of "E" for entry
    FN_ETime   = [array]::IndexOf($header, 'FN_RTime')
}

# Stream rows into hashtable for o(1) lookups
$i = 0
while (-not $parser.EndOfData) {
	$i = $i + 1
	if ($i % 50000 -eq 0){
		Write-Host("Parsing CSV, line ($($i))")
	}
	
    $fields = $parser.ReadFields()

    # 1) Skip lines that didn’t split into enough columns
    if ($fields.Length -le $idx.FilePath) {
        Write-Verbose "Skipping malformed line with $($fields.Length) fields"
        continue
    }

    # Build the full path
    $csvDir  = $fields[$idx.FilePath].TrimStart(':').TrimStart('\')  
    #$name    = $fields[$idx.FileName]
	$full    = Join-Path $drive $csvDir
    #$full    = Join-Path $full $name
	$msiDate = $null; $mfnDate = $null; $asiDate = $null; $afnDate = $null; $csiDate = $null; $cfnDate = $null; $esiDate = $null; $efnDate = $null
	
	if (-not $full.StartsWith($targetPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue 
    }

	# parse
	try { $msiDate = [datetime]$fields[$idx.SI_MTime] }
	catch {
		# leave $msiDate as $null
	}
	try { $mfnDate = [datetime]$fields[$idx.FN_MTime] }
	catch {
		# leave $mfnDate as $null
	}
	try { $asiDate = [datetime]$fields[$idx.SI_ATime] }
	catch {
		# leave $asiDate as $null
	}
	try { $afnDate = [datetime]$fields[$idx.FN_ATime] }
	catch {
		# leave $afnDate as $null
	}
	try { $csiDate = [datetime]$fields[$idx.SI_CTime] }
	catch {
		# leave $csiDate as $null
	}
	try { $cfnDate = [datetime]$fields[$idx.FN_CTime] }
	catch {
		# leave $cfnDate as $null
	}
	try { $esiDate = [datetime]$fields[$idx.SI_ETime] }
	catch {
		# leave $esiDate as $null
	}
	try { $efnDate = [datetime]$fields[$idx.FN_ETime] }
	catch {
		# leave $efnDate as $null
	}

	$lookup[$full] = [pscustomobject]@{ MSI = $msiDate; MFN = $mfnDate; ASI = $asiDate; AFN = $afnDate; CSI = $csiDate; CFN = $cfnDate; ESI = $esiDate; EFN = $efnDate; }
}
$parser.Close()

Write-Host "Scanning directory $TargetDir..."
# Enumerate files in order and loop through them
$prev = $null
$directoryFiles = Get-ChildItem -Path $TargetDir -File | Sort-Object -Property  {$lookup[$_.FullName].MSI} | ForEach-Object {
    $path = $_.FullName
    if ($lookup.ContainsKey($path)) {
        $entry = $lookup[$path]
        if ($entry.MFN -gt $entry.MSI) {
            Write-Warning "RULE 1 $path violates [FN_MTime $($entry.MFN) > SI_MTime $($entry.MSI)]"
        }
		if ($entry.AFN -gt $entry.ASI) {
            Write-Warning "RULE 2 $path violates [FN_ATime $($entry.AFN) > SI_ATime $($entry.ASI)]"
        }
		if ($entry.CFN -gt $entry.CSI) {
            Write-Warning "RULE 3 $path violates  [FN_CTime $($entry.CFN) > SI_CTime $($entry.CSI)]"
        }
		if ($entry.EFN -gt $entry.ESI) {
            Write-Warning "RULE 4 $path violates [FN_ETime $($entry.EFN) > SI_ETime $($entry.ESI)]"
        }
	
		if ($prev) {
			$prevEntry = $lookup[$prev.FullName]
			if ($entry.MSI -eq $prevEntry.MSI) {
				Write-Warning "RULE 5 $path and $($prev.FullName) violate [duplicate SI_MTime $($entry.MSI)]"
			}
			if ($entry.ASI -eq $prevEntry.ASI) {
				Write-Warning "RULE 6 $path and $($prev.FullName) violate [duplicate SI_ATime $($entry.ASI)]"
			}
			if ($entry.CSI -eq $prevEntry.CSI) {
				Write-Warning "RULE 7 $path and $($prev.FullName) violate [duplicate SI_CTime $($entry.CSI)]"
			}
			if ($entry.ESI -eq $prevEntry.ESI) {
				Write-Warning "RULE 8 $path and $($prev.FullName) violate [duplicate SI_ETime $($entry.ESI)]"
			}
		}
    }
	$prev = $_
}
