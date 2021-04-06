#  ***************************************************************************************************************************************************************
#  ***************************************************************************************************************************************************************
#  Script Name: TIA_Portal_v16_VMprep.ps1
#
#  Script Purpose: This script creates a base Hyper-V VM that can run TIA Portal v16 on an engineering workstation. The script does a bit of mathmagic when it 
#                  comes to core selection with respect to converted core # and clock rates. This performance math is no where near perfect, but it is a decent  
#                  first guess. It is important to note the scope of this script is for engineering workstations only, not to set up a multi-user server instance 
#                  of TIA Portal v16. The installation requirements are sourced from Siemens Product Page No. 10314843 and common sense for remaining host specs.    
#
#  Script Author: Alex Holburn 
#
#  Website: https://www.alexholburn.com
#
#  License: MIT License Alex Holburn Copyright 2021
#  ***************************************************************************************************************************************************************
#  ***************************************************************************************************************************************************************

#  ***************************************BEGIN VARIABLE DECLARATIONS***************************************

#  File System and virtualized Hardware Paths [Users will need to edit this]
$disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object FreeSpace, DriveType     #  This is the disk your VM will be created on.
$vmName = "TIA_Portal_v16_Base"                                                                          #  This is the name of the VM to be created.
$vmPath = 'C:\Virtual_Machines\Hyper-V\'                                                                 #  This is the path to the VM 
$isoPath = 'C:\Virtual_Machines\Hyper-V\iso\your.iso'                                                    #  Windows 10 Pro Version 1809 or 1903 image.
$vhdxPath ='C:\Virtual_Machines\Hyper-V\' + $vmName + '\Virtual Hard Disks\' + $vmName + '.vhdx'         #  Path to the Virtual Hard disk
$snapshotsPath = 'C:\Virtual_Machines\Hyper-V\' + $vmName + '\Snapshots\'                                #  Path to the Snapshots


#  Recommended Hardware Variables [No need for end-users to edit this]        
$reccommendedRAM = 16GB                                                                                 #  This is the recommended RAM Required (in GB)
$largeProjectRAM = 32GB                                                                                 #  This is the recommended RAM for large projects (in GB)
$reccommendedLogicalProcessors = 4                                                                      #  Minimum number of CPU cores @ minimum processor clock rate
$recommendedCPUCores = 4                                                                                #  Reccommended number of CPU cores @ processor clock rate.
$recommendedCPUClockRate = 2.7                                                                          #  Recommended CPU Clock Rate in GHz 
$minimumDiskSpace = 55GB                                                                                #  minimum virtual disk size in GB
$reccommendedDiskSpace = $minimumDiskSpace + (.20 * $minimumDiskSpace)                                  #  Reccommended Diskspace (20% spare space)
$reccommendedPF = $reccommendedLogicalProcessors / $recommendedCPUClockRate                             #  Simplification, but a guess for processors within same family. 

#  Host Hardware Variables [No need for end-users to edit this]
$numOfCPUCores = (Get-CimInstance Win32_Processor).NumberOfCores                                            #  Number of CPU cores of the host.
$numOfLogicalProcessors =  (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors                      #  Number of Logical Processors
$installedRAM = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).sum         #  Amount of installed RAM on host.
$maxClockSpeed = (Get-WmiObject Win32_Processor | select-object -first 1).MaxClockSpeed / 1000              #  Maximum host CPU clock speed in GHz. 
$diskFreeSpace = $disk.FreeSpace                                                                            #  Amount of freespace on user specified host disk.
$diskDriveType = $disk.DriveType                                                                            #  Lets us know what kind of drive it is SSD or HDD. 
$hostRAMThreshold = 8                                                                                       #  Recommended amount of free ram on host. 

#  Virtualized Hardware Variables [No need for end-users to edit this]
$VMAssignedCores = [math]::Round($reccommendedPF * $maxClockSpeed)                                          # Rough performance equation within same family of CPUs
$nMinusOneRule = $numOfCPUCores - $VMAssignedCores                                                          # n-1 rule. You have to leave atleast one core for the host

