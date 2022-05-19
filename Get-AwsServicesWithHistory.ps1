#Requires -Version 5.1
<#
.SYNOPSIS
	Returns AWS policy actions as a structure and records the history
	of what differs from the previous data.
	
.DESCRIPTION
	This script calls Get-AwsServices.ps1 and compares the results with the previous
	results from the input CSV. New and deprecated AWS service actions are identified.

.PARAMETER InputFile
	Name of the input file. Default is 'AwsServiceActions.csv'
	
.PARAMETER OutputFile
	Name of the input file. Default is the InputFile name.
	
.PARAMETER HistoryFile
	Name of the history text file to append differences to.\
	The default is 'AwsHistory.txt'
	
.PARAMETER Update
	If specified, then the OutputFile is updated.
	
.EXAMPLE	
	TO SEE A QUICK VIEW:
		.\Get-AwsServicesWithHistory.ps1  # -Update
	

.NOTES
	Author: Lester W.
	Version: v0.06
	Date: 19-May-22
	Repository: https://github.com/lesterw1/AwsServices
	License: MIT License
	
	$Warnings are not propagated back up... to be fixed.
	
.LINK
	https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_actions-resources-contextkeys.html
	https://github.com/rvedotrc/aws-iam-reference	
	https://awspolicygen.s3.amazonaws.com/policygen.html   (web tool containing JavaScript which we scrape)
	https://www.leeholmes.com/blog/2015/01/05/extracting-tables-from-powershells-invoke-webrequest/

#>


# +=================================================================================================+
# |  PARAMETERS																						|
# +=================================================================================================+
[cmdletbinding()]   #  Add -Verbose support; use: [cmdletbinding(SupportsShouldProcess=$True)] to add WhatIf support
Param
(
	[string] $InputFile			= 'AwsServiceActions.csv',
	[string] $OutputFile		= $InputFile,	
	[string] $HistoryFile		= 'AwsHistory.txt',
	[switch] $Update			= $false
)


# +=================================================================================================+
# |  CLASSES																						|
# +=================================================================================================+

# +=================================================================================================+
# |  CONSTANTS																						|
# +=================================================================================================+

# +=================================================================================================+
# |  LOGIN		              																		|
# +=================================================================================================+
# Not necessary for AWS due to the way the list is extracted.

# +=================================================================================================+
# |  MAIN Body																						|
# +=================================================================================================+
$Results = @()
$Today = (Get-Date).ToString("dd-MMM-yyyy")
$Activity	= "Extracting AWS policy actions..."

# Read in existing Inputfile, sorted by Action, dropping any notes
$PreviousData = Import-Csv -Path $InputFile | Where-Object {$_.Action.Length -gt 0} | Sort-Object -Property Action

# Get new data, sorted by Action, dropping any notes
$CurrentData = .\Get-AwsServices.ps1 -WarningVariable $Warnings | Where-Object {$_.Action.Length -gt 0} | Sort-Object -Property Action 
if ($Warnings)
{
	write-warning $Warnings
}

# Loop through current list
$i = 0  # Index into $PreviousData, which MUST be sorted!
foreach ($entry in $CurrentData)
{
	# Skip anything that may be deprecated
	while ($i -lt $PreviousData.Count -And $PreviousData[$i].Action -lt $entry.Action)
	{ 
		$PreviousData[$i] | Add-Member -NotePropertyName 'Status' -NotePropertyValue 'Deprecated' -Force
		$Results += $PreviousData[$i]
		$i++
	} 

	# If we have a match, then skip past it
	# Otherwise, we have a new entry
	if ($i -lt $PreviousData.Count -And $PreviousData[$i].Action -eq $entry.Action)
	{ 
		$i++
	} 
	else
	{
		$entry | Add-Member -NotePropertyName 'Status' -NotePropertyValue 'New' -Force
		$Results += $entry
	}
}

# Extract ServiceNames
$ServiceNames = $CurrentData | Select-Object -Property ServiceName -Unique | Sort-Object

# If HistoryFile does not exist, then we will create it with a new header
if ((Test-Path -Path $HistoryFile) -eq $false)
{
	# Add the timestamp and summary
	"$('=' * 25) $HistoryFile $('=' * 25)`nThis file contains the observed history of AWS Services and Actions.`nWhere previous results are provided, a comparison is displayed with observed changes.`n`n" `
		| out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
}

# At this point, $Results has all of the differences...
# Update the history file
if ($HistoryFile)
{
	$Deprecated	= @($Results | Where-Object {$_.Status -eq 'Deprecated'})
	$NewActions	= @($Results | Where-Object {$_.Status -eq 'New'})

	# Add a divider
	'=' * 100 | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
	
	# Add the timestamp and summary
	"$Today : There are $($CurrentData.Actions.Count) actions across $($ServiceNames.Count) AWS services.`n              $($Results.Count) changes have been detected: $($NewActions.Count) new; $($Deprecated.Count) deprecated." `
		| out-file -FilePath $HistoryFile -Encoding UTF8 -Append 
		
	if ($Warnings)
	{
		"`n$Warnings" | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
	}
	
	if ($Deprecated)
	{
		"`nDEPRECATED:" | out-file -FilePath $HistoryFile -Encoding UTF8 -Append
		"  {0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
		"  {0,-56} {1,-80} {2,-23} {3}" -f '-----------','------','-----------','-----------' | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
		$Deprecated | foreach { ("  {0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250}
	}
	
	if ($NewActions)
	{
		"`nNEW ACTIONS:" | out-file -FilePath $HistoryFile -Encoding UTF8 -Append
		"  {0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
		"  {0,-56} {1,-80} {2,-23} {3}" -f '-----------','------','-----------','-----------' | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
		$NewActions | foreach { ("  {0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250}
	}
	
	"`n" | out-file -FilePath $HistoryFile -Encoding UTF8 -Append 
}
	
if ($Update)
{
	# Update CSV
	$CurrentData | Export-Csv -Path $OutputFile -encoding UTF8 -force
	
	# Update associated text file
	$TxtFile = $OutputFile.Replace('.csv', '.txt')
	"{0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath $TxtFile -Encoding utf8 -force -width 250 ;
		$CurrentData | foreach { ("{0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) } | out-file -FilePath $TxtFile -width 250 -Encoding utf8 -Append

	# TBD - Update services files...
}

