New-NetIPAddress -interfaceAlias "Ethernet" -IPAddress 10.0.1.4 -PrefixLength 16
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.0.1.2, 8.8.8.8
Remove-Item C:\unattend.xml
net user administrator "Hyper-v_installthings"
Rename-Computer -NewName "custom-name" -Force -Restart
