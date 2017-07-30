#!/bin/bash

#SET ENV
YUM_SERVER='yum.suixingpay.local'
PACKAGE_URL="http://${YUM_SERVER}/tools"

#SET TEMP PATH
TEMP_PATH='/usr/local/src'

#SET TEMP DIR
INSTALL_DIR="install_$$"
INSTALL_PATH="${TEMP_PATH}/${INSTALL_DIR}"

#SET PACKAGE
YUM_PACKAGE='php-gd rrdtool-perl rrdtool'
#APT_PACKAGE='build-essential'

#SET EXIT STATUS AND COMMAND
trap "exit 1"           HUP INT PIPE QUIT TERM
trap "rm -rf ${INSTALL_PATH}"  EXIT

download_func () {
local func_shell='func4install.sh'
local func_url="http://${YUM_SERVER}/shell/${func_shell}"
local tmp_file="/tmp/${func_shell}"

wget -q ${func_url} -O ${tmp_file} && source ${tmp_file} ||\
eval "echo Can not access ${func_url}! 1>&2;exit 1"
rm -f ${tmp_file}
}

main () { 
#Check nagios user
id nagios >/dev/null 2>&1 ||\
eval "echo nagios user not exist!;exit 1"

#Check nagios path
test -d /usr/local/nagios/ ||\
eval "echo nagios not installed!;exit 1"

#DOWNLOAD FUNC FOR INSTALL
download_func

#CHECK SYSTEM AND CREATE TEMP DIR
check_system
set_install_cmd

#Install pnp4nagios-0.6.22.tar.gz
PACKAGE='pnp4nagios-0.6.22.tar.gz'

#Create_tmp_dir
create_tmp_dir
download_and_check
run_cmds './configure --with-nagios-user=nagios --with-nagios-group-nagios --with-rrdtool=/usr/bin/rrdtool --with-perfdata-dir=/usr/local/nagios/share/perfdata/
' 'make all' 'make install' 'make install-webconf' 'make install-config' 'make install-init' 'make fullinstall'

#Modify /usr/local/nagios/etc/nagios.cfg
nagios_conf='/usr/local/nagios/etc/nagios.cfg'
test -f ${nagios_conf} ||\
eval "echo ${nagios_conf} not exist!;exit 1"

sed -r -i.backup.`date -d now +"%F".$$` 's/^(cfg_file=.*localhost.cfg)$/#\1/' ${nagios_conf}

#ADD TO rc.local
grep 'AUTO RUN FOR PNP4NAGIOS' /etc/rc.local >/dev/null 2>&1 ||\
echo '#AUTO RUN FOR PNP4NAGIOS
/usr/local/pnp4nagios/bin/npcd -d -f /usr/local/pnp4nagios/etc/npcd.cfg' >> /etc/rc.local

#MODIFY nagios.cfg
grep 'Bulk Mode with NPCD:' ${nagios_conf} >/dev/null 2>&1 ||\
cat << EOF >> ${nagios_conf}

#Bulk Mode with NPCD:
process_performance_data=1

#
# service performance data
#
service_perfdata_file=/usr/local/pnp4nagios/var/service-perfdata
service_perfdata_file_template=DATATYPE::SERVICEPERFDATA\tTIMET::\$TIMET\$\tHOSTNAME::\$HOSTNAME\$\tSERVICEDESC::\$SERVICEDESC\$\tSERVICEPERFDATA::\$SERVICEPERFDATA\$\tSERVICECHECKCOMMAND::\$SERVICECHECKCOMMAND\$\tHOSTSTATE::\$HOSTSTATE\$\tHOSTSTATETYPE::\$HOSTSTATETYPE\$\tSERVICESTATE::\$SERVICESTATE\$\tSERVICESTATETYPE::\$SERVICESTATETYPE\$
service_perfdata_file_mode=a
service_perfdata_file_processing_interval=15
service_perfdata_file_processing_command=process-service-perfdata-file

#
# host performance data starting with Nagios 3.0
# 
host_perfdata_file=/usr/local/pnp4nagios/var/host-perfdata
host_perfdata_file_template=DATATYPE::HOSTPERFDATA\tTIMET::\$TIMET\$\tHOSTNAME::\$HOSTNAME\$\tHOSTPERFDATA::\$HOSTPERFDATA\$\tHOSTCHECKCOMMAND::\$HOSTCHECKCOMMAND\$\tHOSTSTATE::\$HOSTSTATE\$\tHOSTSTATETYPE::\$HOSTSTATETYPE\$
host_perfdata_file_mode=a
host_perfdata_file_processing_interval=15
host_perfdata_file_processing_command=process-host-perfdata-file
EOF

#ADD COMMAND
custom_path='/usr/local/nagios/etc/others'
test -d ${custom_path} &&\
cat << EOF > ${custom_path}/command.cfg
define command{
    command_name    check_nrpe
    command_line    \$USER1\$/check_nrpe -H \$HOSTADDRESS\$ -c \$ARG1\$ -t 60
}

define command{
        command_name    check_mysql
        command_line    \$USER1\$/check_mysql -H \$HOSTADDRESS\$ \$ARG1\$
        }

# 'check_nt' command definition
#define command{
#    command_name    check_nt
#    command_line    \$USER1\$/check_nt -H \$HOSTADDRESS\$ -s nagios -p 12489 -v \$ARG1\$ \$ARG2\$
#    }
EOF

cat << EOF > ${custom_path}/pnp4nagios.cfg
#add pnp0.6 host service
define host {
   name       hosts-pnp
   action_url /pnp4nagios/index.php/graph?host=\$HOSTNAME\$&srv=_HOST_
   register   0
}

define service {
   name       services-pnp
   action_url /pnp4nagios/index.php/graph?host=\$HOSTNAME\$&srv=\$SERVICEDESC\$
   register   0
}
 
define command{
       command_name    process-service-perfdata-file
       command_line    /bin/mv /usr/local/pnp4nagios/var/service-perfdata /usr/local/pnp4nagios/var/spool/service-perfdata.\$TIMET\$
}

define command{
       command_name    process-host-perfdata-file
       command_line    /bin/mv /usr/local/pnp4nagios/var/host-perfdata /usr/local/pnp4nagios/var/spool/host-perfdata.\$TIMET\$
}
EOF

#ADD Server 
LANG=en_US.UTF-8
server_path="/usr/local/nagios/etc/servers"
test -d ${server_path} &&\
cat << EOF > ${server_path}/localhost.cfg
define host{
        use                     linux-server,hosts-pnp
        host_name               NAGIOS-SERVER
        alias                   NAGIOS服务器
        address                 127.0.0.1
        _owner                  系统组
#        contact_groups          sysadm
#        hostgroups              mon-servers
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     CPU负载
        check_command           check_nrpe!check_load
        _owner                  系统组
#        contact_groups          sysadm
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     本地登录用户数
        check_command           check_nrpe!check_users
        _owner                  系统组
#        contact_groups          sysadm
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     根分区磁盘使用率
        check_command           check_nrpe!check_disk_root
        _owner                  系统组
#        contact_groups          sysadm
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     系统进程数
        check_command           check_nrpe!check_total_procs
        _owner                  系统组
#        contact_groups          sysadm
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     僵尸进程数
        check_command           check_nrpe!check_zombie_procs
        _owner                  系统组
#        contact_groups          sysadm
}
define service {
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     CPU占用率
        check_command           check_nrpe!check_cpu_utilization
        max_check_attempts      10
        retry_interval          5
        register                0
        _owner                  系统组
#        contact_groups          sysadm
}
define service{
        use                     generic-service
        host_name               NAGIOS-SERVER
        service_description     DenyHosts服务
        check_command           check_nrpe!check_denyhosts
        max_check_attempts      1
        check_interval          1
        register                0
        notification_options    w,u,c
        _owner                  系统组
#        contact_groups          sysadm
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     网络链接数
        _owner                  系统组
        check_command           check_nrpe!check_tcp_stat
        max_check_attempts      7
        check_interval          3
        retry_check_interval    2
        notification_options    w,u,c,r
#        contact_groups          sysadm
        register                0
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     检测时钟服务器
        check_command           check_nrpe!check_ntp_time
        max_check_attempts      3
        check_interval          3
        retry_check_interval    2
        notification_options    w,u,c,r
        _owner                  系统组
#        contact_groups          sysadm
        register                0
}
define service{
        use                     generic-service,services-pnp
        host_name               NAGIOS-SERVER
        service_description     DNS服务
        check_command           check_nrpe!check_dns
        max_check_attempts      3
        check_interval          3
        retry_check_interval    2
        notification_options    w,u,c,r
        _owner                  系统组
#        contact_groups          sysadm
        register                0
}
define service {
        host_name                       NAGIOS-SERVER
        service_description             swap交换分区使用率
        use                             generic-service,services-pnp
        check_command                   check_nrpe!check_swap
#        contact_groups                  sysadm
        _owner                  系统组
        register                        1
}
define service {
        host_name                       NAGIOS-SERVER
        service_description             内存使用率
        use                             generic-service,services-pnp
        check_command                   check_nrpe!check_mem
        check_interval                  3
                retry_check_interval            3
        max_check_attempts              5
        notification_options            w,u,c,r
#        contact_groups                  sysadm
        _owner                  系统组
        register                        0
}
define service {
        host_name                       NAGIOS-SERVER
        service_description             网卡流量
        use                             generic-service,services-pnp
        check_command                   check_nrpe!check_net_traffic
                check_interval                  3
        retry_check_interval            3
        max_check_attempts              10
#        contact_groups                  sysadm
        _owner                          系统组
        register                        0
}
EOF

#check_commands_path
check_commands_path='/usr/local/pnp4nagios/etc/check_commands'
if [ -d "${check_commands_path}" ];then
	ls ${check_commands_path}/*-sample|sed -r 's/^(.*)-sample/mv & \1/'|sh
	cd ${check_commands_path}
	test -f check_nrpe.cfg && cp check_nrpe.cfg check_nt.cfg && cd
fi

npcd_cmd='/usr/local/pnp4nagios/bin/npcd'
npcd_conf='/usr/local/pnp4nagios/etc/npcd.cfg'

test -f ${npcd_cmd} && eval ${npcd_cmd} -d -f ${npcd_conf} ||\
echo "${npcd_cmd} not found!;exit 1"

#Remove pnp4nagios php
pnp4nagios_php='/usr/local/pnp4nagios/share/install.php'
test -f ${pnp4nagios_php} && mv ${pnp4nagios_php} ${pnp4nagios_php}.backup.`date -d now +"%F".$$`

nrpe_conf='/usr/local/nagios/etc/nrpe.cfg'

if [ -f "${nrpe_conf}" ];then
grep 'check_swap' ${nrpe_conf} ||\
echo 'command[check_swap]=/usr/local/nagios/libexec/check_swap -w 20% -c 10%' >> ${nrpe_conf}

grep 'check_disk_root' ${nrpe_conf} ||\
echo 'command[check_disk_root]=/usr/local/nagios/libexec/check_disk -w 20% -c 10% -p /' >> ${nrpe_conf}
fi

/etc/init.d/nagios restart
/etc/init.d/httpd restart

#EXIT AND CLEAR TEMP DIR
exit_and_clear

}

main
