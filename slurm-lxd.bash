#
#                             ""#
#                       mmm     #    m   m   m mm  mmmmm
#                      #   "    #    #   #   #"  " # # #
#                       """m    #    #   #   #     # # #
#                      "mmm"    "mm  "mm"#   #     # # #
#
#
#                                        #  #
#                mmm    mmm   m mm    mmm#  #mmm    mmm   m   m
#               #   "  "   #  #"  #  #" "#  #" "#  #" "#   #m#
#                """m  m"""#  #   #  #   #  #   #  #   #   m#m
#               "mmm"  "mm"#  #   #  "#m##  ##m#"  "#m#"  m" "m
#

#
# This script sets up a slurm cluster with 1 controller and 2 nodes
#
# - It uses lxd to create the containers and the lxd bridge network to connect them
# - It uses nfs to share the /work, /etc/slurm and /etc/munge directories between the nodes
# - The script is meant to be run on the host machine
# - The host machine should have lxd installed and configured
# - The host machine should have the lxd bridge network configured
#

#
# you can configure lxd and the lxd bridge network like this:
#
# sudo lxd init
#
# if you've never used lxd before you can just press enter to accept the defaults
#
# to give the lxd vms internet access for whatever reason on the cw vdis you need
# some additional work (it's not normally needed on a vanilla ubuntu install):
#
# the IP below should be replaced with the network of the lxd bridge network, which
# you can find by running `ip a` and looking for the lxdbr0 interface
#                                              |
#                                        vvvvvvvvvvvvvv
# sudo iptables -t nat -A POSTROUTING -s 10.131.89.0/24 ! -o lxdbr0 -j MASQUERADE
# sudo iptables -A FORWARD -i lxdbr0 -o enp5s0 -j ACCEPT
# sudo iptables -A FORWARD -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# sudo sysctl -w net.ipv4.ip_forward=1
#
# These settings are wiped between reboots
#

# helper function for running stuff on multiple nodes
run() {
    nodes=("$@")
    command="${nodes[-1]}"
    unset 'nodes[-1]'
    for node in "${nodes[@]}"; do
        node_command="${command//\{node\}/$node}"
        echo "Running command on $node..."
        eval "$node_command"
    done
}

#
#        ""#    ""#                             #
#  mmm     #      #           m mm    mmm    mmm#   mmm    mmm
# "   #    #      #           #"  #  #" "#  #" "#  #"  #  #   "
# m"""#    #      #           #   #  #   #  #   #  #""""   """m
# "mm"#    "mm    "mm         #   #  "#m#"  "#m##  "#mm"  "mmm"
#

run node1 node2 node3 "lxc launch --vm ubuntu:24.04 {node}"
sleep 60
lxc list
run node1 node2 node3 "lxc exec {node} apt update"
run node1 node2 node3 "lxc exec {node} apt -- -y upgrade"
lxc list

#
#                   #         mmm
# m mm    mmm    mmm#   mmm     #
# #"  #  #" "#  #" "#  #"  #    #
# #   #  #   #  #   #  #""""    #
# #   #  "#m#"  "#m##  "#mm"  mm#mm
#

run node1 "lxc exec {node} apt -- -y install munge"
run node1 "lxc exec {node} apt -- -y install slurm-wlm"
run node1 "lxc exec {node} apt -- -y install slurmdbd nfs-server mysql-server"
run node1 "lxc exec {node} mkdir /work"
run node1 "lxc exec {node} -- sh -c 'cat << EOF > /etc/exports

/work    *(rw,sync,no_subtree_check)
/etc/slurm    *(rw,sync,no_subtree_check)
/etc/munge    *(rw,sync,no_subtree_check)

EOF'"
run node1 "lxc exec {node} -- exportfs -a"

run node1 "lxc exec {node} -- sh -c 'cat << EOF > /etc/slurm/slurm.conf

