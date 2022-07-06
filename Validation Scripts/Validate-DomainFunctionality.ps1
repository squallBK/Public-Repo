<#
.SYNOPSIS
This script will run through a series of functionality tests, log a pass/fail, and email the result to the appropriate distribution group.

.DESCRIPTION
REQUIRED MODULES - ActiveDirectory, GroupPolicy
OPTIONAL (But Recommended) MODULES - DnsServer

This script will create a test Active Directory OU, Group, and Computer, as well as a test DNS entry if DNS is present on the system. It will then confirm those entries
do exist.

The script will then wait 20 minutes, and then run the same confirmation commands against the other domain controllers.

.PARAMETER ADTestOUName
The name of the test OU to be created. The OU will be created in the root of the domain.

.PARAMETER ADTestGroupName
The name of the test group to be created. The group will be created in the OU that gets created from the parameter ADTestOUName.

.PARAMETER ADTestComputerName
The name of the test computer object to be created. The computer object will be created in the test OU that gets created from the parameter ADTestOUName.

.PARAMETER ADTestGPOName
The name of the GPO to be created.

.PARAMETER DNSTestHostname
The name of the hostname to be added as an A Record into DNS. Will only get created if the DNS role is in fact installed on the server in question.

.PARAMETER DNSTestIPAddress
The IP address to be configured with the DNSTestHostname in DNS. Will only get created if the DNS role is in fact installed on the server in question.

.PARAMETER DNSZoneName
The name of the DNS Zone where the A Record will be created. Will only be acted upon if the DNS role is in fact installed on the server in question.

.PARAMETER SMTPToAddress
The emaill address that will receive test results of this script.

.PARAMETER SMTPServer
The IP address or DNS name of your SMTP Server.

.PARAMETER SMTPFromAddress
The email address that will appear as the sender when the email is sent.

.EXAMPLE
.\Validate-DomainFunctionality.ps1

Runs the script with default parameters. The parameters in here by default right now are really only beneficial to the author, so be sure to
change the default values if you decide to do this.

.EXAMPLE
powershell.exe -ExecutionPolicy ByPass -File "C:\Path\To\File\Validate-DomainFunctionality.ps1"

The syntax to use in a command prompt window. Will behave the same as in the first example.

.EXAMPLE
.\Validate-DomainFunctionality.ps1 -ADTestOUName 'TestOU' -ADTestGroupName 'TestGroup' -ADTestComputerName 'TestComputer' -ADTestGPOName 'TestGPO' -DNSTestHostname 'TestDNSName' -DNSTestIPAddress '169.254.69.69' -DNSZone 'MyZone.com' -ITEmailAddress 'MyEmail@MyZone.com'

Runs the script with custom parameters

.NOTES
Created by: squallBK
Email Address:
Date of Creation: 07/06/2022
Date of update:
Updated by:
#>

##############################
#### PowerShell Parameters ###
##############################
param 
(
    [Parameter()]
    [string]$ADTestOUName,

    [Parameter()]
    [string]$ADTestGroupName,

    [Parameter()]
    [string]$ADTestComputerName,

    [Parameter()]
    [string]$ADTestGPOName,

    [Parameter()]
    [string]$DNSTestHostname,

    [Parameter()]
    [string]$DNSTestIPAddress,

    [Parameter()]
    [string]$DNSZoneName,

    [Parameter()]
    [string]$SMTPToAddress,

    [Parameter()]
    [string]$SMTPServer,

    [Parameter()]
    [string]$SMTPFromAddress
)

##############################
#### PowerShell Modules ######
##############################

## Import the ActiveDirectory PS Module. If it does not exist, exit the script.
If (Get-Module -ListAvailable -Name 'ActiveDirectory')
{
    Write-Output 'INFO: ActiveDirectory PS Module is available. Importing...'
    Import-Module -Name 'ActiveDirectory' -Force
}
Else 
{
    Write-Error 'ERROR: ActiveDirectory PS Module does not exist. Script will now terminate'
    Exit $LASTEXITCODE
}

## Import the GroupPolicy PS Module. If it does not exist, exit the script.
If (Get-Module -ListAvailable -Name 'GroupPolicy')
{
    Write-Output 'INFO: GroupPolicy PS Module is available. Importing...'
    Import-Module -Name 'GroupPolicy' -Force
}
Else
{
    Write-Error 'ERROR: GroupPolicy PS Module does not exist. Script will now terminate'
    Exit $LASTEXITCODE
}

