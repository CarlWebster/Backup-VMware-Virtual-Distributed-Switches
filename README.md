# BackupVMwareVirtualDistributedSwitches
Backup (Export) VMware Virtual Distributed Switches

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