ClusterName=HEY
ControlMachine=node1
AuthType=auth/munge
SlurmUser=slurm
SlurmdPort=6818
SlurmctldPort=6817
SlurmctldLogFile=/var/log/slurmctld.log
SlurmdLogFile=/var/log/slurmd.log
NodeName=node[2-3] NodeAddr=node[2-3] CPUs=1 State=UNKNOWN
PartitionName=normal Nodes=node[2-3] Default=YES MaxTime=INFINITE State=UP
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=node1

EOF'"

run node1 "lxc exec {node} -- sh -c 'cat << EOF > /etc/slurm/slurmdbd.conf

SlurmUser=slurm
DbdHost=localhost
StorageLoc=slurm_acct_db
StorageType=accounting_storage/mysql
StorageUser=slurm
StoragePass=your_password
AuthType=auth/munge
LogFile=/var/log/slurmdbd.log
PidFile=/var/run/slurmdbd.pid

EOF'"

run node1 "lxc exec {node} -- chmod 600 /etc/slurm/slurmdbd.conf"

run node1 "lxc exec {node} -- sh -c 'mysql -u root <<EOF

CREATE USER slurm@localhost IDENTIFIED BY \"your_password\";
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO slurm@localhost;
FLUSH PRIVILEGES;

EOF'"

run node1 "lxc exec {node} -- chown slurm:slurm -R /etc/slurm"
run node1 "lxc exec {node} -- chmod 600 -R /etc/slurm/slurmdbd.conf"
run node1 "lxc exec {node} -- chown slurm:slurm -R /etc/slurm/slurmdbd.conf"
run node1 "lxc exec {node} -- chown slurm:slurm -R /var/spool"

run node1 "lxc exec {node} -- systemctl daemon-reload"
run node1 "lxc exec {node} -- systemctl restart slurmdbd"

#
#                   #          mmmm          mmmm
# m mm    mmm    mmm#   mmm   "   "#        "   "#
# #"  #  #" "#  #" "#  #"  #      m"          mmm"
# #   #  #   #  #   #  #""""    m"              "#
# #   #  "#m#"  "#m##  "#mm"  m#mmmm   #    "mmm#"
#                                     "
#

run node2 node3 "lxc exec {node} -- apt -y install munge"
run node2 node3 "lxc exec {node} -- apt -y install slurmd"
run node2 node3 "lxc exec {node} -- apt -y install nfs-client"

NODE1_IP=$(lxc list | grep node1 | cut -d '|' -f 4 | cut -d " " -f 2)
export NODE1_IP
run node2 node3 "lxc exec {node} -- sh -c 'cat << EOF >> /etc/fstab

$NODE1_IP:/work  /work  nfs  rw,sync  0  0
$NODE1_IP:/etc/slurm  /etc/slurm  nfs  rw,sync  0  0
$NODE1_IP:/etc/munge  /etc/munge  nfs  rw,sync  0  0

EOF'"

run node2 node3 "lxc exec {node} -- mkdir /work"
run node2 node3 "lxc exec {node} -- systemctl daemon-reload"
run node2 node3 "lxc exec {node} -- mount -a"

lxc file pull node1/etc/passwd .
lxc file pull node1/etc/group .
run node2 node3 "lxc file push passwd {node}/etc/passwd"
run node2 node3 "lxc file push group {node}/etc/group"

run node2 node3 "lxc exec {node} -- chown munge:munge -R /var/log/munge /var/lib/munge"

run node2 node3 "lxc exec {node} -- systemctl restart munge slurmd"

#
#                   #         mmm
# m mm    mmm    mmm#   mmm     #
# #"  #  #" "#  #" "#  #"  #    #
# #   #  #   #  #   #  #""""    #
# #   #  "#m#"  "#m##  "#mm"  mm#mm
#

run node1 "lxc exec {node} -- systemctl restart slurmctld"
sleep 5

lxc exec node1 -- srun -N 2 hostname

# You can shell into the nodes like this:
# lxc exec node1 -- bash
