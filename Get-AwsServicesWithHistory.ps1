#Requires -Version 5.1
<#
.SYNOPSIS
	Returns AWS policy actions as a structure and records the history
	of what differs from the previous data. 
	
	This should be run BEFORE running Get-AwsServices.ps1 (which will update AwsServiceActions.csv).
	
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
	TO GENERATE A CSV (only):
		CD C:\GIT\awsles\AwsServices
		.\Get-AwsServicesWithHistory.ps1 -Update	

	TO CONVERT the above AwsServiceActions.CSV TO FORMATTED TEXT:
		"{0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath 'AwsServiceActions.txt' -Encoding utf8 -force -width 210 ;
		Import-Csv -Path 'AwsServiceActions.csv' | foreach { ("{0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) } | out-file -FilePath 'AwsServiceActions.txt' -width 210 -Encoding utf8 -Append

	TO DO *ALL* STEPS:
		CD C:\GIT\awsles\AwsServices
		.\Get-AwsServicesWithHistory.ps1	# **** SEE Line 170 and run thise in non-update to check results
		.\Get-AwsServicesWithHistory.ps1 -Update	
		.\Get-AwsServices.ps1 -ServicesOnly | Export-Csv -Path 'AwsServices.csv' -Encoding utf8 -force
		# Make a Copy of the outputs into History folder
		copy-item -Path "AwsServices.csv" -Destination ".\history\AwsServices ($(get-date -Format 'dd-MMM-yy')).csv" 
		copy-item -Path "AwsServiceActions.csv" -Destination ".\history\AwsServiceActions ($(get-date -Format 'dd-MMM-yy')).csv" 
		# Create formatted text outputs
		"{0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath 'AwsServiceActions.txt' -Encoding utf8 -force -width 210 ;
		Import-Csv -Path 'AwsServiceActions.csv' | foreach { ("{0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) } | out-file -FilePath 'AwsServiceActions.txt' -width 210 -Encoding utf8 -Append
		"{0,-56} {1,-25} {2}" -f 'ServiceName','ServiceShortName','ARNFormat' | out-file -FilePath 'AwsServices.txt' -Encoding utf8 -force -width 210 ;
		Import-Csv -Path 'AwsServices.csv' | foreach { ("{0,-56} {1,-25} {2}" -f $_.ServiceName, $_.ServiceShortName, $_.ARNFormat) } | out-file -FilePath 'AwsServices.txt' -width 210 -Encoding utf8 -Append



.NOTES
	Author: Lester W.
	Version: v0.07b
	Date: 09-Jan-24
	Repository: https://github.com/leswaters/AwsServices
	License: MIT License
	
	TO DO:
	* Update service list CSV and TXT as well.
	* $Warnings are not propagated back up... to be fixed.
	
.LINK
	https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_actions-resources-contextkeys.html
	https://github.com/rvedotrc/aws-iam-reference	
	https://awspolicygen.s3.amazonaws.com/policygen.html   (web tool containing JavaScript which we scrape)
	https://www.leeholmes.com/blog/2015/01/05/extracting-tables-from-powershells-invoke-webrequest/
	https://lazyadmin.nl/powershell/get-date/
	
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
# "ServiceName","Action","Description","AccessLevel","DocLink"
$PreviousData = Import-Csv -Path $InputFile | Where-Object {$_.Action.Length -gt 0} | Sort-Object -Property Action

# Determine Previous Services
$PreviousServices = $PreviousData.ServiceName | Select-Object -Unique | Sort-Object

# Get new data, sorted by Action, dropping any notes
$CurrentData = .\Get-AwsServices.ps1 -WarningVariable $Warnings | Where-Object {$_.Action.Length -gt 0} | Sort-Object -Property Action 
if ($Warnings)
{
	write-warning $Warnings
}

# Determine Current Services
$CurrentServices = $CurrentData.ServiceName | Select-Object -Unique | Sort-Object

# Compare old & new services
$NewServices = (Compare-Object -ReferenceObject $CurrentServices -DifferenceObject $PreviousServices | Where-Object {$_.SideIndicator -eq '<='}).InputObject
$DeprecatedServices = (Compare-Object -ReferenceObject $CurrentServices -DifferenceObject $PreviousServices | Where-Object {$_.SideIndicator -eq '=>'}).InputObject
$ServiceNameChanges = "There are $($NewServices.Count) new service names and $($DeprecatedServices.Count) deprecated service names.`n"
if ($NewServices) { $ServiceNameChanges += "NEW :`n  $($NewServices -join ""`n  "")`n" }
if ($DeprecatedServices) { $ServiceNameChanges += "DEPRECATED :`n  $($DeprecatedServices -join ""`n  "")`n" }
Write-host $ServiceNameChanges


# Loop through current list
$Results = Compare-Object -ReferenceObject $CurrentData -DifferenceObject $PreviousData -Property Action -PassThru | Sort-Object -Property Action
### OLD METHOD:
#$i = 0  # Index into $PreviousData, which MUST be sorted!
#foreach ($entry in $CurrentData)
#{
#	# Skip anything that may be deprecated
#	while ($i -lt $PreviousData.Count -And $PreviousData[$i].Action -lt $entry.Action)
#	{ 
#		$PreviousData[$i] | Add-Member -NotePropertyName 'Status' -NotePropertyValue 'Deprecated' -Force
#		$Results += $PreviousData[$i]
#		$i++
#	} 
#
#	# If we have a match, then skip past it
#	# Otherwise, we have a new entry
#	if ($i -lt $PreviousData.Count -And $PreviousData[$i].Action -eq $entry.Action)
#	{ 
#		$i++
#	} 
#	else
#	{
#		$entry | Add-Member -NotePropertyName 'Status' -NotePropertyValue 'New' -Force
#		$Results += $entry
#	}
#}

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
	$DeprecatedActions	= @($Results | Where-Object {$_.SideIndicator -eq '=>'})
	$NewActions	= @($Results | Where-Object {$_.SideIndicator -eq '<='})
	
	# Make Sure NewActions does not have elements from DeprecatedActions
	$z = ($NewActions | ?{$DeprecatedActions -contains $_})
	if ($z)
	{
		write-warning "There are items which appear as new as well as deprecated! [BUG]`n"
		write-host $Z
	}

	# Add a divider
	'=' * 100 | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
	
	# Add the timestamp and summary
	"$Today : There are $($CurrentData.Actions.Count) actions across $($CurrentServices.Count) AWS services.`n              $($Results.Count) changes have been detected: $($NewActions.Count) new; $($DeprecatedActions.Count) deprecated." `
		| out-file -FilePath $HistoryFile -Encoding UTF8 -Append 
		
	if ($Warnings)
	{
		"`n$Warnings" | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
	}
	
	# Output the service name changes
	$ServiceNameChanges | out-file -FilePath $HistoryFile -Encoding UTF8 -Append 
	
	# Output the deprecated actions
	if ($DeprecatedActions)
	{
		"`nDEPRECATED:" | out-file -FilePath $HistoryFile -Encoding UTF8 -Append
		"  {0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
		"  {0,-56} {1,-80} {2,-23} {3}" -f '-----------','------','-----------','-----------' | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250
		$DeprecatedActions | foreach { ("  {0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) | out-file -FilePath $HistoryFile -Encoding UTF8 -Append -width 250}
	}
	
	# Output the new actions	
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

