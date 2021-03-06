#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ -z ${SUDO_USER+x} ]]; then
   echo "Stop. Please run this scripts with sudo"
   exit 1
fi

if [ -f /home/$SUDO_USER/rhosp-environment.sh ]; then
   source /home/$SUDO_USER/rhosp-environment.sh
else
   echo "File /home/$SUDO_USER/rhosp-environment.sh not found"
   exit
fi

cd /home/$SUDO_USER

openstack overcloud container image prepare \
  --namespace registry.access.redhat.com/rhosp13  --prefix=openstack- --tag-from-label {version}-{release} \
  --push-destination ${prov_ip}:8787 \
  --output-env-file ./docker_registry.yaml \
  --output-images-file ./overcloud_containers.yaml

echo openstack overcloud container image upload --config-file ./overcloud_containers.yaml
openstack overcloud container image upload --config-file ./overcloud_containers.yaml

./contrail-tripleo-heat-templates/tools/contrail/import_contrail_container.sh -f ./contrail_containers.yaml -r docker.io/tungstenfabric -t latest

sed -i ./contrail_containers.yaml -e "s/192.168.24.1/${prov_ip}/"

cat ./contrail_containers.yaml

echo openstack overcloud container image upload --config-file ./contrail_containers.yaml
openstack overcloud container image upload --config-file ./contrail_containers.yaml

echo Checking catalog in docker registry
curl -X GET http://${prov_ip}:8787/v2/_catalog


