#!/bin/bash

terraform apply -auto-approve

echo "[hosts]" > hosts
terraform output | grep "#inv" | awk '{print $3}' | cut -d "=" -f 2 >> hosts

sleep 30

ansible-playbook deploy.yml
