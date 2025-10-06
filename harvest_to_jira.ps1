#IMPORTANT: IN JIRA, THE ISSUE ID MUST BE AT THE START OF THE NOTES FIELD IN HARVEST

# ------ add below $Global variables to your profile.ps1 file (less secure: or just adjust them here)-------
# dates to populate into Jira
# set these to the range you want to sync from harvest to Jira
# MAKE SURE you don't have any time entries already in Jira for these dates
# I honestly don't know what happens if you try to post a worklog for a date that already has one,
# It probably adds a duplicate time entry?, but I haven't tested it
# format: YYYY-MM-DD
$Global:StartDate = "2025-09-01" # Start date for time entries
$Global:EndDate = "2025-10-01" # End date for time entries
        
# Harvest configuration
# You can get this from https://id.getharvest.com/developers/apps
$Global:AccessToken = "<your harvest access token here>"  # Your Harvest Access Token
$Global:AccountId = "<your harvest account id here>"  # Your Harvest Account ID
$Global:UserAgent = "HarvestTimeFetcher (yourname@yourcompany.com)"

# Jira configuration
$Global:JiraBaseUrl = "https://yourcompany.atlassian.net"  
$Global:JiraEmail = "youremailusedinjiraprofile@yourcompany"                    
$Global:JiraApiToken = "yourextralongjiraapitokengoeshere"           # Your API token

