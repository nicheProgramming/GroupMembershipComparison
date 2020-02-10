# Stores the values of each group member's other group memberships
$masterMembershipList = @{} # Hashtable that keeps a list of group memberships and number of members from keyGroup in each group
$removedGroups = @() # Stores groups removed from the master membership list in memory, good for debugging
$dataStore = @{} # Hashtable keeps all the user info gathered in this script, where the key is the userID

Class User {
    [String]$userID # This should hold the unique value that the user can be identified by
    [String]$userName
    $groupMemberships = @()
    $uniqueGroups = @()
}    

# Rebuilds masterMembershipList without parameter
function rebuildMasterMembershipList {
    Param($removeGroup) # Group to be removed from list
    
    foreach ($group_item in $masterMembershipList) {
        if ($group_item -ne $removeGroup) {
            $newMembershipList += $group_item
        } elseif ($group_item -eq $removeGroup) {
            $global:removedGroups += $group_item
        }    
    }    
    
    $masterMembershipList = $newMembershipList
}    

$keyUser = [User]::new()
# Get username from script executor
$keyUser.userID = Read-Host 'Enter the employee ID of the user who needs access'
# Stores all groups $keyUser is a member of by name, alphabetically
$keyUser.groupMemberships = Get-ADPrincipalGroupMembership $keyUser.userID | Select-Object name
$keyUser.groupMemberships = $keyUser.groupMemberships | Sort-Object

# This must be (afaik) a character for 
$keyGroup = Read-Host "Enter the name of the group you wish to check the user's access against"

# Grabs array of group members
$groupMembers = Get-ADGroupMember -identity $keyGroup -Recursive | Get-ADUser -Property DisplayName | Select-Object SamAccountName

# For each group member, identify groups the member belongs to
foreach ($member in $groupMembers) {
    $newUser = [User]::new()
    $newUser.userID = $member.SamAccountName

    # Grabs the current key group member's other group memberships by name and adds them to the list alphabetically
    $newUser.groupMemberships = Get-ADPrincipalGroupMembership $newUser.userID | Select-Object SamAccountName
    $newUser.groupMemberships = $newUser.groupMemberships.SamAccountName | Sort-Object

    foreach ($group in $newUser.groupMemberships) {
        # If someone already has this group, keep count of how many members this group has in common
        if ($masterMembershipList.ContainsKey("$($group)")) {
            $masterMembershipList["$($group)"] += 1
        } else {
            # Otherwise, start off the count of members
            $masterMembershipList["$($group)"] = 1
        }
    }

    # Grabs full name (LN, FN) from AD field
    $currentUserFullName = Get-ADUser -Filter {samaccountname -eq $newUser.userID} | Select-Object Name

    # Puts all the data we can gather on the user right now into a hashtable for later conversion to CSV
    $dataStore["$($newUser.userID)"] = (
        $currentUserFullName.Name, 
        @($newUser.groupMemberships), 
        @(), # Unique Group Memberships will go here in next loop
        $newUser.groupMemberships.Count,
        0) # Stores number of unique groups in next loop
}

# Iterate through each user and get their unique groups
foreach ($user in $dataStore.Keys) {
    foreach ($group in $dataStore["$($user)"][1]) {
        # If the group made it to the masterlist (it always should) and only 1 person has it, it is unique. 
        if ($masterMembershipList.ContainsKey("$($group)") -and $masterMembershipList["$($group)"] -eq 1) {
            $dataStore["$($user)"][2] += $group
            $dataStore["$($user)"][4] += 1
        }
    }
}

# Go through all the data we gathered in the hashtable and put it in a CSV
($dataStore.Keys | ForEach-Object {
    [PSCustomObject]@{
        FullName = $dataStore[$_][0]
        UserName = $_
        TotalGroupMemberships = $dataStore[$_][3]
        UniqueGroupMemberships = $dataStore[$_][4]
        # I use newlines here so the group membership lists don't go out forever to the right of the spreadsheet
        UniqueGroups = (@($dataStore[$_][2]) -join ",`r`n")
        AllGroupMemberships = (@($dataStore[$_][1]) -join ",`r`n")
    }
} |
# Put spreadsheet in alphabetical order by lastname
Sort-Object -Property @{Expression = "FullName"; Descending = $False} |
Export-Csv -Path $env:USERPROFILE\Desktop\Comparison.csv -NoTypeInformation)