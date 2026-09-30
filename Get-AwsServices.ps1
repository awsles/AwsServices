#Requires -Version 5.1
<#
.SYNOPSIS
	Returns AWS policy actions as a structure.
.DESCRIPTION
	Return a structure containing an entry for each service and action.
	This works by reading the JavaScript assets used by the AWS Policy Generator
	at https://awspolicygen.s3.amazonaws.com/policygen.html (part of AWS Policy Baker).
	The documentation page is also scraped for the description and access level information.
	This script is necessary as there is (unfortunately) no AWS API which returns this information.
	
	Note that you do NOT need to be logged into AWS in order to run this script.
	This script also discovers inconsistencies between AWS documentation and the policy generator.

.PARAMETER ServicesOnly
	If indicated, then only the services are returned along with a (guessed) documentation URL.
.PARAMETER RawDataOnly
	If indicated, then the raw data from the JavaScript object is returned.  This is useful
	as it contains information about ARNs, associated RegEx, etc.
.PARAMETER ScanDocumentation
	If indicated, then the documentation page is scanned for actions which did not
	appear in the AWS javascript scrape.  This is MUCH slower but yields more complete results.
.PARAMETER Extended
	If indicated, returns extended information (WORK IN PROGRESS).
.PARAMETER AddNote
	If indicated, then a note row is added to the structure as the first item (useful if piping to a CSV).