# Global Variables [These are used so we can pass information from function to function]
$global:projectType = ''                                                                                    #  global variable for use outside of functions.
$global:installedVirtualRAM = ''                                                                            #  global variable for use outside of functions.

#  ***************************************BEGIN FUNCTION DEFINITIONS***************************************

# Elevate the PowerShell Console to Administrator privledges
function Elevate-Admin {
                       if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit } 
                       }

#  Enable the Hyper-V Windows Feature
function Enable-HyperV {
                        Write-Host "Status: Checking If Hyper-V is Installed and Enabled."
                        Write-Host `n
                        
                        if((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online).State -eq "Enabled") {
                            Write-Host "Status: PASSED, 'Hyper-V is Installed and Enabled'"                                                                                          
                            Write-Host `n 
                                                                                                                    } 
                        
                        else {
                             Write-Host "Status: 'Installing and Enabling Hyper-V'"
                             Write-Host `n

                             Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

                             if((Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online).State -eq "Enabled") {
                                 Write-Host "Status: PASSED, 'Hyper-V is Installed and Enabled'"                                                                                          
                                 Write-Host `n                                                                                                                        
                                                                                                                         }
                             else{
                                 Write-Host "Status: FAILED, 'Hyper-V Failed to Install and Enable'"
                                 Write-Host `n
                                 Reset-ExecutionPolicies
                                 Read-Host -Prompt "Press Enter to exit"
                                 }
                             }
                                               
                       }

#  Script Title ASCII Art. 
function Write-scriptTitle {
                            Write-Host "  _______ _____            _____           _        _        __   __"                 
                            Write-Host " |__   __|_   _|   /\     |  __ \         | |      | |      /_ | / /"                 
                            Write-Host "    | |    | |    /  \    | |__) |__  _ __| |_ __ _| | __   _| |/ /_"                
                            Write-Host "    | |    | |   / /\ \   |  ___/ _ \| '__| __/ _`  | | \ \ / / | '_ \"               
                            Write-Host "    | |   _| |_ / ____ \  | |  | (_) | |  | || (_| | |  \ V /| | (_) |"              
                            Write-Host "    |_|  |_____/_/    \_\ |_|   \___/|_|   \__\__,_|_|   \_/ |_|\___/"
                            Write-Host `n
                            Write-Host "  _    _                           __      __ __      ____  __   _____ "               
                            Write-Host " | |  | |                          \ \    / / \ \    / /  \/  | |  __ \ "              
                            Write-Host " | |__| |_   _ _ __   ___ _ __ _____\ \  / /   \ \  / /| \  / | | |__) | __ ___ _ __"  
                            Write-Host " |  __  | | | | '_ \ / _ \ '__|______\ \/ /     \ \/ / | |\/| | |  ___/ '__/ _ \ '_ \" 
                            Write-Host " | |  | | |_| | |_) |  __/ |          \  /       \  /  | |  | | | |   | | |  __/ |_) |"
                            Write-Host " |_|  |_|\__, | .__/ \___|_|           \/         \/   |_|  |_| |_|   |_|  \___| .__/ "
                            Write-Host "          __/ | |                                                              | |    "
                            Write-Host "         |___/|_|                                                              |_| "
                            Write-Host `n

                            
                           }

#  Shameless self-promotion. What more can I say? It's how you market yourself and get hired.
function Write-shamelessSelfPromotion {
                                       Write-Host "Like This Utility? Check Out More Controls DevOps Tools @ https://www.alexholburn.com"
                                       Write-Host `n
                                       Write-Host "-------------------------------------------------------------------------------------------------------------------"
                                       Write-Host "-------------------------------------------------------------------------------------------------------------------"
                                       Write-Host `n
                                       }

