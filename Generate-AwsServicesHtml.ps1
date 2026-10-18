#Requires -Version 5.1
<#
.SYNOPSIS
    Generate a self-contained, browsable HTML catalog of AWS services and IAM actions.

.DESCRIPTION
    Reads AwsServices.csv and AwsServiceActions.csv and generates one HTML section
    per service. Each section shows ARNFormat, ARNRegEx, HasResource, and DocLink,
    followed by an expandable table of Action, Description, AccessLevel, DocLink2.

    Records are joined on ServiceName, NOT ServiceShortName, because multiple
    services can share the same short name.

    No AWS credentials or PowerShell modules are required.

.EXAMPLE
    .\Generate-AwsServicesHtml.ps1

.EXAMPLE
    .\Generate-AwsServicesHtml.ps1 -ServicesCsv .\AwsServices.csv `
        -ActionsCsv .\AwsServiceActions.csv -OutputHtml .\AwsServiceActions.html
#>
[CmdletBinding()]
param(
    [string]$ServicesCsv = (Join-Path (Get-Location).Path 'AwsServices.csv'),
    [string]$ActionsCsv  = (Join-Path (Get-Location).Path 'AwsServiceActions.csv'),
    [string]$OutputHtml  = (Join-Path (Get-Location).Path 'AwsServiceActions.html')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Encode-Html {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Format-DocLink {
    param([AllowNull()][string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return '<span class="missing">—</span>'
    }

    # Restrict clickable links to safe, absolute HTTP(S) URLs.
    [Uri]$parsed = $null
    $safeUrl = Encode-Html $Url
    if ([Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$parsed) -and
        ($parsed.Scheme -eq 'https' -or $parsed.Scheme -eq 'http')) {
        return '<a href="' + $safeUrl + '" target="_blank" rel="noopener noreferrer">' + $safeUrl + '</a>'
    }
    return '<code>' + $safeUrl + '</code>'
}

foreach ($file in @($ServicesCsv, $ActionsCsv)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Input CSV not found: $file"
    }
}

# Load the relatively small service file and check its exact schema.
$services = @(Import-Csv -LiteralPath $ServicesCsv -Encoding UTF8 | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.ServiceName) -and
    -not $_.ServiceName.TrimStart().StartsWith('#')
})
if ($services.Count -eq 0) { throw 'AwsServices.csv contains no service records.' }

foreach ($column in @('ServiceName', 'ServiceShortName', 'ARNFormat', 'ARNRegex', 'HasResource', 'DocLink')) {
    if ($null -eq $services[0].PSObject.Properties[$column]) {
        throw "AwsServices.csv is missing the required column '$column'."
    }
}

# Stream the much larger actions CSV into lists indexed by exact ServiceName.
# The dictionary uses case-insensitive comparisons, but never groups on short name.
$actionsByService = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[object]]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$actionCount = 0
$actionSchemaChecked = $false

Import-Csv -LiteralPath $ActionsCsv -Encoding UTF8 | ForEach-Object {
    $action = $_
    if (-not $actionSchemaChecked) {
        foreach ($column in @('ServiceName', 'Action', 'Description', 'AccessLevel', 'DocLink2')) {
            if ($null -eq $action.PSObject.Properties[$column]) {
                throw "AwsServiceActions.csv is missing the required column '$column'."
            }
        }
        $actionSchemaChecked = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($action.ServiceName) -and
        -not [string]::IsNullOrWhiteSpace($action.Action) -and
        -not $action.ServiceName.TrimStart().StartsWith('#')) {
        $name = $action.ServiceName.Trim()
        if (-not $actionsByService.ContainsKey($name)) {
            $actionsByService.Add($name, [System.Collections.Generic.List[object]]::new())
        }
        $actionsByService[$name].Add($action)
        $actionCount++
    }
}
if (-not $actionSchemaChecked) { throw 'AwsServiceActions.csv contains no rows (or is missing its header).' }

$services = @($services | Sort-Object -Property ServiceName, ServiceShortName)
$serviceNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($service in $services) { [void]$serviceNames.Add($service.ServiceName.Trim()) }

$unmatchedNames = @($actionsByService.Keys | Where-Object { -not $serviceNames.Contains($_) } | Sort-Object)
$unmatchedCount = 0
foreach ($name in $unmatchedNames) { $unmatchedCount += $actionsByService[$name].Count }

$outputFile = [System.IO.Path]::GetFullPath($OutputHtml)
$outputDir = [System.IO.Path]::GetDirectoryName($outputFile)
if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
    throw "Output directory does not exist: $outputDir"
}

# Stream directly to disk so the final multi-megabyte HTML need not be held in memory.
$utf8 = [System.Text.UTF8Encoding]::new($false)
$writer = [System.IO.StreamWriter]::new($outputFile, $false, $utf8)
try {
    $htmlHeader = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AWS Services and IAM Actions Catalog</title>
<style>
  :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif; }
  * { box-sizing: border-box; }
  body { background: #f4f6fa; color: #182230; margin: 0; line-height: 1.5; }
  .container { max-width: 1500px; margin: 0 auto; padding: 22px; }
  header { margin-bottom: 22px; }
  h1 { font-size: 1.8rem; margin: 0 0 4px; }
  .subtle { color: #566273; margin: 0 0 16px; }
  label { display: block; font-weight: 600; margin-bottom: 6px; }
  #serviceFilter { width: 100%; max-width: 560px; padding: 10px 12px; font-size: 1rem; border: 1px solid #b5c0cf; border-radius: 6px; }
  .service { background: #fff; border: 1px solid #d7dfe9; border-radius: 8px; margin: 0 0 20px; padding: 16px 20px 18px; }
  h2 { font-size: 1.25rem; margin: 0 0 12px; color: #182c48; overflow-wrap: anywhere; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  th, td { border: 1px solid #dce2ea; padding: 8px 10px; text-align: left; vertical-align: top; overflow-wrap: anywhere; }
  th { background: #eaf0f7; }
  tbody tr:nth-child(even) { background: #f8fafc; }
  .attributes td:first-child { width: 160px; font-weight: 600; background: #f1f5fa; }
  code { font-family: Consolas, "Liberation Mono", monospace; white-space: pre-wrap; overflow-wrap: anywhere; font-size: .9em; }
  a { color: #075a9e; }
  a:hover { text-decoration: none; }
  .missing { color: #6c7682; }
  details { margin-top: 14px; }
  summary { cursor: pointer; font-weight: 650; padding: 9px 12px; background: #eaf0f7; border-radius: 5px; }
  details[open] summary { margin-bottom: 10px; }
  .actions th:nth-child(1) { width: 18%; }
  .actions th:nth-child(2) { width: 47%; }
  .actions th:nth-child(3) { width: 12%; }
  .actions th:nth-child(4) { width: 23%; }
  .no-results { margin: 18px 0; }
  [hidden] { display: none !important; }
  @media (max-width: 700px) {
    .container { padding: 12px; }
    .service { padding: 12px; }
    .attributes td:first-child { width: 112px; }
    .actions { font-size: .82rem; }
    .actions th, .actions td { padding: 6px 4px; }
  }
</style>
</head>
<body>
<div class="container">
<header>
  <h1>AWS Services and IAM Actions Catalog</h1>
'@
    $writer.WriteLine($htmlHeader)

    $writer.WriteLine('  <p class="subtle">' + $services.Count + ' services · ' + ($actionCount - $unmatchedCount) + ' matched IAM actions · Generated ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '</p>')
    $writer.WriteLine('  <label for="serviceFilter">Find a service</label>')
    $writer.WriteLine('  <input type="search" id="serviceFilter" placeholder="Search by service name or prefix..." autocomplete="off">')
    $writer.WriteLine('</header>')

    foreach ($service in $services) {
        $name = $service.ServiceName.Trim()
        $prefix = [string]$service.ServiceShortName
        $heading = $name + ' (' + $prefix + ')'
        $encodedHeading = Encode-Html $heading
        $filterText = Encode-Html ($heading.ToLowerInvariant())

        $serviceActions = @()
        if ($actionsByService.ContainsKey($name)) {
            $serviceActions = @($actionsByService[$name] | Sort-Object -Property Action)
        }

        $writer.WriteLine('<section class="service" data-search="' + $filterText + '">')
        $writer.WriteLine('  <h2>' + $encodedHeading + '</h2>')
        $writer.WriteLine('  <table class="attributes"><tbody>')
        $writer.WriteLine('    <tr><td>ARNFormat</td><td><code>' + (Encode-Html $service.ARNFormat) + '</code></td></tr>')
        $writer.WriteLine('    <tr><td>ARNRegEx</td><td><code>' + (Encode-Html $service.ARNRegex) + '</code></td></tr>')
        $writer.WriteLine('    <tr><td>HasResource</td><td>' + (Encode-Html $service.HasResource) + '</td></tr>')
        $writer.WriteLine('    <tr><td>DocLink</td><td>' + (Format-DocLink $service.DocLink) + '</td></tr>')
        $writer.WriteLine('  </tbody></table>')

        $writer.WriteLine('  <details>')
        $writer.WriteLine('    <summary>Actions (' + $serviceActions.Count + ')</summary>')
        $writer.WriteLine('    <table class="actions"><thead><tr><th>Action</th><th>Description</th><th>AccessLevel</th><th>DocLink2</th></tr></thead><tbody>')

        if ($serviceActions.Count -eq 0) {
            $writer.WriteLine('      <tr><td colspan="4" class="missing">No actions found for this service in AwsServiceActions.csv.</td></tr>')
        }
        else {
            foreach ($action in $serviceActions) {
                $writer.WriteLine('      <tr><td><code>' + (Encode-Html $action.Action) + '</code></td><td>' +
                    (Encode-Html $action.Description) + '</td><td>' +
                    (Encode-Html $action.AccessLevel) + '</td><td>' +
                    (Format-DocLink $action.DocLink2) + '</td></tr>')
            }
        }

        $writer.WriteLine('    </tbody></table>')
        $writer.WriteLine('  </details>')
        $writer.WriteLine('</section>')
    }

    $htmlFooter = @'
<p id="noResults" class="no-results" hidden>No matching services.</p>
</div>
<script>
(function () {
    'use strict';
    const filter = document.getElementById('serviceFilter');
    const sections = document.querySelectorAll('section.service');
    const noResults = document.getElementById('noResults');
    filter.addEventListener('input', function () {
        const query = filter.value.trim().toLocaleLowerCase();
        let matches = 0;
        sections.forEach(function (section) {
            const visible = section.dataset.search.includes(query);
            section.hidden = !visible;
            if (visible) matches++;
        });
        noResults.hidden = (matches !== 0);
    });
}());
</script>
</body>
</html>
'@
    $writer.WriteLine($htmlFooter)
}
finally {
    $writer.Dispose()
}

Write-Host "Generated: $outputFile"
Write-Host "Services: $($services.Count); matched actions: $($actionCount - $unmatchedCount)"
if ($unmatchedCount -gt 0) {
    Write-Warning "$unmatchedCount action records were not included because their ServiceName did not match any service in AwsServices.csv."
    Write-Warning ("Unmatched service names: " + ($unmatchedNames -join ', '))
}
