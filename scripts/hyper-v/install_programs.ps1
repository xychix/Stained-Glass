param([String]$LabName, [String]$PassWord, [int32]$ClientCount)

$pass = ConvertTo-SecureString -String $PassWord -AsPlainText -force
$client_creds = New-Object -TypeName System.Management.Automation.PSCredential "lab",$pass
$server_creds = New-Object -TypeName System.Management.Automation.PSCredential "administrator",$pass

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
[xml]$xml = Get-Content -Path "$dir\..\..\configs\labs_config.xml"
[xml]$programs = Get-Content -Path "$dir\..\..\configs\Programs.xml"

# Map DHCP leases to client names
$client_list = @{}
foreach ($vm in $xml.labs.$LabName.ChildNodes) {
    if ($vm.Programs -like "*DHCP*") {
        $dhcp_ip = (Get-VMNetworkAdapter -VMName $vm.Name).IPAddresses[0]
        $scope = $xml.labs.$LabName.IP
        $leases = Invoke-Command -ComputerName $dhcp_ip -Credential $server_creds { Get-DHCPServerV4Lease -ScopeID $using:scope }
        foreach ($lease in $leases) {
            foreach ($client in $xml.labs.$LabName.ChildNodes) {
                if ($client.Type -eq "Client") {
                    if ($client.Name -eq (($lease.HostName).split("."))[0]) { $client_list.Add($client.Name, $lease.IPAddress) }
                }
            }
        }
    }
}

function remote_install ($program, $v, $computer) {

    $ses = New-PSSession -ComputerName $client_list.$computer -Credential $script:client_creds

    $ext = $programs.Programs.$program."$program$v".ext
    $arg = $programs.Programs.$program."$program$v".arg

    Copy-Item -Path G:\lab-deployer\Installers\$program\$program$v.$ext -Destination C:\users\lab\Downloads\ -ToSession $ses

    $InstallString = "`"C:\users\lab\Downloads\$program$v.$ext`" $arg"
    
    #Start-Sleep -s 40
    
    $process = Invoke-Command -Session $ses -ScriptBlock { ([WMICLASS]"\\localhost\ROOT\CIMV2:Win32_Process").Create($using:InstallString) }
    if ($process.ProcessID -eq $NULL) {
        "Something went wrong when installing $program$v.$ext trying direct command invocation"
        $InstallString = "C:\users\lab\Downloads\$program$v.$ext"
        Invoke-Command -Session $ses -ScriptBlock { & cmd.exe /c "$using:InstallString $using:arg" }
    }

    Start-Sleep -s 120
    Remove-PSSession $ses
}

foreach ($vm in $xml.labs.$LabName.Childnodes) {
    if ($vm.Type -eq "Client") {
        

        #$ip = Resolve-DnsName $vm.Name | select ipaddress | foreach { echo $_.IpAddress }

        foreach($program in $vm.Programs.Split(",")) {
            $program, $v = $program.split(";")
            
            "installing $program $v on $($vm.Name)"
            remote_install $program $v $vm.Name
            
        }

        # Fetch installed programs and check if it installed correctly
        "Checking if installation for $($vm.Name) is complete"
        $installed_programs = Invoke-Command -ComputerName $client_list.$($vm.Name) -Credential $client_creds -ScriptBlock { Get-WmiObject -Class win32_product }
        $installed_programs
        
        foreach($program in $vm.Programs.Split(",")) {
            $installed = $False
            $program, $v = $program.split(";")
            if ($program -eq "acrobat") { $program = "adobe" }
            
            foreach ($installed_program in $installed_programs) {
                if ($installed_program.Name -Like "*$program*" -and $installed_program.Name -like "*$v*") {
                    "$($installed_program.Name) installed succesfully"
                    $installed = $True
                }
            }

            if (-not $installed) {
                "$program $v failed retrying once"
                remote_install $program $v $vm.Name
            }
        }
    }
}