#  This guy prompts the user if the TIA Portal Project is large.
function Check-TIAProjectSize {
                                $projectSize = Read-Host -Prompt "Is the TIA Portal Project Size 'Large'? [y/n]?"
                                      
                                      Write-Host `n
                                      if ($projectSize -eq 'y') {
                                       
                                       "Status: 'Large TIA Portal Project Selected.'"
                                       Write-Host `n
                                       $global:projectType = 'Large'                   #  We set the project type to large for use later
                                       $global:installedVirtualRAM = $largeProjectRAM 
                                                          }
                                      
                                      elseif ($projectSize -eq 'n') {
                                      
                                           "Status: 'Large TIA Portal Project Not Selected.'"
                                           Write-Host `n
                                           $global:projectType = 'Not Large'    #  We set the project type to  not large for use later
                                           $global:installedVirtualRAM = $reccommendedRAM
                                                              }
                                     
                                      else {
                                     
                                         "Status: FAILED, 'Erroneous Project Size Selection!'"
                                         Reset-ExecutionPolicies
                                         Write-Host `n
                                         Read-Host -Prompt "Press Enter to exit"
                                         exit
                                           }

                              }

#  This checks if the RAM falls within the recommended values, and prompts the user if deviations present. 
function Check-RAM {
                    if ($global:projectType -eq 'Large') {
                         Write-Host "Status: Checking RAM Requirements (Large Project)."
                         Write-Host `n
                                          
                         if ($installedRAM -ge $largeProjectRAM) {
                             Write-Host "Status: PASSED, RAM Requirements met (Large Project)."
                             Write-Host `n 
                                          
                                                         }
                          else {
                                Write-Host "Status: FAILED, RAM requirements not met (Large Project)."
                                Write-Host `n
                                Read-Host -Prompt "Press Enter to exit"
                                exit
                                } 
                                                          }
                                      
                     elseif ($global:projectType -eq 'Not Large') {
                             Write-Host "Status: Checking RAM Requirements (Not Large Project)."
                             Write-Host `n

                         if ($installedRAM -ge $reccommendedRAM) {
                             Write-Host "Status: PASSED, RAM Requirements met (Not Large Project)."
                             Write-Host `n 
                                          
                                                         }
                          else {
                                Write-Host "Status: FAILED, RAM requirements not met (Not Large Project)."
                                Reset-ExecutionPolicies
                                Write-Host `n
                                Read-Host -Prompt "Press Enter to exit"
                                exit
                                }

                                                              }
                                     
                       else {
                               
                             Write-Host "Status: FAILED, 'Erroneous Project Type!'"
                             Write-Host `n
                             exit
                            }
                        
                        Write-Host "Status: 'Checking Remaining Host RAM'"
                        Write-Host `n
                        
                        if ($installedRAM -ge $global:installedVirtualRAM) {
                           Write-Host "Status: PASSED, 'Remaining Host RAM Suffcient!'"
                           Write-Host `n
                              }
                        
                        else {
                             
                             Write-Host "Status: FAILED 'Remaining Host RAM Insufficient!"
                             Write-Host `n
                             exit
                             }
                                                                   
}

#  This right here Checks the disk requirements
function Check-diskRequirements {
                         Write-Host "Status: 'Checking Disk Type.'"
                         Write-Host `n
                         if ($diskDriveType -eq '3') {  # '3' is the value that denotes a SSD. '2' Denotes a HDD.
                             Write-Host "Status: PASSED, Disk Type is SSD"
                             Write-Host `n                          
                                                     }

                         else {
                              Write-Host "Status: FAILED, Disk Type is not SSD'"
                              Write-Host `n
                              Read-Host -Prompt "Press Enter to exit"
                              exit 
                              }

                         Write-Host "Status: 'Checking Free Disk Space.'"
                         Write-Host `n
                         if ($diskFreeSpace -ge $reccommendedDiskSpace) {  
                             Write-Host "Status: PASSED, Disk has enough free space for TIA Portal v16 VM"
                             Write-Host `n                          
                                                                        }
                         else {
                              Write-Host "Status: FAILED, Disk has insufficient free space'"
                              Reset-ExecutionPolicies
                              Write-Host `n
                              Read-Host -Prompt "Press Enter to exit"
                              exit 
                              }


                         } 

#  This here checks the CPU requirements
function Check-CPUCores {
                         Write-Host "Status: 'Checking CPU Requirements.'"
                         Write-Host `n
                         if ($nMinusOneRule -ge 1) {
                             Write-Host "Status: PASSED, 'CPU is capable of TIA Portal v16 Requirements'"
                             Write-Host `n
                                                   }

                         else {
                              Write-Host "Status: FAILED, 'CPU is not capable of TIA Portal v16 Requirements'"
                              Reset-ExecutionPolicies
                              Write-Host `n
                              Read-Host -Prompt "Press Enter to exit"
                              exit 
                              }
                        }

#  This guy creates the Hyper-V VM Optimized for running TIA Portal v16
function Create-VM {
                    Write-Host "Status: 'Creating Virtual Hard Disk.'"
                    Write-Host `n

                   
                    New-VHD -Path $vhdxPath -SizeBytes $reccommendedDiskSpace -Fixed  #  Create the VHDX here
                   
                    Write-Host "Status: PASSED, 'New VHDX Created'"
                    Write-Host `n

                    Write-Host "Status: 'Creating Directory Structure'"
                    Write-Host `n 

                    New-Item -ItemType Directory -Path $snapshotsPath

                    Write-Host "Status: PASSED, 'Directory Structure Created'"
                    Write-Host `n
                   
                    Write-Host "Status: 'Creating VM'"
                    Write-Host `n
                   
                    New-VM -Name $vmName -Path $vmPath -MemoryStartupBytes $largeProjectRAM -VHDPath $vhdxPath -Generation 2  #  Create the VM
                    Add-VMDvdDrive -VMName $vmName -ControllerLocation 1 -Path $isoPath                                       #  Create DVD drive and Set the path to the iso
                    Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -Priority 100                                   #  Disable Dynamic Memory and set highest priority so VM always runs well.
                    Set-VMProcessor $vmName -Count $VMAssignedCores -Reserve 10 -Maximum 80 -RelativeWeight 200               #  Configure the number of CPU cores and optimization

                    Write-Host "Status: PASSED, 'New VM Created'"
                    Write-Host `n
                   }

#  This guy sets all of the policies to unrestricted so the script can run.
function Set-ExecutionPolicies {
                               Write-Host "Status: 'Setting Execution Policies'"
                               Write-Host `n
                               Set-ExecutionPolicy Unrestricted -Scope Process
                               Set-ExecutionPolicy Unrestricted -Scope CurrentUser
                               Set-ExecutionPolicy Unrestricted -Scope LocalMachine
                               Write-Host "Status: PASSED 'Execution Policies Set To Unrestricted'"
                               Write-Host `n
                               }

#  This guy resets all of the policies to restricted so the script can run.
function Reset-ExecutionPolicies {
                               Write-Host "Resetting Execution Policies"
                               Write-Host `n
                               Set-ExecutionPolicy Restricted -Scope Process
                               Set-ExecutionPolicy Restricted -Scope CurrentUser
                               Set-ExecutionPolicy Restricted -Scope LocalMachine
                               Write-Host "Status: PASSED 'Execution Policies Reset To Restricted'"
                               Write-Host `n
                               }

#  *********************************************BEGIN MAIN CODE********************************************

Elevate-Admin                                                 # elevate the console to admin permissions.
Write-scriptTitle                                             # Write the script title
Write-shamelessSelfPromotion                                  # Be totally shameless and self advertise (I am always for hire to the right opportunity)
Set-ExecutionPolicies                                         # Set the PowerShell Execution Policy to Unrestricted so the script can run.
Enable-HyperV                                                 # Enable the Hyper-V Windows Feature.
Check-TIAProjectSize                                          # Prompt the user for the TIA Portal project size
Check-RAM                                                     # Check the amount of RAM on the host and determine if it meets requirements
Check-diskRequirements                                        # Check the disk on the host and determine if it meets requirements
Check-CPUCores                                                # Check the CPU on the host and determine if it meets reccommendations 
Create-VM                                                     # Create the Base VM
Reset-ExecutionPolicies                                       # Reset the execution policies back to restricted for security
Read-Host -Prompt "Press Enter to exit"
exit

