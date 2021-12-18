# Linux Libvirt Build Pipeline
A build pipeline tool that utilizes libvirt to run a Windows VM and build executables

This may not work for all projects but works well for compiling tools / exploits for Red Team/Pentesting and doesn't mean you won't ever have to touch the VM again to add packages but it is also a start for an easier building from linux. I will be expanding this as I run into issues or find improvements.

## Usage:
```
################################################
############ Linux Libvirt Pipeline ############
################################################

A build pipeline tool that utilizes libvirt to run
A Windows VM and build executables

Required Parameters: 
	-b|--build		Specify the build's csproj file

Optional Parameters: 
	-r|--release		Set Build Configuration to 'Release'. Cannot be used with -d. (default)
	-d|--debug		Set Build Configuration to 'Debug'. Cannot be used with -r
	-p|--platform		Set Build Platform.
				Expected Values: x86 | x64 (default) | AnyCpu
	-m|--msbuild-path	Set MSBuild.exe Path which inherently sets the version.
				Example: "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
	-o|--outputdir		Set Windows output path for the build. Defaults to ./bin/<release/debug>.
	--dont-stop-vm		If set, this will not kill the vm after the build

```

## Features:
	- Automatically Start/Stop VM with virtsh
	- Automatically Start/Stop smbD using libvirt hooks
	- Auto mouting the SMB share.
	- Utilizes SSH to vm into VM and run build tools


## Setup:
This assumes you have a working libvirt VM running windows 10 named "win10-dev". 

 - Requirements:
	- Linux Host:
		- LibvirtD
		- smbD
	- Windows Guest:
		- OpenSSH Server
		- Visual Studio / Other Build Tools.

#### Windows Guest:
 - Generate SSH key, copy to Host.
 - Add SSH key to authorized_keys
 - Install Visual studio.
 - Create (```New-Item -type file -force $profile```) or modify powershell profile:
 	- Add the line  ```net use Z: \\<vm_default_gateway>\<share_name> /user:<smb_user> <smb_pass>```
 - Set Powershell Execution policy to prevent future issues: ```Set-ExecutionPolicy Unrestricted```
 - Set OpenSSH Default shell to powershell with Regedit: ```/HKLM/SOFTWARE/OpenSSH/DefaultShell``` -> ```C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe```
 - Allow Linked Connections: ```reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableLinkedConnections" /t REG_DWORD /d 0x00000001 /f```
 - *Recommended:*
 	- Assuming you use this for a similar purpose, Disable Defender using Group Policy
 	- Administrative Templates > Windows Components > Windows Defender Antivirus > Turn off Windows Defender Antivirus = Enabled
 	- Administrative Templates > Windows Components > Windows Defender Antivirus > Real-Time Protection > Turn off real-time protection = Enabled

#### Linux Host:
 - Add a hostname / ip to your ```/etc/hosts``` file.
 - Copy the SSH private from the windows host to your favorite ssh key storage location.
 - Add a ~/.ssh/config entry for your VM with the hostname you used in the /etc/hosts file. (Example in ssh/config)
 - Install smbd using your prefered method.
 - Modify the config to have a share where you typically build. I used /opt and disable all other shares including printer and home directories. (Example in etc/samba/smb.conf)
 - Create a hooks script and make it executable in ```/etc/libvirt/hooks/qemu``` (Example/Working in etc/libvirt/hooks/qemu)
 - Modify the default values in the build_exe.sh to fit your setup / build tools.

#### Configurables:
The default values I used is available in the top of the file
```
VIRSH_DOMAIN="win10-dev" ## your libvirt vm domain
SSH_NAME="dev-machine" ## Whatever you named it in /etc/hosts
DEF_MSBUILD='C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild.exe' ## This path varies based on version
DEF_OUTPUTDIR="bin/" ## This is used along with DEF_BCONFIG AND DEF_BPLAT to mkae a standard deployment path in the working directory
DEF_BCONFIG="Release" ## This is usually either Release or Debug
DEF_BPLAT="x64" ## This could also be ARM or something similar but I didn't build that into the script

Z_PATH="/opt/" ## This should be the path to your shared folder. Helps the script make sure the VM can access the file you want to build.

SSH_TIMEOUT=5 ## How long should the SSH timeout if your vm isn't ready
SSH_RETRIES=3 ## max times the script tries to login - ususally takes 2 but could vary based on system specs.
```
