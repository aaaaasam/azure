#!/usr/bin/env python3
# encoding: utf-8

from azure.common.credentials import ServicePrincipalCredentials

subscription_id = '088cad50-fc-7b741cf96d94'
tenant_id = 'a9d009af-458c-deec340e46cf'
client_id = 'd9ae4e19-3ecab5cc85dd396'
client_secret = '1R_0q6tm~Q88dwn9~D~N_m_~'

credential = ServicePrincipalCredentials(tenant=tenant_id, client_id=client_id, secret=client_secret)

'''
from azure.mgmt.resource import SubscriptionClient
subscription_client = SubscriptionClient(credential)

subscription = next(subscription_client.subscriptions.list())
print(subscription.subscription_id)
'''

from azure.mgmt.network import NetworkManagementClient

waf_policy_name = "test-policy-01"
waf_policy_rg_name = "testwaf"
networkmanageclient = NetworkManagementClient(subscription_id=subscription_id, credentials=credential)

# Get Azure Policy info.
waf_policy_info = networkmanageclient.web_application_firewall_policies.get(resource_group_name=waf_policy_rg_name, policy_name=waf_policy_name).as_dict()
waf_policy_info['custom_rules'][0]['match_conditions'][0]['match_values'] = ['10.0.0.0/16', '10.1.0.0/16', '10.2.0.0/16', '10.3.0.0/16']

# Put new blacklist to Azure 
networkmanageclient.web_application_firewall_policies.create_or_update(resource_group_name=waf_policy_rg_name, policy_name=waf_policy_name, parameters=waf_policy_info)