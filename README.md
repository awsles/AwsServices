# AwsServices
List of AWS Services and Actions

# Description
This repository contains two CSV files which document the various AWS services as well as the
actions used in policy permissions.  Comment lines in the CSV (including the header at the top)
start with a hastag (#).  The date when the data was scraped along with the row count may be
found at the bottom of each CSV.

Unfortunately, there is no API to retrieve this data. The data is collected by reading the JavaScript
assets used by the AWS Policy Generator at https://awspolicygen.s3.amazonaws.com/policygen.html. 
In turn, the respective documentation pages are also scraped for the description and access level information.

# Anomalies
In scraping the data, a few anomalies have been observed:

* The service short name 'Ses' appears twice: once for the 'Amazon Pinpoint Email Service' and
again for 'Amazon SES'.  This idosyncracy carries through to the IAM policy creator.

* The 'ses:CreateConfigurationSet' appears several times as a result of the above.

# Script
The data is generated using a small PowerShell script which outputs the two CSVs.
I will publish the script here soon.
