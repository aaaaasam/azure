#!/usr/bin/env bash

terraform_template="template"

function install_dependency_package {
    sudo apt update
    sudo apt install jq unzip curl ansible sshpass -y
}

function check_terraform_and_install {
    terraform -version ||   (   curl -o terraform_0.15.1_linux_amd64.zip https://releases.hashicorp.com/terraform/0.15.1/terraform_0.15.1_linux_amd64.zip; \
                                unzip terraform_0.15.1_linux_amd64.zip; \
                                sudo mv  terraform /usr/bin/ ; \
                                rm  terraform_0.15.1_linux_amd64.zip\
                            )
}

function buildansiblehostfile {
    read -p 'Enter your vm username -> ' username
    read -p 'Enter your vm password -> ' password
}

function disable_ansible_host_check {
    sudo sed -i "s/#host_key_checking = False/host_key_checking = False/" /etc/ansible/ansible.cfg
}

function create_vm_on_azure {
    cat ${terraform_template} | sed "s/<adminuser>/${username}/"  | sed "s/<adminpassword>/${password}/" > main.tf
    terraform init || exit 1
    terraform apply -auto-approve || exit 1
}

function generate_ansible_host_file {
    rm host.txt
    rm /tmp/host.txt
    for ip in `jq .outputs.pip_address.value terraform.tfstate  | grep '"' | awk -F'"' '{print $2}'`; do
        echo "${ip} ansible_port=22 ansible_user=${username} ansible_ssh_pass=${password} ansible_become=true ansible_become_exe=sudo" >> /tmp/host.txt
    done

    cat /tmp/host.txt | sed '1 a [slave]' | sed '1 i [master]' > host.txt

    ansible -i host.txt all -m ping || (echo "Can not access azure vm, Please check the configuration." ; exit 1)
    ansible -i host.txt master -m ping || (echo "Can not access azure vm, Please check the configuration." ; exit 1)
    ansible -i host.txt slave -m ping || (echo "Can not access azure vm, Please check the configuration." ; exit 1)
}

function install_k8s_cluster {
    ansible -i host.txt all -m script -a "script_dir/init_cluster_env.sh"
    # Initialization master node.
    ansible -i host.txt master -m shell -a "kubeadm init --pod-network-cidr=192.168.0.0/16"
    # Run join command in slave node. 
    ansible -i host.txt slave -m shell -a "`ansible -i host.txt  master -m shell -a 'kubeadm token create --print-join-command' | grep kubeadm`"

    # run flanel pulgin on k8s.
    ansible -i host.txt master -m shell -a "mkdir -p $HOME/.kube;cp -i /etc/kubernetes/admin.conf $HOME/.kube/config"
    ansible -i host.txt master -m shell -a "mkdir -p /root/.kube;cp -i /etc/kubernetes/admin.conf /root/.kube/config"
    ansible -i host.txt master -m shell -a "curl -sL https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml | sed 's/10.244.0.0/192.168.0.0/' > kube_flanel.yml; kubectl apply -f kube_flanel.yml"
}

function main {
    install_dependency_package
    check_terraform_and_install
    buildansiblehostfile
    create_vm_on_azure
    generate_ansible_host_file
    install_k8s_cluster
}

main
