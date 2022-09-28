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
	VERSION: 1.0
	AUTHOR: Carl Webster with code borrowed from Jake Rutski
	LASTEDIT: January 8, 2020
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

    If (((Get-Module -ListAvailable | Where-Object {$_.Name -eq "VMware.PowerCLI"}) -ne $null))
    {
        $PSDefaultParameterValues = @{"*:Verbose"=$True}
        # PowerCLI is installed via PowerShell Gallery\or the module is installed
        Write-Verbose "$(Get-Date): PowerCLI Module install found"
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
    cd $tempPWD 4>$Null
    Write-Verbose "$(Get-Date): Setting PowerCLI global Configuration"
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -DisplayDeprecationWarnings $False -Confirm:$False *>$Null

    #Are we already connected to VC?
    If($global:DefaultVIServer)
    {
        Write-Host "`nIt appears PowerCLI is already connected to a VCenter Server. Please use the 'Disconnect-VIServer' cmdlet to disconnect any sessions before running inventory."
        Exit
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
# MIIf8QYJKoZIhvcNAQcCoIIf4jCCH94CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMkAQvoBrXhB84nbTlSW0RDiC
# XuygghtYMIIDtzCCAp+gAwIBAgIQDOfg5RfYRv6P5WD8G/AwOTANBgkqhkiG9w0B
# AQUFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMDYxMTEwMDAwMDAwWhcNMzExMTEwMDAwMDAwWjBlMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3Qg
# Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCtDhXO5EOAXLGH87dg
# +XESpa7cJpSIqvTO9SA5KFhgDPiA2qkVlTJhPLWxKISKityfCgyDF3qPkKyK53lT
# XDGEKvYPmDI2dsze3Tyoou9q+yHyUmHfnyDXH+Kx2f4YZNISW1/5WBg1vEfNoTb5
# a3/UsDg+wRvDjDPZ2C8Y/igPs6eD1sNuRMBhNZYW/lmci3Zt1/GiSw0r/wty2p5g
# 0I6QNcZ4VYcgoc/lbQrISXwxmDNsIumH0DJaoroTghHtORedmTpyoeb6pNnVFzF1
# roV9Iq4/AUaG9ih5yLHa5FcXxH4cDrC0kqZWs72yl+2qp/C3xag/lRbQ/6GW6whf
# GHdPAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0G
# A1UdDgQWBBRF66Kv9JLLgjEtUYunpyGd823IDzAfBgNVHSMEGDAWgBRF66Kv9JLL
# gjEtUYunpyGd823IDzANBgkqhkiG9w0BAQUFAAOCAQEAog683+Lt8ONyc3pklL/3
# cmbYMuRCdWKuh+vy1dneVrOfzM4UKLkNl2BcEkxY5NM9g0lFWJc1aRqoR+pWxnmr
# EthngYTffwk8lOa4JiwgvT2zKIn3X/8i4peEH+ll74fg38FnSbNd67IJKusm7Xi+
# fT8r87cmNW1fiQG2SVufAQWbqz0lwcy2f8Lxb4bG+mRo64EtlOtCt/qMHt1i8b5Q
# Z7dsvfPxH2sMNgcWfzd8qVttevESRmCD1ycEvkvOl77DZypoEd+A5wwzZr8TDRRu
# 838fYxAe+o0bJW1sj6W3YQGx0qMmoRBxna3iw/nDmVG3KwcIzi7mULKn+gpFL6Lw
# 8jCCBSYwggQOoAMCAQICEAZY+tvHeDVvdG/HsafuSKwwDQYJKoZIhvcNAQELBQAw
# cjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQ
# d3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVk
# IElEIENvZGUgU2lnbmluZyBDQTAeFw0xOTEwMTUwMDAwMDBaFw0yMDEyMDQxMjAw
# MDBaMGMxCzAJBgNVBAYTAlVTMRIwEAYDVQQIEwlUZW5uZXNzZWUxEjAQBgNVBAcT
# CVR1bGxhaG9tYTEVMBMGA1UEChMMQ2FybCBXZWJzdGVyMRUwEwYDVQQDEwxDYXJs
# IFdlYnN0ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDCib5DeGTG
# 3J70a2CA8i9n+dPsDklvWpkUTAuZesMTdgYYYKJTsaaNY/UEAHlJukWzaoFQUJc8
# cf5mUa48zGHKjIsFRJtv1YjaeoJzdLBWiqSaI6m3Ttkj8YqvAVj7U3wDNc30gWgU
# eJwPQs2+Ge6tVHRx7/Knzu12RkJ/fEUwoqwHyL5ezfBHfIf3AiukAxRMKrsqGMPI
# 20y/mc8oiwTuyCG9vieR9+V+iq+ATGgxxb+TOzRoxyFsYOcqnGv3iHqNr74y+rfC
# /HfkieCRmkwh0ss4EVnKIJMefWIlkH3HPirYn+4wmeTKQZmtIq0oEbJlXsSryOXW
# i/NjGfe2xXENAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRaxLl7KgqjpepxA8Bg
# +S32ZXUOWDAdBgNVHQ4EFgQUqRd4UyWyhbxwBUPJhcJf/q5IdaQwDgYDVR0PAQH/
# BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGGL2h0
# dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMDWg
# M6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcx
# LmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRw
# czovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCBhAYIKwYBBQUHAQEE
# eDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTgYIKwYB
# BQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNIQTJB
# c3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3
# DQEBCwUAA4IBAQBMkLEdY3RRV97ghwUHUZlBdZ9dFFjBx6WB3rAGTeS2UaGlZuwj
# 2zigbOf8TAJGXiT4pBIZ17X01rpbopIeGGW6pNEUIQQlqaXHQUsY8kbjwVVSdQki
# c1ZwNJoGdgsE50yxPYq687+LR1rgViKuhkTN79ffM5kuqofxoGByxgbinRbC3PQp
# H3U6c1UhBRYAku/l7ev0dFvibUlRgV4B6RjQBylZ09+rcXeT+GKib13Ma6bjcKTq
# qsf9PgQ6P5/JNnWdy19r10SFlsReHElnnSJeRLAptk9P7CRU5/cMkI7CYAR0GWdn
# e1/Kdz6FwvSJl0DYr1p0utdyLRVpgHKG30bTMIIFMDCCBBigAwIBAgIQBAkYG1/V
# u2Z1U0O1b5VQCDANBgkqhkiG9w0BAQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYD
# VQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAw
# WhcNMjgxMDIyMTIwMDAwWjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNl
# cnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdp
# Q2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/
# 5aid2zLXcep2nQUut4/6kkPApfmJ1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH
# 03sjlOSRI5aQd4L5oYQjZhJUM1B0sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxK
# hwjfDPXiTWAYvqrEsq5wMWYzcT6scKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr
# /mzLfnQ5Ng2Q7+S1TqSp6moKq4TzrGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi
# 6CxR93O8vYWxYoNzQYIH5DiLanMg0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCC
# AckwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAww
# CgYIKwYBBQUHAwMweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8v
# b2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6
# MHgwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1s
# AAIEMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMw
# CgYIYIZIAYb9bAMwHQYDVR0OBBYEFFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1Ud
# IwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+
# 7A1aJLPzItEVyCx8JSl2qB1dHC06GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbR
# knUPUbRupY5a4l4kgU4QpO4/cY5jDhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7
# uq+1UcKNJK4kxscnKqEpKBo6cSgCPC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7
# qPjFEmifz0DLQESlE/DmZAwlCEIysjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPa
# s7CM1ekN3fYBIM6ZMWM9CBoYs4GbT8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR
# 6mhsRDKyZqHnGKSaZFHvMIIGajCCBVKgAwIBAgIQAwGaAjr/WLFr1tXq5hfwZjAN
# BgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBBc3N1cmVkIElEIENBLTEwHhcNMTQxMDIyMDAwMDAwWhcNMjQxMDIyMDAwMDAw
# WjBHMQswCQYDVQQGEwJVUzERMA8GA1UEChMIRGlnaUNlcnQxJTAjBgNVBAMTHERp
# Z2lDZXJ0IFRpbWVzdGFtcCBSZXNwb25kZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQCjZF38fLPggjXg4PbGKuZJdTvMbuBTqZ8fZFnmfGt/a4ydVfiS
# 457VWmNbAklQ2YPOb2bu3cuF6V+l+dSHdIhEOxnJ5fWRn8YUOawk6qhLLJGJzF4o
# 9GS2ULf1ErNzlgpno75hn67z/RJ4dQ6mWxT9RSOOhkRVfRiGBYxVh3lIRvfKDo2n
# 3k5f4qi2LVkCYYhhchhoubh87ubnNC8xd4EwH7s2AY3vJ+P3mvBMMWSN4+v6GYeo
# fs/sjAw2W3rBerh4x8kGLkYQyI3oBGDbvHN0+k7Y/qpA8bLOcEaD6dpAoVk62RUJ
# V5lWMJPzyWHM0AjMa+xiQpGsAsDvpPCJEY93AgMBAAGjggM1MIIDMTAOBgNVHQ8B
# Af8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDCC
# Ab8GA1UdIASCAbYwggGyMIIBoQYJYIZIAYb9bAcBMIIBkjAoBggrBgEFBQcCARYc
# aHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzCCAWQGCCsGAQUFBwICMIIBVh6C
# AVIAQQBuAHkAIAB1AHMAZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBp
# AGMAYQB0AGUAIABjAG8AbgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBlAHAAdABh
# AG4AYwBlACAAbwBmACAAdABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABDAFAALwBD
# AFAAUwAgAGEAbgBkACAAdABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABhAHIAdAB5
# ACAAQQBnAHIAZQBlAG0AZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBpAHQAIABs
# AGkAYQBiAGkAbABpAHQAeQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBvAHIAcABv
# AHIAYQB0AGUAZAAgAGgAZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQByAGUAbgBj
# AGUALjALBglghkgBhv1sAxUwHwYDVR0jBBgwFoAUFQASKxOYspkH7R7for5XDStn
# As0wHQYDVR0OBBYEFGFaTSS2STKdSip5GoNL9B6Jwcp9MH0GA1UdHwR2MHQwOKA2
# oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRENB
# LTEuY3JsMDigNqA0hjJodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRB
# c3N1cmVkSURDQS0xLmNybDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0
# dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2Vy
# dHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEQ0EtMS5jcnQwDQYJKoZI
# hvcNAQEFBQADggEBAJ0lfhszTbImgVybhs4jIA+Ah+WI//+x1GosMe06FxlxF82p
# G7xaFjkAneNshORaQPveBgGMN/qbsZ0kfv4gpFetW7easGAm6mlXIV00Lx9xsIOU
# GQVrNZAQoHuXx/Y/5+IRQaa9YtnwJz04HShvOlIJ8OxwYtNiS7Dgc6aSwNOOMdgv
# 420XEwbu5AO2FKvzj0OncZ0h3RTKFV2SQdr5D4HRmXQNJsQOfxu19aDxxncGKBXp
# 2JPlVRbwuwqrHNtcSCdmyKOLChzlldquxC5ZoGHd2vNtomHpigtt7BIYvfdVVEAD
# kitrwlHCCkivsNRu4PQUCjob4489yq9qjXvc2EQwggbNMIIFtaADAgECAhAG/fkD
# lgOt6gAK6z8nu7obMA0GCSqGSIb3DQEBBQUAMGUxCzAJBgNVBAYTAlVTMRUwEwYD
# VQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAi
# BgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0wNjExMTAwMDAw
# MDBaFw0yMTExMTAwMDAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERp
# Z2lDZXJ0IEFzc3VyZWQgSUQgQ0EtMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
# AQoCggEBAOiCLZn5ysJClaWAc0Bw0p5WVFypxNJBBo/JM/xNRZFcgZ/tLJz4Flnf
# nrUkFcKYubR3SdyJxArar8tea+2tsHEx6886QAxGTZPsi3o2CAOrDDT+GEmC/sfH
# MUiAfB6iD5IOUMnGh+s2P9gww/+m9/uizW9zI/6sVgWQ8DIhFonGcIj5BZd9o8dD
# 3QLoOz3tsUGj7T++25VIxO4es/K8DCuZ0MZdEkKB4YNugnM/JksUkK5ZZgrEjb7S
# zgaurYRvSISbT0C58Uzyr5j79s5AXVz2qPEvr+yJIvJrGGWxwXOt1/HYzx4KdFxC
# uGh+t9V3CidWfA9ipD8yFGCV/QcEogkCAwEAAaOCA3owggN2MA4GA1UdDwEB/wQE
# AwIBhjA7BgNVHSUENDAyBggrBgEFBQcDAQYIKwYBBQUHAwIGCCsGAQUFBwMDBggr
# BgEFBQcDBAYIKwYBBQUHAwgwggHSBgNVHSAEggHJMIIBxTCCAbQGCmCGSAGG/WwA
# AQQwggGkMDoGCCsGAQUFBwIBFi5odHRwOi8vd3d3LmRpZ2ljZXJ0LmNvbS9zc2wt
# Y3BzLXJlcG9zaXRvcnkuaHRtMIIBZAYIKwYBBQUHAgIwggFWHoIBUgBBAG4AeQAg
# AHUAcwBlACAAbwBmACAAdABoAGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQAZQAg
# AGMAbwBuAHMAdABpAHQAdQB0AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBjAGUAIABv
# AGYAIAB0AGgAZQAgAEQAaQBnAGkAQwBlAHIAdAAgAEMAUAAvAEMAUABTACAAYQBu
# AGQAIAB0AGgAZQAgAFIAZQBsAHkAaQBuAGcAIABQAGEAcgB0AHkAIABBAGcAcgBl
# AGUAbQBlAG4AdAAgAHcAaABpAGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBhAGIAaQBs
# AGkAdAB5ACAAYQBuAGQAIABhAHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBhAHQAZQBk
# ACAAaABlAHIAZQBpAG4AIABiAHkAIAByAGUAZgBlAHIAZQBuAGMAZQAuMAsGCWCG
# SAGG/WwDFTASBgNVHRMBAf8ECDAGAQH/AgEAMHkGCCsGAQUFBwEBBG0wazAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290
# Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3Js
# NC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMB0GA1Ud
# DgQWBBQVABIrE5iymQftHt+ivlcNK2cCzTAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzANBgkqhkiG9w0BAQUFAAOCAQEARlA+ybcoJKc4HbZbKa9Sz1Lp
# MUerVlx71Q0LQbPv7HUfdDjyslxhopyVw1Dkgrkj0bo6hnKtOHisdV0XFzRyR4WU
# VtHruzaEd8wkpfMEGVWp5+Pnq2LN+4stkMLA0rWUvV5PsQXSDj0aqRRbpoYxYqio
# M+SbOafE9c4deHaUJXPkKqvPnHZL7V/CSxbkS3BMAIke/MV5vEwSV/5f4R68Al2o
# /vsHOE8Nxl2RuQ9nRc3Wg+3nkg2NsWmMT/tZ4CMP0qquAHzunEIOz5HXJ7cW7g/D
# vXwKoO4sCFWFIrjrGBpN/CohrUkxg0eVd3HcsRtLSxwQnHcUwZ1PL1qVCCkQJjGC
# BAMwggP/AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAZY+tvHeDVvdG/Hsafu
# SKwwCQYFKw4DAhoFAKBAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMCMGCSqG
# SIb3DQEJBDEWBBQz5ca/2EJgFxIzpEyGmhRXHZr92jANBgkqhkiG9w0BAQEFAASC
# AQBg1krRQ3Rqfji/qZt7ZOHbkZQl2p4CMMB0aN57rrjQYQaeFaWmVbT17IkOUDwT
# +dUoOhL02KGLNO/feafGZDXwlLr5I/rDO7XF1iEIbQbUf5D5RFmKq5tx2DKGik7b
# CwGTx1uVCjUb/LS6sx30WVvIWCZGkmeYFujIW9kC5gSg5uMyB9CUevi1RFb1a+BY
# JQMsNJohz9hhqATi+YEoZNKTRZvENfpek8cZlKyp/CRaFXwq3QVdH2dmv8m0824t
# hdRllqqFDCghqZZUfDhlh1ya6J0mc5CQV9BYfU9gkDb+iK9CD7LMKiHbANRhTQDm
# hx9Vcbq8fZfUZHzJaQvhWsaIoYICDzCCAgsGCSqGSIb3DQEJBjGCAfwwggH4AgEB
# MHYwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UE
# CxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgQXNzdXJlZCBJ
# RCBDQS0xAhADAZoCOv9YsWvW1ermF/BmMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0B
# CQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMDEwMzExMjA5NTJaMCMG
# CSqGSIb3DQEJBDEWBBTIfPYN0cbUN118rKktNloCJdiU4zANBgkqhkiG9w0BAQEF
# AASCAQAb+nRsnUauMH0NW2ZytlxowBOsDKSgsbAzOgv6O9A+iL57w5f/I04Uwwp6
# MHPtTGsSfcL/4v4fBYlQLO/+JtDNfH18GZqO/eVjQBDve05ypjWyANXgrZl7H/or
# k4aK0XhZIxoZsSl8w7nF2F5RFJIA03MPwxX2l/2DDDj2aTliziS/v2GIREXHh/1H
# cg4oodyAdfExn+58Rt4TnGSB0zzNPwycffC2RayZNKEVvA4/7MRcRKvHc2IWcEuE
# Ie1SjQRxZBtQnATuSjf4Pi+7gykQeFpUaU+MWf5HiTj3IhfxWC0TqnRuYSv6Qg79
# GygcVUvfezilYcZGE4suefq8gwCx
# SIG # End signature block
