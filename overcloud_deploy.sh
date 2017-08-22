#!/bin/bash

error ()
{
  echo $* 1>&2
  exit 1
}

source /home/stack/stackrc || error "can't load stackrc"

openstack overcloud deploy \
--templates \
-e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
-e $PWD/deploy.yaml -r $PWD/roles_data.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/neutron-sriov.yaml \
-e $PWD/network-environment.yaml \
--ntp-server clock.redhat.com \
--libvirt-type kvm

echo "set up symbolic link /home/stack/overcloudrc"
rm -rf /home/stack/overcloudrc 2>/dev/null
ln -s -T $PWD/overcloudrc /home/stack/overcloudrc

echo "modify /etc/hosts entry"
sudo sed -i -r '/compute/d' /etc/hosts
sudo sed -i -r '/controller/d' /etc/hosts
nova list | sed -r -n 's/.*(compute-[0-9]+).*ctlplane=([0-9.]+).*/\2 \1/p' | sudo tee --append /etc/hosts >/dev/null
nova list | sed -r -n 's/.*(controller-[0-9]+).*ctlplane=([0-9.]+).*/\2 \1/p' | sudo tee --append /etc/hosts >/dev/null

echo "build nodes inventory file"
echo "[computes]" > nodes
nova list | sed -n -r 's/.*compute.*ctlplane=([.0-9]+).*/\1/ p' >> nodes
echo "[controllers]" >> nodes
nova list | sed -n -r 's/.*control.*ctlplane=([.0-9]+).*/\1/ p' >> nodes
cat <<EOF >>nodes
[all:vars]
ansible_connection=ssh
ansible_user=heat-admin
ansible_become=true
EOF

# update authorized ssh key on nodes
echo "update authorized ssh key on nodes"
ANSIBLE_HOST_KEY_CHECKING=False UserKnownHostsFile=/dev/null ansible all -i nodes -m shell -a "> /root/.ssh/authorized_keys; echo $(sudo cat /home/stack/.ssh/id_rsa.pub) >> /root/.ssh/authorized_keys; echo $(sudo cat /root/.ssh/id_rsa.pub) >> /root/.ssh/authorized_keys"
ansible all -i nodes -m lineinfile -a "name=/etc/ssh/sshd_config regexp='^UseDNS' line='UseDNS no'"
ansible all -i nodes -m service -a "name=sshd state=restarted"
