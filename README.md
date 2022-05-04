# AwsServices
List of AWS Services and IAM Actions in CSV format.
Formatted text versions are also included for browsing.

Useful for anyone responsible for managing AWS IAM role and policy definitions.

## Description
This repository contains two CSV files which document the various AWS services with the
actions used in policy permissions. This is quite useful when doing policy and role planning
to be able to see all actions in one place. The script which generates this is also here.

Comment lines in the CSV (including the header at the top) start with a hastag (#).  The date
when the data was scraped along with the row count may be found at the bottom of each CSV.

Unfortunately, there is no API to retrieve the complete list of services or their respective operations
the data must be collected on a *best effort* basis by reading one of the JavaScript assets used by the
AWS Policy Generator at https://awspolicygen.s3.amazonaws.com/policygen.html.
In addition, the respective documentation pages are also scraped for the description and access level information.
The documentation page is also scanned for any actions that may not appear in the javascript asset list.

The AWS documentation may be found at:
https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_actions-resources-contextkeys.html

The list of AWS Policy Global Condition keys may be found at:
https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#AvailableKeys

A similar script for Azure permissions may be found at:
https://github.com/leswaters/AzureServices

## Anomalies
In scraping the data, a few anomalies have been observed with the original source data and/or documentation:

* The service prefix '**Ses**' appears twice: once for the '**Amazon Pinpoint Email Service**' and
again for '**Amazon SES**'.  This idosyncracy carries through to the IAM policy creator.

* The 'ses:CreateConfigurationSet' appears several times as a result of the above.

* Sometimes actions are not found in the corresponding documentation pages. This usually occurs when changes
are out of sync between the documentation and the input to the policy generator.
  These are noted in the CSV.

---
# Script
The data is generated using a PowerShell script which outputs the data for the two CSVs.
The code isn't fancy but it is functional. Enhancements & suggestions are welcomed!

### Script Parameters

* **-ServicesOnly**
  If indicated, then only the services are returned along with the top level documentation URL.
  Useful for getting a quick list of AWS services.

* **-RawDataOnly**
	If indicated, then the raw data from the JavaScript object is returned.  This is useful
	as it contains information about ARNs, associated RegEx, etc.
  
* **-ScanDocumentation**
	If indicated, then the documentation page is scanned for actions which did not
	appear in the AWS javascript scrape.  This is MUCH slower but yields more complete results.
  
* **-Extended**
	If indicated, returns extended information (WORK IN PROGRESS).
  
* **-AddNote**
	If indicated, then a note row is added to the structure as the first item (useful if piping to a CSV).
	
### Usage Examples

TO SEE A QUICK VIEW:

``.\Get-AwsServices.ps1 | Out-GridView``
	
TO GET A CSV:

``.\Get-AwsServices.ps1 -AddNote | Export-Csv -Path 'AwsServiceActions.csv' -force``
		
TO CONVERT CSV TO FORMATTED TEXT:

``"{0,-56} {1,-80} {2,-23} {3}" -f 'ServiceName','Action','AccessLevel','Description' | out-file -FilePath 'AwsServiceActions.txt' -Encoding utf8 -force -width 210; Import-Csv -Path 'AwsServiceActions.csv' | foreach { ("{0,-56} {1,-80} {2,-23} {3}" -f $_.ServiceName, $_.Action, $_.AccessLevel, $_.Description) } | out-file -FilePath 'AwsServiceActions.txt' -width 210 -Encoding utf8 -Append``

TO SEE A LIST OF SERVICES:

``.\Get-AwsServices.ps1 -ServicesOnly``
	
TO SEE A LIST OF ACTIONS FOR A SERVICE:

``(.\Get-AwsServices.ps1 -RawDataOnly).ServiceMap."Amazon Redshift".Actions   # All Amazon Redshift actions``

### Next Steps
The next step is to put some automation around my script so that this repository is automatically
updated regularly or when any changes are detected. I also plan to start tracking additions & deletions
to the actions and mark them accordingly (handy to see what's new and what has been depricated).

Also, I would like to have the Resource Types, Condition Keys, and Dependent Actions included
in the actions CSV. It is possible to scrape this from the documentation page but this is a bit
more tedious, given the use of HTML column spans.

---
# References
* _Understanding AWS Policies_ - https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_understand.html