# This is the pattern used for extracting jira task id from harvest hours entries 
$Global:JiraPattern = '^([A-Za-z][A-Za-z0-9]*-\d+)(?=\D|$)'
#----------------------------------------------------------------------------------------------------
function Get_timesheets {
    param (
        $AccessToken = $Global:AccessToken,
        $AccountId = $Global:AccountId ,
        $StartDate = $Global:StartDate,
        $EndDate = $Global:EndDate,
        $UserAgent = $Global:UserAgent
    )
    # API endpoint
    $BaseUrl = "https://api.harvestapp.com/v2/time_entries"
    # Headers for authentication
    $Headers = @{
        "Authorization"      = "Bearer $AccessToken"
        "Harvest-Account-Id" = $AccountId
        "User-Agent"         = $UserAgent
    }
    $Page = 1
    $AllEntries = @()
    do {
        $Params = @{
            from     = $StartDate
            to       = $EndDate
            per_page = 100
            page     = $Page
        }

        $QueryString = ($Params.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
        $Uri = $BaseUrl + "?" + $QueryString

        Write-Host "`nDEBUG: URI = $Uri"
        Write-Host "DEBUG: Headers = $($Headers | Out-String)"
        $Response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get
        $Entries = $Response.time_entries

        if ($Entries.Count -gt 0) {
            $AllEntries += $Entries
            $Page++
        }
        else {
            break
        }
    } while ($true)
    Write-Host "Retrieved $($AllEntries.Count) time entries from $StartDate to $EndDate."
    $Global:harvestTimes = $AllEntries | ForEach-Object {
        [PSCustomObject]@{
            Hours     = $_.hours
            Notes     = $_.notes
            SpentDate = $_.spent_date
        }
    }
} 

function harvest_times_to_jira { 

    # Updated regex to match your Jira ID format at the start
    $jiraPattern = $Global:JiraPattern

    # Filtered output
    $Global:FilteredEntries = @()

    foreach ($entry in $Global:harvestTimes) {
        $notes = $entry.notes

        if ($notes -match $jiraPattern) {
            $jiraId = $matches[1]  # Extracted from the regex capture group
            $Global:FilteredEntries += [PSCustomObject]@{
                JiraTaskID = $jiraId
                Date       = $entry.SpentDate
                Hours      = $entry.hours
            }
        }
    }
    $Global:FilteredEntries | Format-Table JiraTaskID, Date, Hours -AutoSize
}
function Post_JiraWorklog {
    param(
        [string]$JiraBaseUrl = $Global:JiraBaseUrl,  
        [string]$JiraEmail = $Global:JiraEmail,                     
        [string]$JiraApiToken = $Global:JiraApiToken
    )
    Write-Host "=== Starting Jira Worklog Upload ===" -ForegroundColor Cyan
    Write-Host "Constructing Basic Auth header..." -ForegroundColor Cyan
    try {
        $pair = "$JiraEmail`:$JiraApiToken"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
        $base64 = [Convert]::ToBase64String($bytes)
        $JiraHeaders = @{
            "Authorization" = "Basic $base64"
            "Content-Type"  = "application/json"
        }
        Write-Host "Authorization header ready." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to build auth header: $_"
        exit 1
    }
    #Convert decimal hours (i.e 1.5) into "1h 30m"
    function Convert_ToJiraTimeSpent {
        param([double]$hours)
        Write-Host "Converting $hours hours to Jira format..." -ForegroundColor Cyan

        if ($hours -le 0) {
            Write-Host "  → Zero or negative; returning '0m'" -ForegroundColor Yellow
            return "0m"
        }
        $whole = [math]::Floor($hours)
        $minutes = [math]::Round(($hours - $whole) * 60)
        if ($minutes -ge 60) {
            $whole++
            $minutes -= 60
        }

        $parts = @()
        if ($whole -gt 0) { $parts += "${whole}h" }
        if ($minutes -gt 0) { $parts += "${minutes}m" }
        $formatted = ($parts -join ' ')
        Write-Host "  → Converted to '$formatted'" -ForegroundColor Green
        return $formatted
    }
    # Post function for each worklog entry
    function Post_JiraWorklog {
        param(
            [string]   $IssueKey,
            [DateTime] $WorkDate,
            [double]   $Hours
        )
        Write-Host "`nPosting worklog for issue $IssueKey on $($WorkDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
        # Timestamp at 09:00 UTC, with +0000 ugh, I hate this
        $utcStart = [DateTime]::new(
            $WorkDate.Year, $WorkDate.Month, $WorkDate.Day,
            9, 0, 0, [DateTimeKind]::Utc
        )
        $started = $utcStart.ToString("yyyy-MM-dd'T'HH:mm:ss.fff") + "+0000"
        Write-Host "  started = $started"

        $timeSpent = Convert_ToJiraTimeSpent -hours $Hours

        $bodyObj = @{
            started   = $started
            timeSpent = $timeSpent
        }
        $bodyJson = $bodyObj | ConvertTo-Json -Depth 3
        Write-Host "  Payload:" 
        Write-Host $bodyJson

        $url = "$JiraBaseUrl/rest/api/3/issue/$IssueKey/worklog"
        Write-Host "  POST $url"

        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $JiraHeaders -Body $bodyJson
            Write-Host "Successfully logged $timeSpent to $IssueKey." -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Response.StatusCode.Value__ -eq 404) {
                Write-Warning "Issue $IssueKey not found in Jira. Skipping."
            } else {
                Write-Warning "Failed to log time for $IssueKey"
                Write-Warning "Status: $($_.Exception.Response.StatusCode.Value__) ($($_.Exception.Response.StatusCode))"
                if ($_.ErrorDetails) {
                    Write-Warning "Jira error: $($_.ErrorDetails.Message)"
                } else {
                    Write-Warning "Exception: $($_.Exception.Message)"
                }
            }
            # Do NOT exit or throw here; just continue to next entry
        }
    }
    # Where the magic happens
    if (-not $Global:FilteredEntries) {
        Write-Error "No entries found in `$Global:FilteredEntries`. Nothing to post."
        exit 1
    }
    foreach ($entry in $Global:FilteredEntries) {
        try {
            $dateObj = [DateTime]::Parse($entry.Date)
            Post_JiraWorklog `
                -IssueKey $entry.JiraTaskID `
                -WorkDate $dateObj `
                -Hours   $entry.Hours
        }
        catch {
            Write-Error "Error processing entry for $($entry.JiraTaskID): $($_.Exception.Message)"
        }
    }
    Write-Host "`n=== Finished Jira Worklog Upload ===" -ForegroundColor Cyan
}

# After setting the global variables above, uncomment the line below to run the script
# Or just run each function one at a time to see what is happening
# Or leave it commented out and just call the functions manually in the right order from your PWSH/PowerShell console

#uncomment the line below to run the whole process, !! be sure your global variables are set correctly above !!
# Get_timesheets && harvest_times_to_jira && Post_JiraWorklog