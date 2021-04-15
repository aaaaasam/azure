import azure.mgmt.resource
import automationassets
from msrestazure.azure_cloud import AZURE_PUBLIC_CLOUD
from azure.mgmt.compute import ComputeManagementClient
from datetime import datetime
from datetime import timedelta
import time
import re


def get_automation_runas_credential(runas_connection, resource_url, authority_url ):
    """ Returns credentials to authenticate against Azure resoruce manager """
    from OpenSSL import crypto
    from msrestazure import azure_active_directory
    import adal

    # Get the Azure Automation RunAs service principal certificate
    cert = automationassets.get_automation_certificate("AzureRunAsCertificate")
    pks12_cert = crypto.load_pkcs12(cert)
    pem_pkey = crypto.dump_privatekey(crypto.FILETYPE_PEM, pks12_cert.get_privatekey())

    # Get run as connection information for the Azure Automation service principal
    application_id = runas_connection["ApplicationId"]
    thumbprint = runas_connection["CertificateThumbprint"]
    tenant_id = runas_connection["TenantId"]

    # Authenticate with service principal certificate
    authority_full_url = (authority_url + '/' + tenant_id)
    context = adal.AuthenticationContext(authority_full_url)
    return azure_active_directory.AdalAuthentication(
        lambda: context.acquire_token_with_client_certificate(
            resource_url,
            application_id,
            pem_pkey,
            thumbprint)
    )


# Authenticate to Azure using the Azure Automation RunAs service principal
runas_connection = automationassets.get_automation_connection("AzureRunAsConnection")
resource_url = AZURE_PUBLIC_CLOUD.endpoints.active_directory_resource_id
authority_url = AZURE_PUBLIC_CLOUD.endpoints.active_directory
resourceManager_url = AZURE_PUBLIC_CLOUD.endpoints.resource_manager
azure_credential = get_automation_runas_credential(runas_connection, resource_url, authority_url)


disk_resource_id_list = [
    ('/subscriptions/a61933a3-71ed-4ae8-99c2-fc57d9311428/resourceGroups/sam-test-backup-rg/providers/Microsoft.Compute/disks/test01', 'eastasia'),
    ('/subscriptions/a61933a3-71ed-4ae8-99c2-fc57d9311428/resourceGroups/sam-test-backup-rg/providers/Microsoft.Compute/disks/test02', 'eastasia')
]


CMClient = ComputeManagementClient(credentials=azure_credential, subscription_id=runas_connection["SubscriptionId"])


def create_snapshot(diskinfo):
    _resource_id = diskinfo[0]
    _location = diskinfo[1]
    _disk_name = _resource_id.split('/')[-1]
    _resource_group = re.match('.*/resourceGroups/(.*?)/.*', _resource_id).group(1)
    _time = time.strftime('%Y%m%d%H%M%S')
    _snapshotname = "{}_{}".format(_disk_name, _time)
    _snapshot_metadata = {
        'location': _location, 
        'creation_data': {
            'create_option': 'Copy', 
            'source_uri': _resource_id
        }, 
        'incremental': 'true'
    }

    return CMClient.snapshots.create_or_update(_resource_group ,_snapshotname , _snapshot_metadata)


def get_snapshot_resource_id_list(CMC):
    return [
        resouce.id for resouce in CMC.snapshots.list()
    ]

def delete_snapshot(CMC, id):
    _snapshot_name = id.split('/')[-1]
    _resource_group_name = id.split('/')[4]
    CMC.snapshots.delete(
        resource_group_name=_resource_group_name,
        snapshot_name=_snapshot_name
    )

def check_snapshot_and_delete_it_when_timeout(CMC, snapshot_id_list, days=7):
    _timeout = int((datetime.now() - timedelta(days=days)).strftime("%Y%m%d")) * 1000000
    #_timeout = 20210416000000
    for _id in snapshot_id_list:
        _create_time = int(_id.split('_')[-1])
        #print(_create_time, _timeout)
        if _create_time < _timeout:
            print("The id({}) will be delete later.".format(_id))
            delete_snapshot(CMC, _id)

if __name__ == '__main__':
    # Check Snapshot and delete it when it's timeout.
    _snapshot_id_list = get_snapshot_resource_id_list(CMClient)
    check_snapshot_and_delete_it_when_timeout(CMClient, _snapshot_id_list)
    
    # Create Snapshot
    for _diskinfo in disk_resource_id_list:
        print(create_snapshot(_diskinfo).result().as_dict())
    
    