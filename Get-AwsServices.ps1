#Requires -Version 5.1
<#
.SYNOPSIS
	Returns AWS policy actions as a structure.
.DESCRIPTION
	Return a structure containing an entry for each service and action.
	This works by reading the JavaScript assets used by the AWS Policy Generator
	at https://awspolicygen.s3.amazonaws.com/policygen.html. 
	The documentation page is also scraped for the description and access level information.
	This script is necessary as there is (unfortunately) no AWS API which returns this information.

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
		.\Get-AwsPolicies.ps1 | Out-GridView
	
	TO GET A CSV:
		.\Get-AwsPolicies.ps1 -AddNote | Export-Csv -Path 'AwsActions.csv' -force

	TO SEE A LIST OF SERVICES:
		.\Get-AwsPolicies.ps1 -ServicesOnly
	
	TO SEE A LIST OF ACTIONS FOR A SERVICE:
		(.\Get-AwsPolicies.ps1 -RawDataOnly).ServiceMap."Amazon Redshift".Actions   # All Amazon Redshift actions

.NOTES
	Author: Lester W.
	Version: v0.17
	Date: 20-Apr-19
	Repository: https://github.com/lesterw1/AwsServices
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
	[string] $ARNFormat				# Extended
	[string] $ARNRegex				# Extended
	[string] $HasResource			# Extended
}


# +=================================================================================================+
# |  CONSTANTS																						|
# +=================================================================================================+
$AwsPolicyJs	= "https://awspolicygen.s3.amazonaws.com/js/policies.js"
$AwsDocRoot		= "https://docs.aws.amazon.com/IAM/latest/UserGuide/list_%SERVICE%.html"


