## Harvest to Jira Worklog Sync

This repository contains a PowerShell script (`harvest_to_jira.ps1`) to sync your Harvest time entries into Jira worklogs.

### Features
- Fetches time entries from Harvest for a specified date range
- Extracts Jira issue IDs from Harvest notes
- Posts worklogs to Jira for each matching entry

---

## Usage Instructions

### 1. Configure Your Credentials
Edit the top section of `harvest_to_jira.ps1` to set your credentials and date range:

- **Harvest**: `AccessToken`, `AccountId`, `UserAgent`
- **Jira**: `JiraBaseUrl`, `JiraEmail`, `JiraApiToken`
- **Date Range**: `StartDate`, `EndDate` (format: `YYYY-MM-DD`)

You can set these as `$Global` variables in your PowerShell profile for convenience, or edit them directly in the script.

### 2. Run the Script

You can run the script step-by-step or all at once:

#### Option A: Step-by-step (recommended for first use)
```powershell
.\harvest_to_jira.ps1
Get_timesheets
harvest_times_to_jira
Post_JiraWorklog
```

#### Option B: All at once
Uncomment the last line in the script, then run:
```powershell
.\harvest_to_jira.ps1
```

### 3. Notes
- The Jira issue ID **must be at the start of the Harvest notes field** (e.g., `JT-1234: Worked on feature`).
- Make sure you do not have duplicate worklogs in Jira for the same dates.

---

## Installing PowerShell (PWSH) on Linux or Mac

This script requires PowerShell 7+ (pwsh). If you are on Linux or macOS, follow the instructions below:

### Linux (Ubuntu/Debian)
```sh
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
```
Start PowerShell:
```sh
pwsh
```

### macOS (Homebrew)
```sh
brew install --cask powershell
```
Start PowerShell:
```sh
pwsh
```

For more installation options, see: https://docs.microsoft.com/powershell/scripting/install/installing-powershell

---

## Troubleshooting
- Ensure your API tokens and account IDs are correct.
- If you see authentication errors, double-check your credentials and permissions.
- For date parsing or time zone issues, review the script's date handling logic.

---

## License
MIT