## Import the DnsServer PS Module. If it does not exist, log a variable but continue with script execution.
If (Get-Module -ListAvailable -Name 'DnsServer')
{
    Write-Output 'INFO: DnsServer PS Module is available. Importing...'
    Import-Module -Name 'DnsServer' -Force
    $dnsExists = $true
}
Else
{
    Write-Output 'WARNING: DnsServer PS Module does not exist, but script will proceed to validate Active Directory...'
    $dnsExists = $false
}

##############################
## Script Defined Variables ##
##############################

$computerDomain = Get-ADDomain -Current 'LocalComputer'
$computerDomainDN = $computerDomain.DistinguishedName
$computerDomainDNSRoot = $computerDomain.DNSRoot
$ADTestOUFQDN =  'OU=' + $ADTestOUName + ',' + $computerDomainDN
$ADTestRole = 'Print-Services'
$DCList = Get-ADDomainController -Filter '*' | Select-Object 'Name'
$DCServers = $DCList.Name

##############################
### Script Execution #########
##############################

## Create the test objects
New-ADOrganizationalUnit -Name "$ADTestOUName" -Path "$computerDomainDN" -ProtectedFromAccidentalDeletion $false -Confirm:$false
New-ADGroup -Name "$ADTestGroupName" -SamAccountName "$ADTestGroupName" -GroupCategory 'Security' -GroupScope 'Global' -DisplayName "$ADTestGroupName" -Path "$ADTestOUFQDN" -Confirm:$false
New-ADComputer -Name "$ADTestComputerName" -SAMAccountName "$ADTestComputerName" -Path "$ADTestOUFQDN" -Enabled $true -Confirm:$false
New-GPO -Name "$ADTestGPOName" -Confirm:$false
Install-WindowsFeature -Name "$ADTestRole" -Confirm:$false

## If DNS exists on the server, also add the test DNS A Record
if ($dnsExists)
{
    Add-DnsServerResourceRecordA -Name "$DNSTestHostname" -ZoneName "$DNSZoneName" -AllowUpdateAny -IPv4Address "$DNSTestIPAddress" -TimeToLive '01:00:00' -Confirm:$false
}

## Variables for validating that each object was properly created on the local domain controller
$TestADOUExists = Get-ADOrganizationalUnit -Identity "$ADTestOUFQDN"
If ($TestADOUExists)
{
    $TestADOUResult = 'PASS'
}
Else
{
    $TestADOUResult = 'FAIL'
}
    
$TestADGroupExists = Get-ADGroup -Identity "$ADTestGroupName"
If ($TestADGroupExists)
{
    $TestADGroupResult = 'PASS'
}
Else
{
    $TestADGroupResult = 'FAIL'
}

$TestADComputerExists = Get-ADComputer -Identity "$ADTestComputerName"
If ($TestADComputerExists)
{
    $TestADComputerResult = 'PASS'
}
Else
{
    $TestADComputerResult = 'FAIL'
}

$TestADGPOExists = Get-GPO -Name "$ADTestGPOName"
If ($TestADGPOExists)
{
    $TestADGPOResult = 'PASS'
}
Else
{
    $TestADGPOResult = 'FAIL'
}

$TestWindowsFeatureExists = Get-WindowsFeature -Name "$ADTestRole" | Where-Object 'Installed'
If ($TestWindowsFeatureExists)
{
    $TestWindowsFeatureResult = 'PASS'
}
Else
{
    $TestWindowsFeatureResult = 'FAIL'
}

If($dnsExists)
{
    $TestDNSARecordExists = Get-DnsServerResourceRecord -ZoneName "$DNSZoneName" -Name "$DNSTestHostname"
    If ($TestDNSARecordExists)
    {
        $TestDNSARecordResult = 'PASS'
    }
    Else
    {
        $TestDNSARecordResult = 'FAIL'
    }
}

## Time out for a period of 20 minutes to allow time for AD Replication to occur.
Start-Sleep -Seconds '1200'