# +=================================================================================================+
# |  LOGIN		              																		|
# +=================================================================================================+
# Needed to ensure default credentials are in place for Proxy
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
	write-verbose "Service: $service"
	$pctComplete = [string] ([math]::Truncate((++$ctr / $ServiceList.Count)*100))
	Write-Progress -Activity $Activity -PercentComplete $pctComplete  -Status "$service - $pctComplete% Complete  ($ctr of $($ServiceList.Count))" -ID 1
	
	# Get the specific Item
	$ServiceItem = $RawData.ServiceMap.$service
	
	# Cleanup Name
	$ServiceKeyName = $service.ToLower().Replace(' ','').Replace('(','').Replace(')','')
	
	# Guess Documentation Page and retrieve it
	$DocPage				= $AwsDocRoot.Replace('%SERVICE%', $ServiceKeyName)
	
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
	
	if (!$ServicesOnly)
	{
		# Grab the documentation page
		if ($ScanDocumentation)
		{
			$WebResponse2 		= Invoke-WebRequest -uri $DocPage -UseDefaultCredentials 
			# DO NOT SPECIFY -UseBasicParsing		
		}
		else
		{
			$WebResponse2 		= Invoke-WebRequest -uri $DocPage -UseDefaultCredentials -UseBasicParsing
		}

		# Extract Content
		$Content2				= $WebResponse2.Content										# Get HTML content
		$ActionsIndex			= $Content2.IndexOf('<th>Actions</th>')						# Marker we use
		$TableIndex				= $Content2.IndexOf('<table', $ActionsIndex-300)			# Go back a bit to find start
		$TableBody				= $Content2.SubString($TableIndex)							# Start of Actions Table
		$TableBody				= $TableBody.SubString(0, $TableBody.IndexOf('</table>')+8)	# Capture Table
		## Extract Table ID
		$TableId				= $TableBody.SubString($TableBody.IndexOf(' id="')+5)
		$TableId				= $TableId.SubString(0, $TableId.IndexOf('"'))
		write-verbose "TableId: $TableId"
		
		## Scan the documentation page (if requested)
		if ($ScanDocumentation)
		{
			# Extract table elements into DocumentedActions()
			# This allows us to eliminate actions that we see, leaving only those that weren't in the JavaScript
			# We conveniently use the ParsedHtml property returned by Invoke-WebRequest.
			## Extract the tables out of the web request
			$table = $WebResponse2.ParsedHtml.getElementById($TableId)
			# $tables = @($WebResponse2.ParsedHtml.getElementsByTagName("TABLE"))		# OLD APPROACH
			# $table = $tables[1]														# **ASSUME* 2nd Table...
		
			# This is MESSY for tables which have rowspans...
			$titles = @()
			$rows = @($table.Rows)
			$DocTable = @()
			$RowSpan = [int32] 1		# Assume no rowspan
			## Go through all of the rows in the table
			foreach($row in $rows)
			{
				# If we have a previous rowspan > 1, then count down
				if ($RowSpan -gt 1)
				{
					$rowspan--
					continue
				}
			
				# Check $row.innerHTML for rowspan=xxx so we can skip subsequent rows as needed...
				$RowSpan = [int32] 1		# Assume no rowspan
				$RowSpanIndex = $row.InnerHTML.ToLower().IndexOf(' rowspan=')
				if ($RowSpanIndex -gt 0)
				{
					# TBD
					$RowSpanTxt	= $row.InnerHTML.SubString($RowSpanIndex + 9)
					$RowSpan	= [int32] $RowSpanTxt.SubString(0,$RowSpanTxt.IndexOf('>'))  # CAREFUL! Could be a space!!
				}
				
				# Extract Cells
				$cells = @($row.Cells)

				## If we've found a table header, remember its titles
				if($cells[0].tagName -like "TH")
				{
					$titles = @($cells | % { ("" + $_.InnerText).Trim() })
					continue
				}

				## If we haven't found any table headers, make up names "C1", "C2", etc.
				if(-not $titles)
				{
					$titles = @(1..($cells.Count + 2) | % { "C$_" })
				}

				## Now go through the cells in the the row. For each, try to find the
				## title that represents that column and create a hashtable mapping those
				## titles to content
				$resultObject = [Ordered] @{}
				for($counter = 0; $counter -lt $cells.Count; $counter++)
				{
					$title = $titles[$counter]
					if(-not $title) { continue }
					$resultObject[$title] = ("" + $cells[$counter].InnerText).Trim()
				}

				## And finally cast that hashtable to a PSCustomObject
				$DocTable += [PSCustomObject] $resultObject
			}
			# $DocTable has the results
		}
	
		# Loop through each Action
		foreach ($action in $ServiceItem.Actions)
		{
			# Eliminate action entries in $DocTable as we see them 
			if ($ScanDocumentation -And $DocTable)
			{
				$x = [ref] ($DocTable | Where-Object {$_.Actions -like $action} )					# Get By Reference!!
				if ($x.Count -gt 1) { write-warning "Multiple Actions found for $service - $action" }  
				if (!$x) { $x = [ref] ($DocTable | Where-Object {$_.Actions -like "$action *" } ) }	# catch 'action [PermissionsOnly]'
				if ($x) { $x.Value.Actions = "--"	}												# Eliminate it
			}
			
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
									   
			
			# See if we can find the Description
			$SearchId 				= $ServiceKeyName + '-' + $action
			Try
			{
				$Body3 					= $TableBody.SubString($TableBody.IndexOf($SearchId))   # Do not search for $action!
				$Body3 					= $Body3.SubString($Body3.IndexOf('<td')+3)		# Find next <td>
				$Body3					= $Body3.SubString($Body3.IndexOf('>')+1)		# Closing '>' for <td> tag 
				$Description			= $Body3.SubString(0, $Body3.IndexOf('</td>')).Trim()	# </td>
				$Entry.Description		= [regex]::Replace($Description, "\s+", " ")	# Clean up spaces
			}
			Catch
			{
				# write-host -ForegroundColor Yellow $service
				write-warning "$service - Search failed for '$SearchId' `n         PAGE: $DocPage"
				$Entry.Description		= "--- NOT FOUND ---"
				$Entry.AccessLevel		= ""
				# write-output $_
			}

			# See if we can find the Access Level (next column - start with $Body3)
			if (!$Entry.Description.StartsWith('---'))
			{
				Try
				{
					$Body4					= $Body3.SubString($Body3.IndexOf('<td')+3)
					$Body4					= $Body4.SubString($Body4.IndexOf('>')+1)		# Closing '>'
					$AccessLevel			= $Body4.SubString(0, $Body4.IndexOf('</td>')) -replace '<[^>]+>',''
					$Entry.AccessLevel		= [regex]::Replace($AccessLevel, "\s+", " ").Trim()
				}
				Catch
				{
					# write-host -ForegroundColor Yellow $service
					write-warning "$service - AccessLevel search failed for '$SearchId' `n         PAGE: $DocPage"
					$Entry.AccessLevel		= "--- ERROR ---"
					write-output $_
				}
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
	{ Return $Results }
else 
	{ Return ($Results | Select-Object -Property * -ExcludeProperty StringPrefix,ARNFormat,ARNRegex,HasResource ) }

	
# $Results | Out-GridView -Title "AWS Services"	# DEBUG
