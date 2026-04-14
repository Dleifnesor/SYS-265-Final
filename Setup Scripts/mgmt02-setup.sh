#!/bin/bash
# mgmt02-setup.sh
# Run this on mgmt02 as the deployer user.
# This is your master script — run everything else BEFORE this.
# Order: dfs01 -> dfs02 -> dc01 -> then this script.

set -e
ANSIBLES=~/ansibles

echo "============================================"
echo " STEP 1: Write inventory"
echo "============================================"

cat > $ANSIBLES/inventory.txt << 'EOF'
[controller]
mgmt02 ansible_connection=local

[dhcp]
dhcp01
dhcp02

[other]
util01
docker01

[ubuntu]
dhcp01
dhcp02
util01
docker01

[rocky]
# empty - needs a Rocky host for req 12

[file]
dfs01
dfs02

[windows]
dc01
dc02
mgmt01
w01
w02

[windows:vars]
ansible_shell_type=powershell
ansible_connection=ssh
ansible_user=grok\\administrator
ansible_ssh_common_args="-o StrictHostKeyChecking=no"

[ubuntu:vars]
ansible_user=deployer
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_become=yes
ansible_become_method=sudo

[file:vars]
ansible_shell_type=powershell
ansible_connection=ssh
ansible_user=grok\\administrator
ansible_ssh_common_args="-o StrictHostKeyChecking=no"
EOF

echo "Inventory written."

echo ""
echo "============================================"
echo " STEP 2: Test connectivity to all hosts"
echo "============================================"

echo "--- Ubuntu hosts ---"
ansible ubuntu -i $ANSIBLES/inventory.txt -m ping

echo ""
echo "--- Windows hosts ---"
ansible windows -i $ANSIBLES/inventory.txt -m win_ping

echo ""
echo "--- DFS hosts ---"
ansible file -i $ANSIBLES/inventory.txt -m win_ping

echo ""
echo "============================================"
echo " STEP 3: Run Ansible playbooks in order"
echo "============================================"

cd $ANSIBLES

echo ""
echo "[1/6] linux-admins AD group + sssd sudo on util01..."
ansible-playbook -i inventory.txt playbooks/02-linux-admins.yml

echo ""
echo "[2/6] Deploy Netdata to util01..."
ansible-playbook -i inventory.txt playbooks/01-deploy-netdata.yml

echo ""
echo "[3/6] Deploy Docker + Wiki.js to docker01..."
ansible-playbook -i inventory.txt playbooks/03-deploy-docker-wikijs.yml

echo ""
echo "[4/6] Install htop (apt package) on all Ubuntu hosts..."
ansible-playbook -i inventory.txt playbooks/07-install-apt-package.yml

echo ""
echo "[5/6] Add Linux local user srvadmin to util01..."
# NOTE: Edit playbooks/09-add-linux-user.yml first and replace
# the new_user_pubkey value with your actual public key:
#   cat ~/.ssh/id_rsa.pub
ansible-playbook -i inventory.txt playbooks/09-add-linux-user.yml

echo ""
echo "[6/6] Add Windows domain user via Ansible..."
ansible-playbook -i inventory.txt playbooks/10-add-windows-domain-user.yml

echo ""
echo "============================================"
echo " DONE"
echo "============================================"
echo "Verify results:"
echo "  Netdata:  http://172.16.1.15:19999"
echo "  Wiki.js:  http://172.16.1.5:3000"
echo ""
echo "Still TODO (needs Rocky host):"
echo "  ansible-playbook -i inventory.txt playbooks/08-install-yum-package.yml"
