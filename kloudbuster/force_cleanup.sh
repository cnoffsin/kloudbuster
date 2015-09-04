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
         "or the input file is invalid. The script will delete all"\
         "resources of the cloud whose names contain \"KB\". "
    read -p "Are you sure? (Y/N) " answer
    if [ "$answer" != "Y" ] && [ "$answer" != "y" ]; then
        exit 0
    fi
}

if [ "$1" == "--file" ] && [ -f "$2" ] && [OS_TENANT_NAME=BSS_Validations]; then
    INSTANCE_LIST=`grep "instances" $2 | cut -d'|' -f3`
    SEC_GROUP_LIST=`grep "sec_groups" $2 | cut -d'|' -f3`
    FLAVOR_LIST=`grep "flavors" $2 | cut -d'|' -f3`
    ROUTER_LIST=`grep "routers" $2 | cut -d'|' -f3`
    NETWORK_LIST=`grep "networks" $2 | cut -d'|' -f3`
    TENANT_LIST=`grep "tenants" $2 | cut -d'|' -f3`
    USER_LIST=`grep "users" $2 | cut -d'|' -f3`
    FLOATINGIP_LIST=`grep "floating_ips" $2 | cut -d'|' -f3`
else
    prompt_to_run;
    INSTANCE_LIST=`nova list --fields ID|grep -v ID | awk '{print $2}'`
#    SEC_GROUP_LIST=`neutron security-group-list | cut -d'|' -f2`
#    FLAVOR_LIST=`nova flavor-list | cut -d'|' -f3`
    ROUTER_LIST=`neutron router-list | cut -d'|' -f2`
    NETWORK_LIST=`neutron net-list | cut -d'|' -f2`
#    TENANT_LIST=`keystone tenant-list | cut -d'|' -f2`
#    USER_LIST=`keystone user-list | cut -d'|' -f2`
    FLOATINGIP_LIST=""
    CINDER_SNAPSHOT_LIST=`openstack snapshot list -c ID|grep -v [ID,+]|awk '{print $2}'`
    CINDER_VOLUME_LIST=`openstack volume list -c ID|grep -v [ID,+]|awk '{print $2}'`
    CONTAINER_LIST=`swift list`
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

for line in $CONTAINER_LIST; do
    swift delete $line --all
done
