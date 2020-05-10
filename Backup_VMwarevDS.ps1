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

	Write-Host "                                                                                    " -BackgroundColor Black -ForegroundColor White
	Write-Host "               This FREE script was brought to you by Conversant Group              " -BackgroundColor Black -ForegroundColor White
	Write-Host "We design, build, and manage infrastructure for a secure, dependable user experience" -BackgroundColor Black -ForegroundColor White
	Write-Host "                       Visit our website conversantgroup.com                        " -BackgroundColor Black -ForegroundColor White
	Write-Host "                                                                                    " -BackgroundColor Black -ForegroundColor White
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