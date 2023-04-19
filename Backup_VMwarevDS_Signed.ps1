#Requires -Version 3.0
#This File is in Unicode format.  Do not edit in an ASCII editor.

#region help text

<#

.SYNOPSIS
	Creates a backup of one or more Virtual Distributed Switches in a 
	VMware vSphere datacenter using PowerCLI.
.DESCRIPTION
	Creates a backup of one or more Virtual Distributed Switches in a 
	VMware vSphere datacenter using PowerCLI.
	
	When restoring an image-based backup, VMware states:
	
	"If you use a distributed virtual switch, you are advised to export 
	separately the distributed virtual switch configuration before you 
	restore to a backup. You can import the configuration after the restore. 
	If you omit this consideration, you may lose the changes made to a 
	distributed virtual switch after the backup."
	
	By default, the script processes all datacenters on the specified vCenter server 
	and backs up all Virtual Distributed Switches in each datacenter.
	
	The backup file created follows this naming scheme:
	
	DatacenterName_VirtualSwitchName_Backup.zip
.PARAMETER VIServerName
    Name of the vCenter Server to connect to.
    This parameter is mandatory and does not have a default value.
    FQDN should be used; hostname can be used if it can be resolved 
	correctly.
.PARAMETER PCLICustom
    Prompts user to locate the PowerCLI Scripts directory in a 
	non-default installation
	
    This parameter is disabled by default
.PARAMETER Datacenter
	Specify a specific datacenter to process.
	
	The default is to process all datacenters in the specified vCenter 
	Server.
	This parameter has an alias of DC
.PARAMETER Folder
	Specifies the optional output folder to save the output report. 
.PARAMETER Dev
	Clears errors at the beginning of the script.
	Outputs all errors to a text file at the end of the script.
	
	This is used when the script developer requests more troubleshooting 
	data.
	The text file is placed in the same folder from where the script is run.
	
	This parameter is disabled by default.
.PARAMETER ScriptInfo
	Outputs information about the script to a text file.
	The text file is placed in the same folder from where the script is run.
	
	This parameter is disabled by default.
	This parameter has an alias of SI.
.PARAMETER Log
	Generates a log file for troubleshooting.
.EXAMPLE
	PS C:\PSScript > .\Backup_VMwarevDS.ps1
	
	Will prompt for vCenter server.
	Will process all Datacenters configured on the vCenter server.
	Will place the backup Zip files in the folder from where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Backup_VMwarevDS.ps1 -Datacenter "Webster's Lab"
	
	Will prompt for vCenter server.
	Will attempt to validate the datacenter "Webster's Lab" is valid. 
	If valid, process all virtual Distributed Switches in the Datacenter named 
	"Webster's Lab".
	Will place the backup Zip files in the folder from where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Backup_VMwarevDS.ps1 -VIServer vcenter.labaddomain.com
	
	Uses vcenter.labaddomain.com for the vCenter server.
	Will process all Datacenters configured on the vCenter server.
	Will place the backup Zip files in the folder from where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Backup_VMwarevDS.ps1 -VIServer vcenter.labaddomain.com 
	-Datacenter "Webster's Lab"
	
	Uses vcenter.labaddomain.com for the vCenter server.
	Will attempt to validate the datacenter "Webster's Lab" is valid. 
	If valid, process all virtual Distributed Switches in the Datacenter named 
	"Webster's Lab".
	Will place the backup Zip files in the folder from where the script is run.
.EXAMPLE
	PS C:\PSScript > .\Backup_VMwarevDS.ps1 -VIServer vcenter.labaddomain.com -Folder 
	\\server\share\vDSBackups
	
	Uses vcenter.labaddomain.com for the vCenter server.
	Will process all Datacenters configured on the vCenter server.
	Will place the backup Zip files in the folder \\server\share\vDSBackups.
.INPUTS
	None. You cannot pipe objects to this script.
.OUTPUTS
	No objects are output from this script.  
	This script creates one or more zip files.
.NOTES
	NAME: Backup_VMwarevDS.ps1
	VERSION: 1.01
	AUTHOR: Carl Webster with code borrowed from Jake Rutski
	LASTEDIT: April 19, 2023
#>

#endregion

#region script parameters
#thanks to @jeffwouters and Michael B. Smith for helping me with these parameters
[CmdletBinding(SupportsShouldProcess = $False, ConfirmImpact = "None", DefaultParameterSetName = "") ]

Param(
    [parameter(Mandatory=$False)]
    [Alias("VC")]
    [ValidateNotNullOrEmpty()]
    [string]$VIServerName="",
	
    [parameter(Mandatory=$False)]
    [Switch]$PCLICustom=$False,

	[parameter(Mandatory=$False)] 
	[Alias("DC")]
	[string]$Datacenter="",
	
	[parameter(Mandatory=$False)] 
	[string]$Folder="",

	[parameter(Mandatory=$False)] 
	[Switch]$Dev=$False,
	
	[parameter(Mandatory=$False)] 
	[Alias("SI")]
	[Switch]$ScriptInfo=$False,
	
	[parameter(Mandatory=$False)] 
	[Switch]$Log=$False
	
	)
#endregion

#region script change log	
#webster@carlwebster.com
#@carlwebster on Twitter
#http://www.CarlWebster.com
#Created on January 2, 2020

#Portions borrowed from VMware vCenter inventory
#Jacob Rutski
#jake@serioustek.net
#http://blogs.serioustek.net
#@JRutski on Twitter
#
# Version 1.0 released to the community on 8-Jan-2020 (Happy Birthday Sophie)
#
# Version 1.01 19-Apr-2023
#	Fixed a $Null comparison where null was on the right instead of the left of the comparison
#	Fixed a missing variable $tempPWD
#	Test for variable $global:DefaultVIServer before using
#	Tested with PowerCLI 13.1
#endregion


#region initial variable testing and setup
Set-StrictMode -Version Latest

#force  on
$PSDefaultParameterValues = @{"*:Verbose"=$True}
$SaveEAPreference = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'

