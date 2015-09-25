#! /bin/bash 
# Copyright 2015 Cisco Systems, Inc.  All rights reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

###############################################################################
#                                                                             #
# This is a helper script which will delete all resources created by          #
# KloudBuster.                                                                #
#                                                                             #
# Normally, KloudBuster will clean up automatically when it is done. However, #
# sometimes errors or timeouts happen during the rescource creation stage,    #
# which will cause KloudBuster out of sync with the real environment. If that #
# happens, a force cleanup may be needed.                                     #
#                                                                             #
# It is safe to use the script with the resource list generated by            #
# KloudBuster, usage:                                                         #
#     $ source <rc_of_the_openstack_cloud>                                    #
#     $ ./force_cleanup --file kb_20150807_183001_svr.log                     #
#     $ ./force_cleanup --file kb_20150807_183001_cnt.log                     #
#                                                                             #
# Note: If running under single-tenant or tenant/user reusing mode, you have  #
#       to cleanup the server resources first, then client resources.         #
#                                                                             #
# When there is no resource list provided, the script will simply grep the    #
# resource name with "KB" and delete them. If running on a production         #
# network, please double and triple check all resources names are *NOT*       #
# containing "KB", otherwise they will be deleted by the script.              #
#                                                                             #
###############################################################################

# ======================================================
#                        WARNING
# ======================================================
# IMPORTANT FOR RUNNING KLOUDBUSTER ON PRODUCTION CLOUDS
#
# DOUBLE CHECK THE NAMES OF ALL RESOURCES THAT DO NOT
# BELONG TO KLOUDBUSTER ARE *NOT* CONTAINING "KB".
# ======================================================

echo "If this is not your tenant, or you are running as the admin user, ctrl-c now and do not run this script."
echo $OS_TENANT_NAME

function prompt_to_run() {
    echo "Warning: You didn't specify a resource list file as the input,"\
         "or the input file is invalid. The script will delete ALL"\
         "the resources in the tenant. "
    read -p "Are you sure? (Y/N) " answer
    if [ "$answer" != "Y" ] && [ "$answer" != "y" ]; then
        exit 0
    fi
}

if [ "$OS_TENANT_NAME" != "admin" ]; then
    prompt_to_run;
    
    INSTANCE_LIST=`nova list --fields ID|grep -v ID | awk '{print $2}'`
#    SEC_GROUP_LIST=`neutron security-group-list | cut -d'|' -f2`
#    FLAVOR_LIST=`nova flavor-list | cut -d'|' -f3`
    ROUTER_LIST=`neutron router-list |cut -d'|' -f2| grep -v external_gateway_info|grep -v +|grep -v id`
    NETWORK_LIST=`neutron net-list |grep -v floating|cut -d'|' -f2| grep -v external_gateway_info|grep -v +|grep -v id`
#    TENANT_LIST=`keystone tenant-list | cut -d'|' -f2`
#    USER_LIST=`keystone user-list | cut -d'|' -f2`
    FLOATINGIP_LIST=""
    CINDER_SNAPSHOT_LIST=`openstack snapshot list -c ID|grep -v [ID,+]|awk '{print $2}'`
    CINDER_VOLUME_LIST=`openstack volume list -c ID|grep -v [ID,+]|awk '{print $2}'`
#    CONTAINER_LIST=`swift list`
    LB_VIP_LIST=`neutron lb-vip-list |cut -d'|' -f2| grep -v external_gateway_info|grep -v +|grep -v id`
    LB_LIST=`neutron lb-pool-list |cut -d'|' -f2| grep -v external_gateway_info|grep -v +|grep -v id`
    FW_LIST=`neutron firewall-list |cut -d'|' -f2| grep -v external_gateway_info|grep -v +|grep -v id`
    STACK_LIST=`heat list |cut -d'|' -f2|grep -v +|grep -v id`
    
else
    echo "You are running against admin tenant, can't do that."
fi

echo $INSTANCE_LIST
for line in $INSTANCE_LIST; do
    nova delete $line
done

#for line in $FLAVOR_LIST; do
#    nova flavor-delete $line
#done;

#for line in $SEC_GROUP_LIST; do
#    neutron security-group-delete $line &
#done;

if [ "$FLOATINGIP_LIST" == "" ]; then
    echo -e "`neutron floatingip-list | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'`" | while read line; do
        fid=`echo $line | cut -d'|' -f2 | xargs`
        portid=`echo $line | cut -d'|' -f5 | xargs`
        if [ "$fid" != "" ] && [ "$portid" = "" ]; then
            neutron floatingip-delete $fid
        fi
    done;
else
    for line in $FLOATINGIP_LIST; do
        neutron floatingip-delete $line &
    done;
fi

for line in $LB_VIP_LIST; do
    neutron lb-vip-delete $line &
done;


for line in $FW_LIST; do
    neutron firewall-delete $line &
done;


for line in $ROUTER_LIST; do
    neutron router-gateway-clear $line
    for line2 in `neutron router-port-list $line | grep subnet_id | cut -d'"' -f4`; do
        neutron router-interface-delete $line $line2
    done
    neutron router-delete $line
done

for line in $NETWORK_LIST; do
    neutron net-delete $line
done

#for line in $TENANT_LIST; do
#    keystone tenant-delete $line
#done

#for line in $USER_LIST; do
#    keystone user-delete $line
#done

for line in $CINDER_SNAPSHOT_LIST; do
    cinder snapshot-delete $line
done

for line in $CINDER_VOLUME_LIST; do
    cinder delete $line
done

#for line in $CONTAINER_LIST; do
#    swift delete $line --all
#done
swift delete --all

for line in $LB_LIST; do
    neutron lb-pool-delete $line &
done;

for line in $STACK_LIST; do
    heat delete $line &
done;

