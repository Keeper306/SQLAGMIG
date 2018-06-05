Function Create-SqlConfigFile
{
    [CmdletBinding()]
    Param
        (
            [Parameter(Mandatory=$false)] 
            [ValidateSet('Auto','Manual')]
            [string]$DeploymentType='Auto',

            [Parameter(Mandatory=$true)] 
            [string]$SqlInstanceID,

            [Parameter(Mandatory=$true)] 
            [string]$ConfigFileName,
     

            [Parameter(Mandatory=$false)] 
            [string]$TempFolder='C:\Temp',

            [Parameter(Mandatory=$False)] 
            [string]$SqlInstancePath='C:\Program Files\Microsoft SQL Server',

            [Parameter(Mandatory=$true)] 
            [string]$SqlServiceAccountName,

            [Parameter(Mandatory=$false)] 
            [string]$SqlServerCollation='Cyrillic_General_CI_AS'
        )

    #Create temp folder if it does not exist.
    If (!(Test-Path -Path $TempFolder) )
        {
            New-Item -Path $TempFolder  -Type Directory|Out-Null
        }
    #Result config file path
    $ResultFilePath=($TempFolder+'\'+$ConfigFileName+'.ini')
    #Create empty config file
    New-Item -Path $TempFolder -Name ($ConfigFileName+'.ini') -Type File -Force|Out-Null

    #Define Gui settings based by deployment type
    if ($DeploymentType -eq 'Auto') {$SqlUiMode=';UIMODE="Normal"';$SqlQuiteSimpleState='True'}
    if ($DeploymentType -eq 'Manual') {$SqlUiMode='UIMODE="Normal"';$SqlQuiteSimpleState='False'}
    #Common SQL Configuration Parameters
    $CommonConfig='
    ;SQL Server 2012 Configuration File
    [OPTIONS]

    ; Specifies a Setup work flow, like INSTALL, UNINSTALL, or UPGRADE. This is a required parameter. 
    IACCEPTSQLSERVERLICENSETERMS="True"
    ACTION="Install"

    ; Detailed help for command line argument ENU has not been defined yet. 

    ENU="True"



    ; Specify whether SQL Server Setup should discover and include product updates. The valid values are True and False or 1 and 0. By default SQL Server Setup will include updates that are found. 

    UpdateEnabled="True"

    ; Specifies features to install, uninstall, or upgrade. The list of top-level features include SQL, AS, RS, IS, MDS, and Tools. The SQL feature will install the Database Engine, Replication, Full-Text, and Data Quality Services (DQS) server. The Tools feature will install Management Tools, Books online components, SQL Server Data Tools, and other shared components. 

    FEATURES=SQLENGINE,FULLTEXT,SSMS,ADV_SSMS

    ; Specify the location where SQL Server Setup will obtain product updates. The valid values are "MU" to search Microsoft Update, a valid folder path, a relative path such as .\MyUpdates or a UNC share. By default SQL Server Setup will search Microsoft Update or a Windows Update service through the Window Server Update Services. 

    UpdateSource="MU"

    ; Displays the command line parameters usage 

    HELP="False"

    ; Specifies that the detailed Setup log should be piped to the console. 

    INDICATEPROGRESS="True"

    ; Specifies that Setup should install into WOW64. This command line argument is not supported on an IA64 or a 32-bit system. 

    X86="False"

    ; Specify that SQL Server feature usage data can be collected and sent to Microsoft. Specify 1 or True to enable and 0 or False to disable this feature. 

    SQMREPORTING="False"

    ; Specify if errors can be reported to Microsoft to improve future SQL Server releases. Specify 1 or True to enable and 0 or False to disable this feature. 

    ERRORREPORTING="False"


    '
    $SqlGuiconfig="
    ; Parameter that controls the user interface behavior. Valid values are Normal for the full UI,AutoAdvance for a simplied UI, and EnableUIOnServerCore for bypassing Server Core setup GUI block. 
 
    $SqlUiMode

    ; Setup will not display any user interface. 

    QUIET=`"False`"

    ; Setup will display progress only, without any user interaction. 

    QUIETSIMPLE=`"$SqlQuiteSimpleState`"

    "
    $SqlPathConfig= "
    ; Specify the installation directory. 

    INSTANCEDIR=$SqlInstancePath

    ; Specify the root installation directory for shared components.  This directory remains unchanged after shared components are already installed. 

    INSTALLSHAREDDIR=`"C:\Program Files\Microsoft SQL Server`"

    ; Specify the root installation directory for the WOW64 shared components.  This directory remains unchanged after WOW64 shared components are already installed. 

    INSTALLSHAREDWOWDIR=`"C:\Program Files (x86)\Microsoft SQL Server`"

    "
    $SqlServiceConfig="
    ; Agent account name 

    AGTSVCACCOUNT=`"$SqlServiceAccountName`"

    ; Auto-start service after installation.  

    AGTSVCSTARTUPTYPE=`"Automatic`"

    ; CM brick TCP communication port 

    COMMFABRICPORT=`"0`"

    ; How matrix will use private networks 

    COMMFABRICNETWORKLEVEL=`"0`"

    ; How inter brick communication will be protected 

    COMMFABRICENCRYPTION=`"0`"

    ; TCP port used by the CM brick 

    MATRIXCMBRICKCOMMPORT=`"0`"

    ; Startup type for the SQL Server service. 

    SQLSVCSTARTUPTYPE=`"Automatic`"

    ; Level to enable FILESTREAM feature at (0, 1, 2 or 3). 

    FILESTREAMLEVEL=`"0`"

    ; Set to `"1`" to enable RANU for SQL Server Express. 

    ENABLERANU=`"False`"

    ; Specifies a Windows collation or an SQL collation to use for the Database Engine. 

    SQLCOLLATION=`"$SqlServerCollation`"

    ; Account for SQL Server service: Domain\User or system account. 

    SQLSVCACCOUNT=`"$SqlServiceAccountName`"

    ; Windows account(s) to provision as SQL Server system administrators. 

    SQLSYSADMINACCOUNTS=`"BUILTIN\Administrators`"

    ; The default is Windows Authentication. Use `"SQL`" for Mixed Mode Authentication. 

    SECURITYMODE=`"SQL`"

    ; Provision current user as a Database Engine system administrator for SQL Server 2012 Express. 

    ADDCURRENTUSERASSQLADMIN=`"False`"

    ; Specify 0 to disable or 1 to enable the TCP/IP protocol. 

    TCPENABLED=`"1`"

    ; Specify 0 to disable or 1 to enable the Named Pipes protocol. 

    NPENABLED=`"0`"

    ; Startup type for Browser Service. 

    BROWSERSVCSTARTUPTYPE=`"Automatic`"

    ; Add description of input argument FTSVCACCOUNT 

    FTSVCACCOUNT=`"NT Service\MSSQLFDLauncher`$$SqlInstanceID`"
    "
    $SqlInstanceIDConfig="
    ; Specify a default or named instance. MSSQLSERVER is the default instance for non-Express editions and SQLExpress for Express editions. This parameter is required when installing the SQL Server Database Engine (SQL), Analysis Services (AS), or Reporting Services (RS). 

    INSTANCENAME=`"$SqlInstanceID`"

    ; Specify the Instance ID for the SQL Server features you have specified. SQL Server directory structure, registry structure, and service names will incorporate the instance ID of the SQL Server instance. 

    INSTANCEID=`"$SqlInstanceID`"
    "
    Set-Content -Path $ResultFilePath -Value $CommonConfig,$SqlGuiconfig,$SqlPathConfig,$SqlServiceConfig,$SqlInstanceIDConfig

    $ResultFilePath
    return 
}