If($Log) 
{
	#start transcript logging
	$Script:ThisScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
	$Script:LogPath = "$Script:ThisScriptPath\BackupVMWvDSScriptTranscript_$(Get-Date -f yyyy-MM-dd_HHmm).txt"
	
	try 
	{
		Start-Transcript -Path $Script:LogPath -Force -Verbose:$false | Out-Null
		Write-Verbose "$(Get-Date): Transcript/log started at $Script:LogPath"
		$Script:StartLog = $true
	} 
	catch 
	{
		Write-Verbose "$(Get-Date): Transcript/log failed at $Script:LogPath"
		$Script:StartLog = $false
	}
}

If($Dev)
{
	$Error.Clear()
	$Script:DevErrorFile = "$($pwd.Path)\BackupVMWvDSScriptErrors_$(Get-Date -f yyyy-MM-dd_HHmm).txt"
}

If(!($VIServerName))
{
    $VIServerName = Read-Host 'Please enter the FQDN of your vCenter server'
}

If($Folder -ne "")
{
	Write-Verbose "$(Get-Date): Testing folder path"
	#does it exist
	If(Test-Path $Folder -EA 0)
	{
		#it exists, now check to see if it is a folder and not a file
		If(Test-Path $Folder -pathType Container -EA 0)
		{
			#it exists and it is a folder
			Write-Verbose "$(Get-Date): Folder path $Folder exists and is a folder"
		}
		Else
		{
			#it exists but it is a file not a folder
			Write-Error "Folder $Folder is a file, not a folder.  Script cannot continue"
			Exit
		}
	}
	Else
	{
		#does not exist
		Write-Error "Folder $Folder does not exist.  Script cannot continue"
		Exit
	}
}

If($Folder -eq "")
{
	$pwdpath = $pwd.Path
}
Else
{
	$pwdpath = $Folder
}