.EXAMPLE	
	TO SEE A QUICK VIEW:
		.\Get-AwsServices.ps1 -ServicesOnly | Out-GridView
	
	TO GET A CSV:
		.\Get-AwsServices.ps1 -AddNote | Export-Csv -Path 'AwsServiceActions.csv' -encoding utf8 -force
		
	TO CONVERT the above AwsServiceActions.CSV TO FORMATTED TEXT:
		"{0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath 'AwsServiceActions.txt' -Encoding utf8 -force -width 210 ;
		Import-Csv -Path 'AwsServiceActions.csv' | foreach { ("{0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) } | out-file -FilePath 'AwsServiceActions.txt' -width 210 -Encoding utf8 -Append

	TO GET A LIST OF SERVICES only AS A CSV:
		.\Get-AwsServices.ps1 -ServicesOnly | Export-Csv -Path 'AwsServices.csv' -Encoding utf8 -force
	
	TO CONVERT the above AwsServices.CSV TO FORMATTED TEXT:                                                                                                                                         
		"{0,-56} {1,-25} {2}" -f 'ServiceName','ServiceShortName','ARNFormat' | out-file -FilePath 'AwsServices.txt' -Encoding utf8 -force -width 210 ;
		Import-Csv -Path 'AwsServices.csv' | foreach { ("{0,-56} {1,-25} {2}" -f $_.ServiceName, $_.ServiceShortName, $_.ARNFormat) } | out-file -FilePath 'AwsServices.txt' -width 210 -Encoding utf8 -Append

	TO SEE A LIST OF ACTIONS FOR A SERVICE:
		(.\Get-AwsServices.ps1 -RawDataOnly).ServiceMap."Amazon Redshift".Actions   # All Amazon Redshift actions

.NOTES
	Author: awsles
	Version: v0.42
	Date: 30-Sep-26
	Repository: https://github.com/awsles/AwsServices
	License: MIT License
	
	INPUT DATA:
	$WebResponse = Invoke-WebRequest -UseBasicParsing -uri "https://awspolicygen.s3.amazonaws.com/js/policies.js"
		
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
	[switch] $ServicesOnly		= $false,		# If true, then the services are returned as a structure
	[switch] $RawDataOnly		= $false,		# If true, then the raw data is returned as a structure
	[switch] $ScanDocumentation	= $false,		# If true, then scan documentation pages
	[switch] $Extended			= $false,		# If true, then extended data is returned
	[switch] $AddNote			= $false		# If true, add a note description as the 1st item
)

if ($RawDataOnly -And $ServicesOnly)
{
	write-Error "Choose -ServicesOnly or -RawDataOnly as an option. Both cannot be chosen."
	return $null
}


# +=================================================================================================+
# |  CLASSES																						|
# +=================================================================================================+

class AwsService
{
	[string] $ServiceShortName 
	[string] $ServiceName 
	[string] $Actions
	[string] $ARNFormat 
	[string] $ARNRegex
	[string] $conditionKeys
	[string] $HasResource
	[string] $DocLink
	# IsDeprecated b
}

class AwsAction
{
	[string] $ServiceName
	[string] $StringPrefix			# Extended					
	[string] $Action
	[string] $Description
	[string] $AccessLevel
	[string] $DocLink
	[string] $DocLink2
	[string] $ARNFormat				# Extended
	[string] $ARNRegex				# Extended
	[string] $HasResource			# Extended
}


# +=================================================================================================+
# |  CONSTANTS																						|
# +=================================================================================================+
$AwsPolicyJs	= "https://awspolicygen.s3.amazonaws.com/js/policies.js"
$AwsDocRoot		= "https://docs.aws.amazon.com/service-authorization/latest/reference/list_%SERVICE%.html"

# Documentation Exceptions (page is usally based on the Service Prefix, but there are expections)
#	To help DEBUG AWS Documentation:
#	   .\Get-AwsServices.ps1 -ServicesOnly | Select -Property ServiceShortName,ServiceName,@{Name = "Action1"; `
#      Expression = { $_.Actions.SubString(1).Split(',')[0].Replace('"','') }},DocLink | Export-csv -NoTypeInformation "AwsServices-Temp2.csv" -Force
$DocPageMap = Import-Csv -Path 'DocPages.csv'   # Columns: ServiceName,ServiceShortName,Page,SpanPrefix
if (!$DocPageMap) {
	Write-Warning "Run this in the directory that contains DocPages.csv."
	Return $null
}

# +=================================================================================================+
# |  LOGIN		              																		|
# +=================================================================================================+
# Needed to ensure default credentials are in place for any proxy server
# AWS login is NOT required.
$browser = New-Object System.Net.WebClient
$browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials 


# +=================================================================================================+
# |  MAIN Body																						|
# +=================================================================================================+
$Results = @()
$Today = (Get-Date).ToString("dd-MMM-yyyy")
$Activity	= "Extracting AWS policy actions..."

if ($AddNote)
{
	# 1st entry with notes
	$Entry = New-Object AwsAction
	$Entry.ServiceName		= ""
	$Entry.Description		= "### NOTE ### `nThe data contained herein was scraped on $Today from the AWS Policy Generator " + `
							  "at https://awspolicygen.s3.amazonaws.com/policygen.html and from associated " + `
							  "documentation. It may not be entirely up to date."
	$Entry.Action			= ""
	$Entry.DocLink			= ""
	$Results += $Entry
}


# Grab the JavaScript from AWS
Try
{
	$WebResponse = Invoke-WebRequest -uri $AwsPolicyJs -UseDefaultCredentials -UseBasicParsing
}
Catch
{
	write-error $_
	return $null
}

# Now parse it
$Body		= $WebResponse.Content
$Body1		= $Body.SubString($Body.IndexOf('=')+1)
$RawData 	= ConvertFrom-Json -InputObject $Body1

# If -RawDataOnly, then return it
if ($RawDataOnly)
	{ return $RawData }

# Progress Counter
$ctr = [int32] 0

# Extract SERVICES List
$Services = @()
$ServiceList = ($RawData.ServiceMap | Get-Member | Where-Object {$_.MemberType -Like 'NoteProperty'}).Name
foreach ($service in $ServiceList)
{
	$SkipWarning = $False  # True if we hit a page retrieval error
	
	write-verbose "`n========== $service =========="
	$pctComplete = [string] ([math]::Truncate((++$ctr / $ServiceList.Count)*100))
	Write-Progress -Activity $Activity -PercentComplete $pctComplete  -Status "$service - $pctComplete% Complete  ($ctr of $($ServiceList.Count))" -ID 1
	
	# Get the specific Item
	$ServiceItem = $RawData.ServiceMap.$service
	
	# Cleanup ServiceKeyName (used in documentation)
#	$ServiceKeyName = $service.ToLower().Replace(' ','').Replace('(','').Replace(')','')  # OLD
	$ServiceKeyName = $ServiceItem.StringPrefix
#	$SpanKeyName    = 'list_' + $ServiceItem.StringPrefix    # <span id="..."> < 
	$SpanKeyName    = 'list_' +$ServiceKeyName + '-action-'  # <span id="..."> < 
	
	# Guess Documentation Page and retrieve it
	$i = $DocPageMap.ServiceName.IndexOf($service)
	if ($i -ge 0) {
		$DocPage = $AwsDocRoot.SubString(0,$AwsDocRoot.LastIndexOf('/')+1) + $DocPageMap.page[$i]
		if ($DocPageMap.SpanPrefix[$i].Length -gt 5) { $SpanKeyName = $DocPageMap.SpanPrefix[$i] }
	}
	else {
		$DocPage = $AwsDocRoot.Replace('%SERVICE%', $ServiceKeyName)  # OLD WAY
	}
##	$DocPage = 'https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html' # DEBUG DEBUG
	write-verbose " $DocPage   ($i)"

	# Build up the Services() array
	$ServiceEntry = New-Object AwsService
	$ServiceEntry.ServiceShortName	= $ServiceItem.StringPrefix
	$ServiceEntry.ServiceName 		= $service
	$ServiceEntry.Actions 			= ($ServiceItem.Actions | ConvertTo-json -compress)
	$ServiceEntry.ARNFormat 		= $ServiceItem.ARNFormat
	$ServiceEntry.ARNRegex			= $ServiceItem.ARNRegex
	$ServiceEntry.conditionKeys		= ($ServiceItem.conditionKeys | ConvertTo-json -compress)
	$ServiceEntry.HasResource		= $ServiceItem.HasResource
	$ServiceEntry.DocLink			= $DocPage
	$Services += $ServiceEntry
	
	################
	if (!$ServicesOnly)
	{
		# Grab the documentation page
		Try {
			if ($ScanDocumentation)
			{
				$WebResponse2 		= Invoke-WebRequest -uri $DocPage -UseDefaultCredentials 
				# DO NOT SPECIFY -UseBasicParsing		
			}
			else
			{
				$WebResponse2 		= Invoke-WebRequest -uri $DocPage -UseDefaultCredentials -UseBasicParsing
			}
		}
		Catch {
			$WebResponse2 = $null
			Write-Warning "SERVICE: '$service' - Error retrieving: $DocPage"
			$SkipWarning = $True
			Pause
		}

		# Extract Content - There may be multiple tables now...
		$MasterTable 			= @()
		$Content2				= $WebResponse2.Content										# Get HTML content
		$TableIDs				= @()
		$TableColumns			= @('<th>Action</th>', '<th>Operation</th>', '<th>Actions</th>')
		$HeaderLabels			= @('action', 'actions')  # Lower case!  'operation',
		
		# Grab all <tables>, each into its own entry that we can parse
		$Tables = $WebResponse2.Content.Split('<table ')[1..20]  # Discard 1st entry
		if ($Tables.Count -eq 0) { write-warning "No tables found in $DocPage" ; pause }

		# Loop through the Tables
		For ($i=0; $i -lt $Tables.Count; $i++) {
			$table = $Tables[$i]
			
			# Table Headers
			$HeaderHTML = $table.SubString(0,$table.IndexOf('</thead>'))
			$HeaderHTML = $HeaderHTML.SubString($HeaderHTML.IndexOf('<thead>'))
			$Headers = $HeaderHTML.Split('<th>')[1..20]  # Discard 1st entry
			For ($j=0; $j -lt $Headers.Count; $j++) {
				$Headers[$j] = $Headers[$j].SubString(0,$Headers[$j].IndexOf('</th>')).Trim().ToLower()
			}
			$Rows = $table.Split('<tr>')[1..2000]  # Discard 1st entry
			For ($j=0; $j -lt $Rows.Count; $j++) {
				$Rows[$j] = $Rows[$j].SubString(0,$Rows[$j].IndexOf('</tr>')).Trim()
			}
			# $Rows[0] is the header row!
			
			# Do we want this table?
			If (!($HeaderLabels -Contains $Headers[0])) { continue; }
			
			# Index of description & Access level
			$DescIDX = $Headers.IndexOf('description')     # Usually 1
			$AlevelIDX = $Headers.IndexOf('access level')  # Usally 4
			if ($DescIDX -lt 0) { write-warning "'Description' Column not found in Table $i"; pause }
			if ($AlevelIDX -lt 0) { write-warning "'Access level' Column not found in Table $i"; pause }
			
			# Parse the rows to extract the action, description, and Access level
			ForEach ($row in $Rows) {
				$Columns = $row.Split('<td')[1..99]
				if ($Columns.Count -eq 0)	{ continue }  # Skip Header Row (has '<TH>' instead of '<TD>')
				For ($j=0; $j -lt $Columns.Count; $j++) {
					$Columns[$j] = $Columns[$j].SubString(0,$Columns[$j].IndexOf('</td>')).Trim()
				}
				if (($Columns.Count -lt 3) -Or ($Columns.Count -le $ALevelIDX)) { continue }  # Skip these

				# Extract HTML
				$ActionHTML      = $Columns[0]
				$DescriptionHTML = $Columns[$DescIDX]
				$AccessLevelHTML = $Columns[$ALevelIDX]

				if (!$AccessLevelHTML -OR !$DescriptionHTML) { write-warning "OOps!"; pause }
				
				# Extract SPAN ID
				$k = $ActionHTML.IndexOf('span id=')
				if ($k -ge 0) {
					$ActionID = $ActionHTML.SubString($k+9)
					$ActionID = $ActionID.SubString(0,$ActionID.IndexOf('"'))
				} else {
					$ActionID = ''
				}
				
				# Extract href and label
				$k = $ActionHTML.IndexOf('a href=')
				if ($k -ge 0) {
					$ActionHREF = $ActionHTML.SubString($k+8)
					$ActionLabel = $ActionHREF.SubString($ActionHREF.IndexOf('>')+1)
					$ActionLabel = $ActionLabel.SubString(0,$ActionLabel.IndexOf('</a>'))
					$ActionHREF = $ActionHREF.SubString(0,$ActionHREF.IndexOf('"'))
				} else {
					$ActionHREF = '' ; $ActionLabel = '(not found)'
				}
				
				# Extract description
				$k = $DescriptionHTML.IndexOf('<p>')
				if ($k -ge 0) {
					$Description = $DescriptionHTML.SubString($k+3)
					if ($Description.IndexOf('</p>') -lt 0) { write-host "BREAK1"; pause }  # DEBUG
					$Description = $Description.SubString(0,$Description.IndexOf('</p>'))
				} else {
					$Description = '(not found)'
				}

				# Extract Access level
				$k = $AccessLevelHTML.IndexOf('<p>')
				if ($k -ge 0) {
					$AccessLevel = $AccessLevelHTML.SubString($k+3)
					$AccessLevel = $AccessLevel.SubString(0,$AccessLevel.IndexOf('</p>'))
				} else {
					$AccessLevel = ''
				}

				# Build our object
				$MasterTable += [PSCustomObject] @{
					ActionID 		= $ActionID
					ActionHREF		= $ActionHREF
					ActionLabel		= $ActionLabel
					Description		= $Description
					AccessLevel		= $AccessLevel
				}
			} # END ForEach Row
		} # END ForEach Table
		# RETURN $MasterTable # DEBUG

		# Make sure the rows in the doc matches the count of actions. If it doesn't, output a warning.
		if (($MasterTable.Count -ne $ServiceItem.Actions.Count)) {
			Write-Warning "Found $($MasterTable.Count) table rows in doc. There are $($ServiceItem.Actions.Count) Actions to be mapped."
			pause  # DEBUG
		}
		
		# Loop through each Action
		$NoMatchFlag 			= $False
		foreach ($action in $ServiceItem.Actions)
		{		
			# Create an object
			$Entry = New-Object AwsAction
			$Entry.ServiceName		= $service
			$Entry.Action			= $ServiceItem.StringPrefix + ':' + $action
			$Entry.DocLink			= $DocPage
			if ($Extended)
			{
				$Entry.StringPrefix		= $ServiceItem.StringPrefix
				$Entry.ARNFormat		= $ServiceItem.ARNFormat
				$Entry.ARNRegex			= $ServiceItem.ARNRegex
				$Entry.HasResource		= $ServiceItem.HasResource
			}
									   
			
			# See if we can find the Description for the Service Action
			# Note that it may or may not be preceeded by the prefix.
			# $SearchId 					= 'list_' +$ServiceKeyName + '-action-' + $action # Or SpanKeyName?  # OLD
			$SearchId 					= $SpanKeyName + $action
			Try {
				$MasterMatch 				= $MasterTable.ActionID.IndexOf($SearchId)
			}
			Catch {
				$MasterMatch = -1
			}
			
			If ($MasterMatch -ge 0) {
				$Entry.DocLink2			= $MasterTable[$MasterMatch].ActionHREF
				$Entry.Description		= $MasterTable[$MasterMatch].Description
				$Entry.AccessLevel		= $MasterTable[$MasterMatch].AccessLevel
				$NoMatchFlag 			= $False  # Flag prevents contiguous repitition
				
			} else {
				$Entry.DocLink2			= ''
				$Entry.Description		= '--- DOCPAGE NOT FOUND ---'
				$Entry.AccessLevel		= ''
				write-Host "  No match found for '$SearchID'"
#				if ($MasterTable.Count -gt 0) {
#					write-Host "  No match found for $SearchID"
#					if ($NoMatchFlag -eq $False) {$NoMatchFlag = $True; pause }
#				}
			}
			
			# Save the results
			$Results += $Entry
		}
	
		if ($ScanDocumentation)
		{
			## See what actions are left over from the documentation page...
			# And add them to the $Results()
			# write-host ($DocTable | ConvertTo-json)  # DEBUG!!!!
			$LeftOvers = $DocTable | Where-Object {$_.Actions -Notlike '--' -And $_.Actions.Length -gt 0} 
			foreach ($LeftOver in $LeftOvers)
			{
				# Create an object
				$Entry = New-Object AwsAction
				$Entry.ServiceName		= $service
				$Entry.Action			= $ServiceItem.StringPrefix + ':' + $LeftOver.Actions
				$Entry.DocLink			= $DocPage
				$Entry.Description		= "[DOCUMENTATION ONLY] " + $LeftOver.Description
				$Results += $Entry
				write-host "DOCUMENTATION ONLY: $service - $($LeftOver.Actions)"
			}
		}
	}
}
Write-Progress -Activity $Activity -PercentComplete 100 -Completed -ID 1

if ($RawDataOnly)
	{ Return $RawData }  # we should never get here as this case exits above
elseif ($ServicesOnly)
	{ Return $Services }
elseif ($Extended)
	{ Return $Results | Sort-Object -Property ServiceName,Action }
else 
	{ Return ($Results | Sort-Object -Property ServiceName,Action | Select-Object -Property * -ExcludeProperty StringPrefix,ARNFormat,ARNRegex,HasResource ) }

	
# $Results | Out-GridView -Title "AWS Services"	# DEBUG
