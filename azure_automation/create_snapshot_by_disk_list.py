import azure.mgmt.resource
import automationassets
from msrestazure.azure_cloud import AZURE_PUBLIC_CLOUD
from azure.mgmt.compute import ComputeManagementClient
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

if __name__ == '__main__':
    for _diskinfo in disk_resource_id_list:
        print(create_snapshot(_diskinfo).result().as_dict())