If($pwdpath.EndsWith("\"))
{
	#remove the trailing \
	$pwdpath = $pwdpath.SubString(0, ($pwdpath.Length - 1))
}

$Folder = $pwdpath
#endregion

#region general script functions
Function VISetup( [string] $VIServer )
{
	# Check for root
	# http://blogs.technet.com/b/heyscriptingguy/archive/2011/05/11/check-for-admin-credentials-in-a-powershell-script.aspx
	If(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
	{
		Write-Host "`nThis script is not running as administrator - this is required to set global PowerCLI parameters. You may see PowerCLI warnings.`n"
	}

	Write-Verbose "$(Get-Date): Setting up VMware PowerCLI"
	#Check to see if PowerCLI is installed via Module or MSI
	$PSDefaultParameterValues = @{"*:Verbose"=$False}

	If ($Null -ne (Get-Module -ListAvailable | Where-Object {$_.Name -eq "VMware.PowerCLI"}))
	{
		$PSDefaultParameterValues = @{"*:Verbose"=$True}
		# PowerCLI is installed via PowerShell Gallery\or the module is installed
		Write-Verbose "$(Get-Date): PowerCLI Module install found"
		# grab the PWD before PCLI resets it to C:\
		$tempPWD = $pwd
	}
	Else
	{
		$PSDefaultParameterValues = @{"*:Verbose"=$True}
		If($PCLICustom)
		{
			Write-Verbose "$(Get-Date): Custom PowerCLI Install location"
			$PCLIPath = "$(Select-FolderDialog)\Initialize-PowerCLIEnvironment.ps1" 4>$Null
		}
		ElseIf($env:PROCESSOR_ARCHITECTURE -like "*AMD64*")
		{
			$PCLIPath = "C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"
		}
		Else
		{
			$PCLIPath = "C:\Program Files\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"
		}

		If (!(Test-Path $PCLIPath))
		{
			# PCLI v6.5 changed install directory...check here first
			If($env:PROCESSOR_ARCHITECTURE -like "*AMD64*")
			{
				$PCLIPath = "C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"
			}
			Else
			{
				$PCLIPath = "C:\Program Files\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"
			}
		}
		If (Test-Path $PCLIPath)
		{
			# grab the PWD before PCLI resets it to C:\
			$tempPWD = $pwd
			Import-Module $PCLIPath *>$Null
		}
		Else
		{
			Write-Host "`nPowerCLI does not appear to be installed - please install the latest version of PowerCLI. This script will now exit."
			Write-Host "*** If PowerCLI was installed to a non-Default location, please use the -PCLICustom parameter ***`n"
			Exit
		}
	}

	$PSDefaultParameterValues = @{"*:Verbose"=$False}
	$Script:xPowerCLIVer = (Get-Command Connect-VIServer).Version
	$PSDefaultParameterValues = @{"*:Verbose"=$True}

	Write-Verbose "$(Get-Date): Loaded PowerCLI version $($Script:xPowerCLIVer.Major).$($Script:xPowerCLIVer.Minor)"
	If($Script:xPowerCLIVer.Major -lt 5 -or ($Script:xPowerCLIVer.Major -eq 5 -and $Script:xPowerCLIVer.Minor -lt 1))
	{
		Write-Host "`nPowerCLI version $($Script:xPowerCLIVer.Major).$($Script:xPowerCLIVer.Minor) is installed. PowerCLI version 5.1 or later is required to run this script. `nPlease install the latest version and run this script again. This script will now exit."
		Exit
	}

	#Set PCLI defaults and reset PWD
	If(Test-Path variable:tempPWD)
	{
		cd $tempPWD 4>$Null
	}
	Write-Verbose "$(Get-Date): Setting PowerCLI global Configuration"
	Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -DisplayDeprecationWarnings $False -Confirm:$False *>$Null

	#Are we already connected to VC?
	If(Test-Path variable:global:DefaultVIServer)
	{
		If($global:DefaultVIServer)
		{
			Write-Host "`nIt appears PowerCLI is already connected to a vCenter Server. Please use the 'Disconnect-VIServer' cmdlet to disconnect any sessions before running inventory."
			Exit
		}
	}

	#Connect to VI Server
	Write-Verbose "$(Get-Date): Connecting to VIServer: $($VIServer)"
	$Script:VCObj = Connect-VIServer $VIServer 4>$Null

	#Verify we successfully connected
	If(!($?))
	{
		Write-Host "Connecting to vCenter failed with the following error: $($Error[0].Exception.Message.substring($Error[0].Exception.Message.IndexOf("Connect-VIServer") + 16).Trim()) This script will now exit."
		Exit
	}
}

Function Select-FolderDialog
{
	# http://stackoverflow.com/questions/11412617/get-a-folder-path-from-the-explorer-menu-to-a-powershell-variable
	param([string]$Description="Select PowerCLI Scripts Directory - Default is C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\",[string]$RootFolder="Desktop")

	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null     

	$objForm = New-Object System.Windows.Forms.FolderBrowserDialog
	$objForm.Rootfolder = $RootFolder
	$objForm.Description = $Description
	$Show = $objForm.ShowDialog()
	If ($Show -eq "OK")
	{
		Return $objForm.SelectedPath
	}
	Else
	{
		Write-Error "Operation cancelled by user."
	}
}

Function ShowScriptOptions
{
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): "
	If($Datacenter -eq "")
	{
		Write-Verbose "$(Get-Date): Datacenter      : All"
	}
	Else
	{
		Write-Verbose "$(Get-Date): Datacenter      : $($Datacenter)"
	}
	Write-Verbose "$(Get-Date): Dev             : $($Dev)"
	If($Dev)
	{
		Write-Verbose "$(Get-Date): DevErrorFile    : $($Script:DevErrorFile)"
	}
	Write-Verbose "$(Get-Date): Folder          : $($Folder)"
	Write-Verbose "$(Get-Date): Log             : $($Log)"
	Write-Verbose "$(Get-Date): ScriptInfo      : $($ScriptInfo)"
	Write-Verbose "$(Get-Date): VIServerName    : $($VIServerName)"
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): OS Detected     : $($Script:RunningOS)"
	Write-Verbose "$(Get-Date): PoSH version    : $($Host.Version)"
	Write-Verbose "$(Get-Date): PowerCLI version: $($Script:xPowerCLIVer.Major).$($Script:xPowerCLIVer.Minor)"
	Write-Verbose "$(Get-Date): PSCulture       : $($PSCulture)"
	Write-Verbose "$(Get-Date): PSUICulture     : $($PSUICulture)"
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): Script start    : $($Script:StartTime)"
	Write-Verbose "$(Get-Date): "
	Write-Verbose "$(Get-Date): "
}

Function ValidateDatacenter
{
	Write-Verbose "$(Get-Date): Validating datacenter $Datacenter"
	$PSDefaultParameterValues = @{"*:Verbose"=$False}
	$results = Get-Datacenter -Name $Datacenter -EA 0
	
	If(-not $? -or $Null -eq $results)
	{
		$PSDefaultParameterValues = @{"*:Verbose"=$True}
		Write-Error "$(Get-Date): `t`t
		`n`n
		Error retrieving a datacenter named $Datacenter.
		`n`n
		Script cannot continue."
		
		Return $False
	}
	
	$PSDefaultParameterValues = @{"*:Verbose"=$True}
	Write-Verbose "$(Get-Date): `tDatacenter $Datacenter is valid"
	Return $True
}

Function ProcessBackup
{
	If($Datacenter -eq "")
	{
		Write-Verbose "$(Get-Date): Gathering Datacenters"
		$DCs = @(Get-DataCenter 4>$Null| Sort-Object Name)
		
		If(-not $? -or $Null -eq $DCs)
		{
			Write-Error "$(Get-Date): `t`t
			`n`n
			Error retrieving DCs.
			`n`n
			Script cannot continue."
		}
		ElseIf($? -and $Null -ne $DCs)
		{
			Write-Verbose "$(Get-Date): Found $($DCs.Count) Datacenters"
			
			ForEach($DC in $DCs)
			{
				Write-Verbose "$(Get-Date): `tGathering Virtual Switches for Datacenter: $($DC.Name)"
				$PSDefaultParameterValues = @{"*:Verbose"=$False}
				$VirtualSwitches = @(Get-Datacenter -Name $DC.Name -EA 0 | Get-VDSwitch -EA 0)
				
				If(-not $? -or $Null -eq $VirtualSwitches)
				{
					$PSDefaultParameterValues = @{"*:Verbose"=$True}
					Write-Warning "$(Get-Date): Error retrieving virtual switches or there are no virtual switches for Datacenter $($DC.Name)"
				}
				Else
				{
					$PSDefaultParameterValues = @{"*:Verbose"=$True}
					Write-Verbose "$(Get-Date): `tFound $($VirtualSwitches.Count) virtual switches"
					
					ForEach($VirtualSwitch in $VirtualSwitches)
					{
						Write-Verbose "$(Get-Date): `t`tProcess virtual switch: $($VirtualSwitch.Name)"
						$ExportFilename = "$Folder\$($DC.Name)_$($VirtualSwitch.Name)_Backup.zip"
						Export-VdSwitch -VDSwitch $VirtualSwitch.Name -Destination $ExportFilename -Force -Server $VIServerName -EA 0 *> $Null
						
						If($?)
						{
							Write-Verbose "$(Get-Date): `t`t`tSuccessfully backed up virtual switch $($VirtualSwitch.Name)"
						}
						Else
						{
							Write-Verbose "$(Get-Date): `t`t`tFailed to back up virtual switch $($VirtualSwitch.Name)"
						}
					}
				}
			}
		}
	}
	Else
	{
		Write-Verbose "$(Get-Date): `tGathering Virtual Switches for Datacenter: $Datacenter"
		$PSDefaultParameterValues = @{"*:Verbose"=$False}
		$VirtualSwitches = @(Get-Datacenter -Name $Datacenter -EA 0 | Get-VDSwitch -EA 0)
		
		If(-not $? -or $Null -eq $VirtualSwitches)
		{
			$PSDefaultParameterValues = @{"*:Verbose"=$True}
			Write-Warning "$(Get-Date): Error retrieving virtual switches or there are no virtual switches for Datacenter $Datacenter"
		}
		Else
		{
			$PSDefaultParameterValues = @{"*:Verbose"=$True}
			Write-Verbose "$(Get-Date): `tFound $($VirtualSwitches.Count) virtual switches"
			
			ForEach($VirtualSwitch in $VirtualSwitches)
			{
				Write-Verbose "$(Get-Date): `t`tProcess virtual switch: $($VirtualSwitch.Name)"
				$ExportFilename = "$Folder\$($Datacenter)_$($VirtualSwitch.Name)_Backup.zip"
				Export-VdSwitch -VDSwitch $VirtualSwitch.Name -Destination $ExportFilename -Force -Server $VIServerName -EA 0 *> $Null
				
				If($?)
				{
					Write-Verbose "$(Get-Date): `t`t`tSuccessfully backed up virtual switch $($VirtualSwitch.Name)"
				}
				Else
				{
					Write-Verbose "$(Get-Date): `t`t`tFailed to back up virtual switch $($VirtualSwitch.Name)"
				}
			}
		}
	}
}
#endregion

#region script setup function
Function ProcessScriptSetup
{
	$script:startTime = Get-Date
	[string]$Script:RunningOS = (Get-WmiObject -class Win32_OperatingSystem -EA 0).Caption

	VISetup $VIServerName
	
	ShowScriptOptions
}
#endregion

#region script end function
Function ProcessScriptEnd
{
	Write-Verbose "$(Get-Date): Script has completed"
	Write-Verbose "$(Get-Date): "

	#http://poshtips.com/measuring-elapsed-time-in-powershell/
	Write-Verbose "$(Get-Date): Script started: $($Script:StartTime)"
	Write-Verbose "$(Get-Date): Script ended: $(Get-Date)"
	$runtime = $(Get-Date) - $Script:StartTime
	$Str = [string]::format("{0} days, {1} hours, {2} minutes, {3}.{4} seconds", `
		$runtime.Days, `
		$runtime.Hours, `
		$runtime.Minutes, `
		$runtime.Seconds,
		$runtime.Milliseconds)
	Write-Verbose "$(Get-Date): Elapsed time: $($Str)"

	If($Dev)
	{
		Out-File -FilePath $Script:DevErrorFile -InputObject $error 4>$Null
	}

	If($ScriptInfo)
	{
		$SIFile = "$($pwd.Path)\BackupVMWvDSScriptInfo_$(Get-Date -f yyyy-MM-dd_HHmm).txt"
		Out-File -FilePath $SIFile -InputObject "" 4>$Null
		If($Datacenter -eq "")
		{
			Out-File -FilePath $SIFile -Append -InputObject "Datacenter       : All"
		}
		Else
		{
			Out-File -FilePath $SIFile -Append -InputObject "Datacenter       : $($Datacenter)"
		}
		Out-File -FilePath $SIFile -Append -InputObject "Dev             : $($Dev)" 4>$Null
		If($Dev)
		{
			Out-File -FilePath $SIFile -Append -InputObject "DevErrorFile    : $($Script:DevErrorFile)" 4>$Null
		}
		Out-File -FilePath $SIFile -Append -InputObject "Folder          : $($Folder)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "Log             : $($Log)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "Script Info     : $($ScriptInfo)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "VIServerName    : $($VIServerName)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "OS Detected     : $($Script:RunningOS)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "PoSH version    : $($Host.Version)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "PowerCLI version: $($Script:xPowerCLIVer.Major).$($Script:xPowerCLIVer.Minor)"
		Out-File -FilePath $SIFile -Append -InputObject "PSCulture       : $($PSCulture)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "PSUICulture     : $($PSUICulture)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "Script start    : $($Script:StartTime)" 4>$Null
		Out-File -FilePath $SIFile -Append -InputObject "Elapsed time    : $($Str)" 4>$Null
	}

	#stop transcript logging
	If($Log -eq $True) 
	{
		If($Script:StartLog -eq $true) 
		{
			try 
			{
				Stop-Transcript | Out-Null
				Write-Verbose "$(Get-Date): $Script:LogPath is ready for use"
			} 
			catch 
			{
				Write-Verbose "$(Get-Date): Transcript/log stop failed"
			}
		}
	}
	$ErrorActionPreference = $SaveEAPreference
}
#endregion

#region script core
#Script begins

ProcessScriptSetup

If($Datacenter -ne "")
{
	If(ValidateDatacenter)
	{
		ProcessBackup
	}
}
Else
{
	ProcessBackup
}

#endregion

#region finish script
Write-Verbose "$(Get-Date): Finishing up script"

#Disconnect from VCenter
Disconnect-VIServer $VIServerName -Confirm:$False 4>$Null

ProcessScriptEnd
#endregion
# SIG # Begin signature block
# MIItUQYJKoZIhvcNAQcCoIItQjCCLT4CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUfyx7DridyuGxWb56J0025vxe
# PquggiaxMIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
# AQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz
# 7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS
# 5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7
# bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfI
# SKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jH
# trHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14
# Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2
# h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt
# 6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPR
# iQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ER
# ElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4K
# Jpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAd
# BgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SS
# y4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAC
# hjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRV
# HSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyh
# hyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO
# 0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo
# 8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++h
# UD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5x
# aiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIFkDCCA3ig
# AwIBAgIQBZsbV56OITLiOQe9p3d1XDANBgkqhkiG9w0BAQwFADBiMQswCQYDVQQG
# EwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNl
# cnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMTMw
# ODAxMTIwMDAwWhcNMzgwMTE1MTIwMDAwWjBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Y
# q3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lX
# FllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxe
# TsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbu
# yntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I
# 9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmg
# Z92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse
# 5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKy
# Ebe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwh
# HbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/
# Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwID
# AQABo0IwQDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4E
# FgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wDQYJKoZIhvcNAQEMBQADggIBALth2X2p
# bL4XxJEbw6GiAI3jZGgPVs93rnD5/ZpKmbnJeFwMDF/k5hQpVgs2SV1EY+CtnJYY
# ZhsjDT156W1r1lT40jzBQ0CuHVD1UvyQO7uYmWlrx8GnqGikJ9yd+SeuMIW59mdN
# Oj6PWTkiU0TryF0Dyu1Qen1iIQqAyHNm0aAFYF/opbSnr6j3bTWcfFqK1qI4mfN4
# i/RN0iAL3gTujJtHgXINwBQy7zBZLq7gcfJW5GqXb5JQbZaNaHqasjYUegbyJLkJ
# EVDXCLG4iXqEI2FCKeWjzaIgQdfRnGTZ6iahixTXTBmyUEFxPT9NcCOGDErcgdLM
# MpSEDQgJlxxPwO5rIHQw0uA5NBCFIRUBCOhVMt5xSdkoF1BN5r5N0XWs0Mr7QbhD
# parTwwVETyw2m+L64kW4I1NsBm9nVX9GtUw/bihaeSbSpKhil9Ie4u1Ki7wb/UdK
# Dd9nZn6yW0HQO+T0O/QEY+nvwlQAUaCKKsnOeMzV6ocEGLPOr0mIr/OSmbaz5mEP
# 0oUA51Aa5BuVnRmhuZyxm7EAHu/QD09CbMkKvO5D+jpxpchNJqU1/YldvIViHTLS
# oCtU7ZpXwdv6EM8Zt4tKG48BtieVU+i2iW1bvGjUI+iLUaJW+fCmgKDWHrO8Dw9T
# dSmq6hN35N6MgSGtBxBHEa2HPQfRdbzP82Z+MIIGrjCCBJagAwIBAgIQBzY3tyRU
# fNhHrP0oZipeWzANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjIwMzIzMDAwMDAwWhcN
# MzcwMzIyMjM1OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
# IEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEy
# NTYgVGltZVN0YW1waW5nIENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAxoY1BkmzwT1ySVFVxyUDxPKRN6mXUaHW0oPRnkyibaCwzIP5WvYRoUQVQl+k
# iPNo+n3znIkLf50fng8zH1ATCyZzlm34V6gCff1DtITaEfFzsbPuK4CEiiIY3+va
# PcQXf6sZKz5C3GeO6lE98NZW1OcoLevTsbV15x8GZY2UKdPZ7Gnf2ZCHRgB720RB
# idx8ald68Dd5n12sy+iEZLRS8nZH92GDGd1ftFQLIWhuNyG7QKxfst5Kfc71ORJn
# 7w6lY2zkpsUdzTYNXNXmG6jBZHRAp8ByxbpOH7G1WE15/tePc5OsLDnipUjW8LAx
# E6lXKZYnLvWHpo9OdhVVJnCYJn+gGkcgQ+NDY4B7dW4nJZCYOjgRs/b2nuY7W+yB
# 3iIU2YIqx5K/oN7jPqJz+ucfWmyU8lKVEStYdEAoq3NDzt9KoRxrOMUp88qqlnNC
# aJ+2RrOdOqPVA+C/8KI8ykLcGEh/FDTP0kyr75s9/g64ZCr6dSgkQe1CvwWcZklS
# UPRR8zZJTYsg0ixXNXkrqPNFYLwjjVj33GHek/45wPmyMKVM1+mYSlg+0wOI/rOP
# 015LdhJRk8mMDDtbiiKowSYI+RQQEgN9XyO7ZONj4KbhPvbCdLI/Hgl27KtdRnXi
# YKNYCQEoAA6EVO7O6V3IXjASvUaetdN2udIOa5kM0jO0zbECAwEAAaOCAV0wggFZ
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFLoW2W1NhS9zKXaaL3WMaiCP
# nshvMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQE
# AwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5j
# cnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJ
# YIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQB9WY7Ak7ZvmKlEIgF+ZtbYIULh
# sBguEE0TzzBTzr8Y+8dQXeJLKftwig2qKWn8acHPHQfpPmDI2AvlXFvXbYf6hCAl
# NDFnzbYSlm/EUExiHQwIgqgWvalWzxVzjQEiJc6VaT9Hd/tydBTX/6tPiix6q4XN
# Q1/tYLaqT5Fmniye4Iqs5f2MvGQmh2ySvZ180HAKfO+ovHVPulr3qRCyXen/KFSJ
# 8NWKcXZl2szwcqMj+sAngkSumScbqyQeJsG33irr9p6xeZmBo1aGqwpFyd/EjaDn
# mPv7pp1yr8THwcFqcdnGE4AJxLafzYeHJLtPo0m5d2aR8XKc6UsCUqc3fpNTrDsd
# CEkPlM05et3/JWOZJyw9P2un8WbDQc1PtkCbISFA0LcTJM3cHXg65J6t5TRxktcm
# a+Q4c6umAU+9Pzt4rUyt+8SVe+0KXzM5h0F4ejjpnOHdI/0dKNPH+ejxmF/7K9h+
# 8kaddSweJywm228Vex4Ziza4k9Tm8heZWcpw8De/mADfIBZPJ/tgZxahZrrdVcA6
# KYawmKAr7ZVBtzrVFZgxtGIJDwq9gdkT/r+k0fNX2bwE+oLeMt8EifAAzV3C+dAj
# fwAL5HYCJtnwZXZCpimHCUcr5n8apIUP/JiW9lVUKx+A+sDyDivl1vupL0QVSucT
# Dh3bNzgaoSv27dZ8/DCCBrAwggSYoAMCAQICEAitQLJg0pxMn17Nqb2TrtkwDQYJ
# KoZIhvcNAQEMBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQg
# VHJ1c3RlZCBSb290IEc0MB4XDTIxMDQyOTAwMDAwMFoXDTM2MDQyODIzNTk1OVow
# aTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQD
# EzhEaWdpQ2VydCBUcnVzdGVkIEc0IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4
# NCAyMDIxIENBMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANW0L0LQ
# KK14t13VOVkbsYhC9TOM6z2Bl3DFu8SFJjCfpI5o2Fz16zQkB+FLT9N4Q/QX1x7a
# +dLVZxpSTw6hV/yImcGRzIEDPk1wJGSzjeIIfTR9TIBXEmtDmpnyxTsf8u/LR1oT
# pkyzASAl8xDTi7L7CPCK4J0JwGWn+piASTWHPVEZ6JAheEUuoZ8s4RjCGszF7pNJ
# cEIyj/vG6hzzZWiRok1MghFIUmjeEL0UV13oGBNlxX+yT4UsSKRWhDXW+S6cqgAV
# 0Tf+GgaUwnzI6hsy5srC9KejAw50pa85tqtgEuPo1rn3MeHcreQYoNjBI0dHs6EP
# bqOrbZgGgxu3amct0r1EGpIQgY+wOwnXx5syWsL/amBUi0nBk+3htFzgb+sm+YzV
# svk4EObqzpH1vtP7b5NhNFy8k0UogzYqZihfsHPOiyYlBrKD1Fz2FRlM7WLgXjPy
# 6OjsCqewAyuRsjZ5vvetCB51pmXMu+NIUPN3kRr+21CiRshhWJj1fAIWPIMorTmG
# 7NS3DVPQ+EfmdTCN7DCTdhSmW0tddGFNPxKRdt6/WMtyEClB8NXFbSZ2aBFBE1ia
# 3CYrAfSJTVnbeM+BSj5AR1/JgVBzhRAjIVlgimRUwcwhGug4GXxmHM14OEUwmU//
# Y09Mu6oNCFNBfFg9R7P6tuyMMgkCzGw8DFYRAgMBAAGjggFZMIIBVTASBgNVHRMB
# Af8ECDAGAQH/AgEAMB0GA1UdDgQWBBRoN+Drtjv4XxGG+/5hewiIZfROQjAfBgNV
# HSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYD
# VR0lBAwwCgYIKwYBBQUHAwMwdwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1Ud
# HwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRy
# dXN0ZWRSb290RzQuY3JsMBwGA1UdIAQVMBMwBwYFZ4EMAQMwCAYGZ4EMAQQBMA0G
# CSqGSIb3DQEBDAUAA4ICAQA6I0Q9jQh27o+8OpnTVuACGqX4SDTzLLbmdGb3lHKx
# AMqvbDAnExKekESfS/2eo3wm1Te8Ol1IbZXVP0n0J7sWgUVQ/Zy9toXgdn43ccsi
# 91qqkM/1k2rj6yDR1VB5iJqKisG2vaFIGH7c2IAaERkYzWGZgVb2yeN258TkG19D
# +D6U/3Y5PZ7Umc9K3SjrXyahlVhI1Rr+1yc//ZDRdobdHLBgXPMNqO7giaG9OeE4
# Ttpuuzad++UhU1rDyulq8aI+20O4M8hPOBSSmfXdzlRt2V0CFB9AM3wD4pWywiF1
# c1LLRtjENByipUuNzW92NyyFPxrOJukYvpAHsEN/lYgggnDwzMrv/Sk1XB+JOFX3
# N4qLCaHLC+kxGv8uGVw5ceG+nKcKBtYmZ7eS5k5f3nqsSc8upHSSrds8pJyGH+PB
# VhsrI/+PteqIe3Br5qC6/To/RabE6BaRUotBwEiES5ZNq0RA443wFSjO7fEYVgcq
# LxDEDAhkPDOPriiMPMuPiAsNvzv0zh57ju+168u38HcT5ucoP6wSrqUvImxB+YJc
# FWbMbA7KxYbD9iYzDAdLoNMHAmpqQDBISzSoUSC7rRuFCOJZDW3KBVAr6kocnqX9
# oKcfBnTn8tZSkP2vhUgh+Vc7tJwD7YZF9LRhbr9o4iZghurIr6n+lB3nYxs6hlZ4
# TjCCBsAwggSooAMCAQICEAxNaXJLlPo8Kko9KQeAPVowDQYJKoZIhvcNAQELBQAw
# YzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQD
# EzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGlu
# ZyBDQTAeFw0yMjA5MjEwMDAwMDBaFw0zMzExMjEyMzU5NTlaMEYxCzAJBgNVBAYT
# AlVTMREwDwYDVQQKEwhEaWdpQ2VydDEkMCIGA1UEAxMbRGlnaUNlcnQgVGltZXN0
# YW1wIDIwMjIgLSAyMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAz+yl
# JjrGqfJru43BDZrboegUhXQzGias0BxVHh42bbySVQxh9J0Jdz0Vlggva2Sk/QaD
# FteRkjgcMQKW+3KxlzpVrzPsYYrppijbkGNcvYlT4DotjIdCriak5Lt4eLl6FuFW
# xsC6ZFO7KhbnUEi7iGkMiMbxvuAvfTuxylONQIMe58tySSgeTIAehVbnhe3yYbyq
# Ogd99qtu5Wbd4lz1L+2N1E2VhGjjgMtqedHSEJFGKes+JvK0jM1MuWbIu6pQOA3l
# jJRdGVq/9XtAbm8WqJqclUeGhXk+DF5mjBoKJL6cqtKctvdPbnjEKD+jHA9QBje6
# CNk1prUe2nhYHTno+EyREJZ+TeHdwq2lfvgtGx/sK0YYoxn2Off1wU9xLokDEaJL
# u5i/+k/kezbvBkTkVf826uV8MefzwlLE5hZ7Wn6lJXPbwGqZIS1j5Vn1TS+QHye3
# 0qsU5Thmh1EIa/tTQznQZPpWz+D0CuYUbWR4u5j9lMNzIfMvwi4g14Gs0/EH1OG9
# 2V1LbjGUKYvmQaRllMBY5eUuKZCmt2Fk+tkgbBhRYLqmgQ8JJVPxvzvpqwcOagc5
# YhnJ1oV/E9mNec9ixezhe7nMZxMHmsF47caIyLBuMnnHC1mDjcbu9Sx8e47LZInx
# scS451NeX1XSfRkpWQNO+l3qRXMchH7XzuLUOncCAwEAAaOCAYswggGHMA4GA1Ud
# DwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMI
# MCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATAfBgNVHSMEGDAWgBS6
# FtltTYUvcyl2mi91jGogj57IbzAdBgNVHQ4EFgQUYore0GH8jzEU7ZcLzT0qlBTf
# UpwwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRpbWVTdGFtcGluZ0NBLmNybDCB
# kAYIKwYBBQUHAQEEgYMwgYAwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2lj
# ZXJ0LmNvbTBYBggrBgEFBQcwAoZMaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRpbWVTdGFtcGluZ0NBLmNy
# dDANBgkqhkiG9w0BAQsFAAOCAgEAVaoqGvNG83hXNzD8deNP1oUj8fz5lTmbJeb3
# coqYw3fUZPwV+zbCSVEseIhjVQlGOQD8adTKmyn7oz/AyQCbEx2wmIncePLNfIXN
# U52vYuJhZqMUKkWHSphCK1D8G7WeCDAJ+uQt1wmJefkJ5ojOfRu4aqKbwVNgCeij
# uJ3XrR8cuOyYQfD2DoD75P/fnRCn6wC6X0qPGjpStOq/CUkVNTZZmg9U0rIbf35e
# Ca12VIp0bcrSBWcrduv/mLImlTgZiEQU5QpZomvnIj5EIdI/HMCb7XxIstiSDJFP
# PGaUr10CU+ue4p7k0x+GAWScAMLpWnR1DT3heYi/HAGXyRkjgNc2Wl+WFrFjDMZG
# QDvOXTXUWT5Dmhiuw8nLw/ubE19qtcfg8wXDWd8nYiveQclTuf80EGf2JjKYe/5c
# QpSBlIKdrAqLxksVStOYkEVgM4DgI974A6T2RUflzrgDQkfoQTZxd639ouiXdE4u
# 2h4djFrIHprVwvDGIqhPm73YHJpRxC+a9l+nJ5e6li6FV8Bg53hWf2rvwpWaSxEC
# yIKcyRoFfLpxtU56mWz06J7UWpjIn7+NuxhcQ/XQKujiYu54BNu90ftbCqhwfvCX
# hHjjCANdRyxjqCU4lwHSPzra5eX25pvcfizM/xdMTQCi2NYBDriL7ubgclWJLCcZ
# YfZ3AYwwggdeMIIFRqADAgECAhAFulYuS3p29y1ilWIrK5dmMA0GCSqGSIb3DQEB
# CwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8G
# A1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBT
# SEEzODQgMjAyMSBDQTEwHhcNMjExMjAxMDAwMDAwWhcNMjMxMjA3MjM1OTU5WjBj
# MQswCQYDVQQGEwJVUzESMBAGA1UECBMJVGVubmVzc2VlMRIwEAYDVQQHEwlUdWxs
# YWhvbWExFTATBgNVBAoTDENhcmwgV2Vic3RlcjEVMBMGA1UEAxMMQ2FybCBXZWJz
# dGVyMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA98Xfb+rSvcKK6oXU
# 0jjumwlQCG2EltgTWqBp3yIWVJvPgbbryZB0JNT3vWbZUOnqZxENFG/YxDdR88By
# ukOAeveRE1oeYNva7kbEpQ7vH9sTNiVFsglOQRtSyBch3353BZ51gIESO1sxW9dw
# 41rMdUw6AhxoMxwhX0RTV25mUVAadNzDEuZzTP3zXpWuoAeYpppe8yptyw8OR79A
# d83ttDPLr6o/SwXYH2EeaQu195FFq7Fn6Yp/kLYAgOrpJFJpRxd+b2kWxnOaF5RI
# /EcbLH+/20xTDOho3V7VGWTiRs18QNLb1u14wiBTUnHvLsLBT1g5fli4RhL7rknp
# 8DHksuISIIQVMWVfgFmgCsV9of4ymf4EmyzIJexXcdFHDw2x/bWFqXti/TPV8wYK
# lEaLa2MrSMH1Jrnqt/vcP/DP2IUJa4FayoY2l8wvGOLNjYvfQ6c6RThd1ju7d62r
# 9EJI8aPXPvcrlyZ3y6UH9tiuuPzsyNVnXKyDphJm5I57tLsN8LSBNVo+I227VZfX
# q3MUuhz0oyErzFeKnLsPB1afLLfBzCSeYWOMjWpLo+PufKgh0X8OCRSfq6Iigpj9
# q5KzjQ29L9BVnOJuWt49fwWFfmBOrcaR9QaN4gAHSY9+K7Tj3kUo0AHl66QaGWet
# R7XYTel+ydst/fzYBq6SafVOt1kCAwEAAaOCAgYwggICMB8GA1UdIwQYMBaAFGg3
# 4Ou2O/hfEYb7/mF7CIhl9E5CMB0GA1UdDgQWBBQ5WnsIlilu682kqvRMmUxb5DHu
# gTAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwgbUGA1UdHwSB
# rTCBqjBToFGgT4ZNaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcmwwU6BRoE+G
# TWh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNENvZGVT
# aWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMD4GA1UdIAQ3MDUwMwYGZ4EM
# AQQBMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzCB
# lAYIKwYBBQUHAQEEgYcwgYQwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2lj
# ZXJ0LmNvbTBcBggrBgEFBQcwAoZQaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNB
# MS5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAGcm1xuESCj6Y
# VIf55C/gtmnsRJWtf7zEyqUtXhYU+PMciHnjnUbOmuF1+jKTA6j9FN0Ktv33fVxt
# WQ+ZisNssZbfwaUd3goBQatFF2TmUc1KVsRUj/VU+uVPcL++tzaYkDydowhiP+9D
# IEOXOYxunjlwFppOGrk3edKRj8p7puv9sZZTdPiUHmJ1GvideoXTAJ1Db6Jmn6ee
# tnl4m6zx9CCDJF9z8KexKS1bSpJBbdKz71H1PlgI7Tu4ntLyyaRVOpan8XYWmu9k
# 35TOfHHl8Cvbg6itg0fIJgvqnLJ4Huc+y6o/zrvj6HrFSOK6XowdQLQshrMZ2ceT
# u8gVkZsKZtu0JeMpkbVKmKi/7RXIZdh9bn0NhzslioXEX+s70d60kntMsBAQX0Ar
# OpKmrqZZJuxNMGAIXpEwSTeyqu0ujZI9eE1AU7EcZsYkZawdyLmilZdw1qwEQlAv
# EqyjbjY81qtpkORAeJSpnPelUlyyQelJPLWFR0syKsUyROqg5OFXINxkHaJcuWLW
# RPFJOEooSWPEid4rHMftaG2gOPg35o7yPzzHd8Y9pCX2v55NYjLrjUkz9JCjQ/g0
# LiOo3a+yvot+7izsaJEs8SAdhG7RZ/fdsyv+SyyoEzsd1iO/mZ2DQ0rKaU/fiCXJ
# pvrNmEwg+pbeIOCOgS0x5pQ0dyMlBZoxggYKMIIGBgIBATB9MGkxCzAJBgNVBAYT
# AlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQg
# VHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEzODQgMjAyMSBDQTEC
# EAW6Vi5Lenb3LWKVYisrl2YwCQYFKw4DAhoFAKBAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMCMGCSqGSIb3DQEJBDEWBBQ/qTQk4+rM88aQaY7EaEIFGikHNTAN
# BgkqhkiG9w0BAQEFAASCAgDVQRjDHZOO8lhdZZUSbPMz1DwETl0e2uXys/lws3bP
# JGOPwNWSu3Uham2J1b9LpvcoT7lOCskYZ1JcOBOg92bWIMtpUIwsefjZd4maE6Vk
# hVDUd7mwG/OKGr2hPFIVnNJN1c2opJr/6skBdXo0MEYkhwaCR0uyJlSJ2R2dkEcS
# A60YONYaJof00C8XSgHWbR6wUXMsnuqaBjze+oHAdnIo++QEmQuRgiT2ZvUOR46+
# DBj5i6j+FQMR+nTcn2eVoniuB8JNxxWXi11zqgbTRrGJlR70HBRM5FlasL/K6dRu
# mfEY6FneYJ0DYn0cfA8MM4KQnjk7FexJKZVU2vEaIuYit+lAx4yYGO39/PCvyU5n
# x/QhsyvzEhCUBDl/hVT9RDbZw40keMZAtmCWgbx5e8gwzJswTC46ur188a0nNtWn
# tOeZV7uNU3QNHTrsKD+UKRXvXAKd2vTbGHmGW/f9RGjY2eCjma12M6HTv0T3pt9u
# uW3zPD3S9B9550FVZ5oS1LNrxArqMskwXmUbBKBKst537baxiWmD44X/c1GAc9ld
# 4Cy1wtG153JtkJu7VgSwly7bbnM/riAbXDNy0w8XvY2X2dVpAZLQwLuffq1+//VM
# T/tpdN1cQg0/AJ7cTHnIjZ8KRr6V86ySDXf3lqAfD7CbYkncXIYz5SQPcVG32ApD
# KqGCAyAwggMcBgkqhkiG9w0BCQYxggMNMIIDCQIBATB3MGMxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1
# c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0ECEAxNaXJLlPo8
# Kko9KQeAPVowDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yMzA0MTkxNzM3MTFaMC8GCSqGSIb3DQEJBDEi
# BCCIKYqe2o2824E/obaiNDsBzx+ZF13/hnTxkdtaGn4qWzANBgkqhkiG9w0BAQEF
# AASCAgBfEDSrCpxxnM46E2zffEStIMSUDP18mcSOOSFc7IlA1gcCjYt9jte+IqLr
# M7PJUQ3AM+o1VPOtqt7/+IeQqf6C8S2Qnzjo3DUAFDfBXU042uTV5U4fmzGHJrZK
# WwJoSKjFwvkkFffsl1mteKI5Mex1mGbsFB7fyRayNjp/cpA4CRDwYo7yQk/S4wy9
# 4JsmhYKKAa8j4owuXh1AZpiFZDmBk6YgGhKjfT2UboviWgeiiwrDmlwHIdydQArg
# dHkRc58YZo3pblSEcGaTp9sDMO8+QUUn+dkfGKjx11Gimc9fZuG7ZIYbLg1Zy6dt
# YyNOaBw3xbyIh5LvyP6xxN/Nc502C/k1n4cg0EiJQ9ZnvxfXuxsPpmOSNQezzqBL
# l9DwZh/BuQTdv2T/N0Gh5/swTdG7hK7w+jFvoT13HR91j238koIIVHpxVAiLun2/
# LnuTwANIresId92TneKJemSsuDE0A9qtkJyQSOUvJE1W0zXI1nt/Z+QWOtMtP+s4
# mGZ6LSt2604q8sticZCJb+ercEH0fCVL2gS/f1hDGj0f8A7SIW0Xv5hBA0brFoA8
# V1JC1pcX9gQWwWm00VPbsvS0dOdOsbPw8H0f80CEDa9FZcGAyBJEPXpCn9867hjR
# j1NRBkw3bpIngqHx722LpCwhYja8Zqdjuvp8RQ0Rtx4UXAeFjg==
# SIG # End signature block
