# AwsServices
List of AWS Services and Actions in CSV format.
Formatted text versions are also included for browsing.

## Description
This repository contains two CSV files which document the various AWS services as well as the
actions used in policy permissions. This is quite useful when doing policy and role planning
to be able to see all actions in one place. 

Comment lines in the CSV (including the header at the top) start with a hastag (#).  The date
when the data was scraped along with the row count may be found at the bottom of each CSV.

Unfortunately, there is no API to retrieve this data. The data is collected by reading the JavaScript
assets used by the AWS Policy Generator at https://awspolicygen.s3.amazonaws.com/policygen.html. 
In turn, the respective documentation pages are also scraped for the description and access level information.
The documentation page is also scanned for any actions that may not appear in the javascript source.

The AWS documentation may be found at:
https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_actions-resources-contextkeys.html

## Anomalies
In scraping the data, a few anomalies have been observed with the original source data and/or documentation.

* The service prefix 'Ses' appears twice: once for the 'Amazon Pinpoint Email Service' and
again for 'Amazon SES'.  This idosyncracy carries through to the IAM policy creator.

* The 'ses:CreateConfigurationSet' appears several times as a result of the above.

* Roughly 29 actions were not found in the corresponding documentation page.
  These are noted in the CSV.

---
# Script
The data is generated using a PowerShell script which outputs the two CSVs.
The code isn't fancy but it is functional. Enhancement suggestions are welcomed!

### Script Parameters

* **-ServicesOnly**
  If indicated, then only the services are returned along with a (guessed) documentation URL.

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

### Next Steps
Ideally, I would like to have the Resource Types, Condition Keys, and Dependent Actions included
in the actions CSV. It is possible to scrape this from the documentation page but this is a bit
more tedious, given the use of HTML column spans.
