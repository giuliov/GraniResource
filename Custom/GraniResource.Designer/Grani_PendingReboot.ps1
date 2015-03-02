Import-Module xDSCResourceDesigner
$property = @()
$property += New-xDscResourceProperty -Name Name -Type String -Attribute Key -Description "Describe Identifier Key name."
$property += New-xDscResourceProperty -Name WaitTimeSec -Type Uint32 -Attribute Write -Description "Describe wait sec before reboot."
$property += New-xDscResourceProperty -Name Force -Type Boolean -Attribute Write -Description "Force flag for Reboot"
$property += New-xDscResourceProperty -Name WhatIf -Type Boolean -Attribute Write -Description "WhatIf for Reboot execution."
$property += New-xDscResourceProperty -Name Ensure -Type String -Attribute Read -ValidateSet Present, Absent -Description "Describe desired state or not."
$property += New-xDscResourceProperty -Name ComponentBasedServicing -Type Boolean -Attribute Read -Description "Reboot required for Windows Component."
$property += New-xDscResourceProperty -Name WindowsUpdate -Type Boolean -Attribute Read -Description "Reboot required for Windows Update."
$property += New-xDscResourceProperty -Name PendingFileRename -Type Boolean -Attribute Read -Description "Reboot required for File Name update."
$property += New-xDscResourceProperty -Name PendingComputerRename -Type Boolean -Attribute Read -Description "Reboot required for ComputerName change."
$property += New-xDscResourceProperty -Name CcmClientSDK -Type Boolean -Attribute Read

New-xDscResource -Name Grani_PendingReboot -Property $property -Path .\ -ModuleName GraniResource -FriendlyName cPendingReboot -Force