## After time expires, proceed to test replication of various objects across your domain.
Foreach ($DCServer in $DCServers)
{
    ## Variables for validating that each object was properly created on the local domain controller
    $TestReplicatedADOUExists = Get-ADOrganizationalUnit -Identity "$ADTestOUFQDN" -Server "$DCServer"
    If ($TestReplicatedADOUExists)
    {
        $TestReplicatedADOUResult = 'PASS'
        New-Variable -Name "ReplicationTestResult-ADOU-$DCServer" -Value "$TestReplicatedADOUResult"
    }
    Else
    {
        $TestReplicatedADOUResult = 'FAIL'
        New-Variable -Name "ReplicationTestResult-ADOU-$DCServer" -Value "$TestReplicatedADOUResult"
    }

    $TestReplicatedADGroupExists = Get-ADGroup -Identity "$ADTestGroupName" -Server "$DCServer"
    If ($TestReplicatedADGroupExists)
    {
        $TestReplicatedADGroupResult = 'PASS'
        New-Variable -Name "ReplicationTestResult-ADGroup-$DCServer" -Value "$TestReplicatedADGroupResult"
    }
    Else
    {
        $TestReplicatedADGroupResult = 'FAIL'
        New-Variable -Name "ReplicationTestResult-ADGroup-$DCServer" -Value "$TestReplicatedADGroupResult"
    }

    $TestReplicatedADComputerExists = Get-ADComputer -Identity "$ADTestComputerName" -Server "$DCServer"
    If ($TestReplicatedADComputerExists)
    {
        $TestReplicatedADComputerResult = 'PASS'
        New-Variable -Name "ReplicationTestResult-ADComputer-$DCServer" -Value "$TestReplicatedADComputerResult"
    }
    Else
    {
        $TestReplicatedADComputerResult = 'FAIL'
        New-Variable -Name "ReplicationTestResult-ADComputer-$DCServer" -Value "$TestReplicatedADComputerResult"
    }

    $TestReplicatedADGPOExists = Get-GPO -Name "$ADTestGPOName" -Server "$DCServer"
    If ($TestReplicatedADGPOExists)
    {
        $TestReplicatedADGPOResult = 'PASS'
        New-Variable -Name "ReplicationTestResult-ADGPO-$DCServer" -Value "$TestReplicatedADGPOResult"
    }
    Else
    {
        $TestReplicatedADGPOResult = 'FAIL'
        New-Variable -Name "ReplicationTestResult-ADGPO-$DCServer" -Value "$TestReplicatedADGPOResult"
    }

    If($dnsExists)
    {
        $TestDNSARecordExists = Get-DnsServerResourceRecord -ComputerName "$DCServer" -ZoneName "$DNSZoneName" -Name "$DNSTestHostname"
        If ($TestDNSARecordExists)
        {
            $TestReplicatedDNSARecordResult = 'PASS'
            New-Variable -Name "ReplicationTestResult-DNS-$DCServer" -Value "$TestReplicatedDNSARecordResult"
        }
        Else
        {
            $TestReplicatedDNSARecordResult = 'FAIL'
            New-Variable -Name "ReplicationTestResult-DNS-$DCServer" -Value "$TestReplicatedDNSARecordResult"
        }
    }
}

## Send an email to the appropriate distribution group with the test results
$DCServerVars = Get-Variable -Name 'ReplicationTestResult*' | ConvertTo-Html -Property 'Name', 'Value'
$EmailBody = @"
<p>Below are the functionality test results for the $computerDomainDNSRoot domain, including Active Directory, local system functionality, and DNS functionality</p>

<p>== Local Server $env:ComputerName Domain Functionality ==<br>
AD OU Creation : $TestADOUResult<br>
AD Group Creation : $TestADGroupResult<br>
AD Computer Creation : $TestADComputerResult<br>
AD GPO Creation : $TestADGPOResult</p>

<p>== Local Server $env:ComputerName Local System Functionality ==<br>
Windows Feature Installation Attempt : $TestWindowsFeatureResult</p>

<p>== Local Server $env:ComputerName DNS Results ==<br>
DNS Record Creation : $TestDNSARecordResult (If this is empty, it can be safely ignored. It merely means the DNS role did not exist on the server.)</p>

<p>== Domain Wide Replication Results ==<br>
$DCServerVars</p>
"@

Send-MailMessage -SmtpServer "$SMTPServer" -From "$SMTPFromAddress" -To "$ITEmailAddress" -Subject "$computerDomainDNSRoot : Domain Functionality Test Results" -Body $EmailBody -BodyAsHtml

## Remove the test objects
Remove-ADOrganizationalUnit -Identity "$ADTestOUFQDN" -Recursive -Confirm:$false
Remove-GPO -Name "$ADTestGPOName" -Confirm:$false
Uninstall-WindowsFeature -Name "$ADTestRole" -Confirm:$false

## If DNS exists on the server, also remove the test DNS A Record
If ($dnsExists)
{
    Remove-DnsServerResourceRecord -ZoneName "$DNSZoneName" -RRType 'A' -Name "$DNSTestHostname" -RecordData "$DNSTestIPAddress" -Confirm:$false -Force
}

## Exit with a 0 error code to register success.
Exit 0