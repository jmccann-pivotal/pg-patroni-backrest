export ANSIBLE_CFG := ./ansible.cfg
all:
	echo "ping, check-syntax,  deploy-ha"

ping:
	ansible all -m ping -i hosts.cfg

check-syntax:
	ansible-playbook -i hosts.cfg  pg-ha-playbook.yml --syntax-check

deploy-ha:
	ansible-playbook -i hosts.cfg  pg-ha-playbook.yml


