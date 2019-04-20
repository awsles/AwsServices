# AwsServices
List of AWS Services and Actions in CSV format.

# Description
This repository contains two CSV files which document the various AWS services as well as the
actions used in policy permissions. This is quite useful when doing policy and role planning
to be able to see all actions in one place. 

Comment lines in the CSV (including the header at the top) start with a hastag (#).  The date
when the data was scraped along with the row count may be found at the bottom of each CSV.

Unfortunately, there is no API to retrieve this data. The data is collected by reading the JavaScript
assets used by the AWS Policy Generator at https://awspolicygen.s3.amazonaws.com/policygen.html. 
In turn, the respective documentation pages are also scraped for the description and access level information.

The AWS documentation may be found at:
https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_actions-resources-contextkeys.html

# Anomalies
In scraping the data, a few anomalies have been observed:

* The service prefix 'Ses' appears twice: once for the 'Amazon Pinpoint Email Service' and
again for 'Amazon SES'.  This idosyncracy carries through to the IAM policy creator.

* The 'ses:CreateConfigurationSet' appears several times as a result of the above.

# Script
The data is generated using a small PowerShell script which outputs the two CSVs.
I will publish the script here soon.

## Next Steps
Ideally, I would like to have the Resource Types,	Condition Keys, and	Dependent Actions included
in the actions CSV. It is possible to scrape this from the documentation page but this is a bit
more tedious, given the use of HTML column spans.
