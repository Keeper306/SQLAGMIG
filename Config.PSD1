@{  
    
    <#
        SqlStanaloneInstallation - Properties for sql Installation AOAG for Source (Primary node) and destination (Secondary node)
        MediaFilesPath - Folder for SQL distr. For example D:\SQLSetup\.
        SourceInstanceID - Instance ID for source node.
        DestInstanceID - Instance ID for destination node
        SourceServiceAccountName - Service account that will be used for sql instance and sql agent services on source node.
        DestServiceAccountName - Service account that will be used for sql instance and sql agent services on destination node.
    #>
    SqlStanaloneInstallation=@{
        
        MediaFilesPath='\\axpost\VM\GoldImages\SQL2012\'        
        SourceInstanceID="AGT"
        DestInstanceID='AGT'       
        SourceServiceAccountName='labrp\aivanov'
        DestServiceAccountName='labrp\aivanov'
        SourceInstancePath='C:\'
        DestInstancePath='C:\'
    }   

    <#Sourcesqlserver - describe source server (with cluster SQL instance) and its resources.
        Name - Name of source server.        
    #>
    SourceSqlServer = @{
        Name='lab-ufpssql0101'         
        <#DatabaseDisk - describe cluster disk that contain databases for migration process.
            Label - Drive letter of cluster disk
            GUID - GUID of cluster disk. Use 'Get-disk|select disknumber,uniqueid,GUID' to get this value.
        #>        
        DatabaseDisk =@{
            Label='G:\'
            GUID='b6141207-a824-4f67-acad-b615f413c5ff'
        }
        <#SystemDatabases - describe parameters of system databases.
            ParentPath - folder where database files reside.
            DBLogicalName - logical name of database data in mssql.
            LogLogicalName - logical name of database log in mssql.
            DBFileName - name of database file.
            LogFileName - name of log file.
        #>
        SystemDatabases=@{
            msdb= @{             
                ParentPath="G:\MSSQL11.UFPSSQL01\MSSQL\DATA"
                DBFileName="MSDBData.mdf"
                LogFileName="MSDBLog.ldf"
            }
            model=@{
               ParentPath="G:\MSSQL11.UFPSSQL01\MSSQL\DATA"
                DBFileName="model.mdf"
                LogFileName='modellog.ldf'
            }
            tempdb=@{
                 DBLogicalName='tempdev'
                LogLogicalName='templog'
                ParentPath='G:\MSSQL11.UFPSSQL01\MSSQL\DATA'
                DBFileName='tempdb.mdf'
                LogFileName='templog.ldf'
            }
        }
        <#Dataases - desribe application databases that will be migrated from cluster sql instance to
        stanalone sql instance and then will be joined to availability group.
            DBName - Name of database object in SQL
            DBFileName - Name of database file.
            DBLogFileName - Name of database log file.        
        #>
        Databases=@{
       AXDB=@{
                DBName='EMC_AX_MSK'
                DBFileName='EMC_AX_MSK.mdf'
                LogFileName='EMC_AX_MSK_log.ldf'
                DBFileParentPath="G:\DB\"
                DBLogFilePath="G:\DB\"
            }
            AXModelDB=@{
                DBName='EMC_AX_MSK_model'
                DBFileName='EMC_AX_MSK_model.mdf'
                LogFileName='EMC_AX_MSK_model_log.ldf'
                DBFileParentPath="G:\DB\"
                DBLogFilePath="G:\DB\"
            }                      
        }        
    }
    <#DestinationsqlServer - Describe secondary node. That will be joined to AlwaysON availablity group.
        Name - Name of destination secondary node.
        StandaloneInstanceName - Full instance name of sql server on secondary node.   
    #>
    DestinationSqlServer = @{
        Name='lab-aosql0101'
        StandaloneInstanceName='lab-aosql0101\agt'        
    }
    <#SourceSqlCluster - Describe SQL failover cluster in configuration N+1.
        ClusterGroups - Container of cluster roles in failover cluster that will be migrated.
            Group1 - Describe first cluster group role. This role must contain clustered instance from which AX databases will be migrated.
                Name - Name of cluster role (NOT CNO !!! use Get-ClusterGroup to receive it).
                VCOName - Name of VCO (Virtual Computer object) object in role.
                InstanceName - Name of SQL cluster instance in format VCONAME\InstanceID. 
                InstanceID - Instace ID of SQL cluster instance.
    
    #>
    SourceSqlCluster=@{
        ClusterGroups = @{
            Group1=@{
                Name='SQL Server (UFPSSQL01)'
                VCOName='ufpssql01'
                InstanceId='ufpssql01'
            }              
        }        
    }
    <#DestinationSqlCluster - Describe SQL failover cluster in configuration 1+1 AlwaysON
        CNO - Cluster name object for failover cluster.
        IPAddress - IP address of cluster CNO.
        WitnessShare - UNC path of witness share for cluster quorum.
    #>
     DestinationSqlCluster=@{
        CNO="lab-aosql01c"
        IPAddress='172.10.20.32'
        WitnessShare='\\lab-iscsi01\Quorum\lab-aosql01c'
    }

    <#AvaiabilityGroup - Describe properties of SQL availability group that will be created on source sql server.
    Name - Name of Availability Group. This name also will be used for Listener creation.
    StaticIp - IP address of availability group istener (cluster VCO).
    #>
    AvaiabilityGroup=@{
        
        Name='D01EMCDBSMR'
        StaticIp='10.193.117.228/255.255.248.0'  
    }

    <#BackupShare - Backup Share for AG Database migration. Need only for automatic backup (Don't fill if backups and restore application databases manually).
    Name - Name of share that will be created on source SQL server (If you need to create a file share).
    FullUncPath - UNC path that will be used for restore and backup operation.
    #>
    BackupShare=@{
    Name="UfpsBkp" 
    UncPath="\\D01EASCLTDB01\UfpsBkp" #FullUncPath
    }

    <#SqlUserList - Describes users that must be created on sql stanadlone instances on both servers (source and destination).
        UserNumber - Name of the user in domain\username format.  
    #>
    SqlUserList=@{
        User1='labrp\SqlUser'

    <#SqlUserAdminList - Describes users that must be created on sql stanadlone instances on both servers (source and destination).
    This users will get sysadmin roles on SQL server.
        UserNumber - Name of the user in domain\username format.  
    #>   
    }

    SqlUserAdminList=@{
        User1='labrp\sqlAdmin'
          }
    
             

   
}