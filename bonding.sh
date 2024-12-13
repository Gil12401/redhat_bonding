#!/bin/bash

# file_to_map.sh / bonding.sh / create_ifcfg.sh / ifcfg_sample.tar.gz

# 환경 변수 Back up 
PRE_IFS=$IFS
# PRE_HISTFILE=$HISTFILE
# PRE_HISTCONTROL=$HISTCONTROL

# a. ip a 명령어로 Bonding 구성이 가능한 Ethernet Device 이름 확인 
# Loopback / Master / Slave 제외한 NIC 이름 나열 ( ex. eth0, eth1, ens18, ens19 ... )

# 주의 !! IFS="\n" :  문자 'n'이 구분자로 지정이 됨. 
IFS=$'\n' 

nic_list=($(ip addr show | grep "<[^>]*>" | grep -v -E "LOOPBACK|MASTER|SLAVE"))
names=()

roles=("primary" "secondary")
declare -A bonding_members # ex ) bonding_members[eth2]="primary" / bonding_members[eth3]="secondary" / bonding_members[eth4]="secondary" ... 

# IFS Back up 
IFS=$PRE_IFS

for row in "${nic_list[@]}"; do
    # cut (delimiter : " ") 이름을 리스트에 추가.  
    nic_name=$(echo ${row} | cut -d " " -f 2 | tr -d ":")
    names+=(${nic_name})
done

# ( 0 : primary / 1 : secondary )
roles_index=0 

while : 
    do

    nic_name=${roles[${roles_index}]}

    # 탈출조건 : Primary, Secondary 모두 선택 -> roles_index >= ${#names[@]} 
    if [[ ${roles_index} -ge ${#roles[@]} ]]; then
        break
    fi

    echo "----------------------------------------------------"
    echo "    Select the ${nic_name} NIC for Bonding Slave    "
    echo "----------------------------------------------------"

    for((i=0; i<${#names[@]}; i++)); do
        role=${bonding_members[${names[${i}]}]}
        if [[ -z ${role} ]]; then
            echo "${i}. ${names[${i}]}"
        else
            echo "${i}. ${names[${i}]} ( ${role} )"
        fi
    done

    read number

    # number이 map의 key range에 속해있는지 검사 0 < number <= ${#names[@]}
    if [ ${number} -lt 0 -o ${number} -ge ${#names[@]} ]; then
        echo " index out of range. "
        continue
    fi

    # 이미 선택된 index 다시 선택했는지 검사 
    # 해당 bondig_members에 ( key : nic name ) role이 존재한다면, 이미 선택된 index 
    role=${bonding_members[${names[${number}]}]}
    if [[ -n ${role} ]]; then
        echo " already selected index. " 
        continue
    fi

    key=${names[${number}]}
    value=${roles[${roles_index}]}

    # bonding members 등록 
    # value : primary ( 0 ) / secondary ( 1 )
    bonding_members[${key}]=${value}

    # roles_index 증가 
    roles_index=$((1+${roles_index}))
done

# b. 현재 Linux OS 버전 확인 : '/etc/*release'
# 결과를 key - value 연관 배열에 담아서 출력(반환)
eval "$(bash /redhat_bonding/file_to_map.sh '/etc/*release')" 

version_id=$(echo "${map["VERSION_ID"]}")

# 버전을 소수점 제거(내림) 하고 정수로 표현 ( 리눅스에서 정수 이외에는 숫자가 아닌 문자열로 인식됨 )
version_id=$(printf "%.0f" "${version_id}")
echo "version_id : ${version_id}"

if [ ${version_id} -le 7 ]; then

    # echo "this version is -le 7"
    # 7버전 이하 -> ifcfg 설정 파일 

    # 1. NetworkManager 중지 
    systemctl stop NetworkManager

    # bonding_members ( Assosiative Array ) to File  
    # 파일 경로 및 이름 : /bonding_members
    touch "/bonding_members"
    chmod 777 "/bonding_members"

    cat /dev/null > $(find / -maxdepth 1 -name "bonding_members")

    for key in ${!bonding_members[@]}; do
        line="${key}=${bonding_members[${key}]}"
        echo ${line} >> $(find / -maxdepth 1 -name "bonding_members")
    done

    # 3. Bonding module 적재 ( Bonding 모듈 존재하지 않을 경우 )
    bonding=$(echo $(lsmod | grep 'bonding'))

    if [[ ${#bonding[@]} -eq "" ]]; then
        modprobe --first-time bonding
    fi

    # 4. 기존 설정 파일 백업 ( ifcfg 파일 )
    path_head="/etc/sysconfig/network-scripts/"
    ifcfg_bakdir="${path_head}/ifcfg_bak"

    # 백업 디렉터리가 존재하지 않으면 생성
    if [[ -d ${ifcfg_bakdir} ]]; then
        true
    else
        mkdir ${ifcfg_bakdir}
    fi
    
    # backup_files=()

    # bonding member에 해당하는 nic의 ifcfg파일 경로를 특정. 
    for path_tail in ${names[@]}; do
        file="${path_head}ifcfg-${path_tail}"

        # echo "file : ${file}"

        if [[ -f "${file}" ]]; then
           mv ${file} ${ifcfg_bakdir}
        fi

        # backup_files+=(${path})
    done

    # 5. Master Slave 설정 파일 작성 ( /redhat_bonding/create_ifcfg.sh )
    # $1 : /bonding_members 
    bash /redhat_bonding/create_ifcfg.sh /bonding_members

    # 6. network 재시작 
    systemctl restart network 

    # rm -rv /bonding_members
    echo " bonding config finished. " 

elif [ ${version_id} -gt 7 ]; then
    echo "key : ${!bonding_members[@]}"
    echo "value : ${bonding_members[@]}"

    # echo "this version is -gt 7"
    # 8버전 이상 -> NetworkManager nmcli

    # 0. Network Manager 실행 ( 실행 중이 아니라면 실행 ) 

    # NetworkManager가 실행 중인지 확인
    if systemctl is-active --quiet NetworkManager; then
        true
    else
        systemctl enable NetworkManager
        systemctl start NetworkManager
    fi

    # Master : bond0 
    # Slave : bond0-p1 bond0-p2

    # 1. Bond Master 생성 
    echo "write the name of Master"
    read master

    nmcli connection add type bond con-name ${master} ifname ${master} bond.options "mode=active-backup,miimon=100"

    # 2. Bond Slaves 생성 
    p_index=1
    for key in ${!bonding_members[@]}; do
        nmcli connection add type ethernet slave-type bond con-name ${master}-p${p_index} ifname ${key} master ${master}
        p_index=$((1+${p_index}))
    done

    # 3. Bond Master 설정 
    # Manual / Gateway IP / DNS Server IP / Primary 설정 
    
    echo " ====================================== "
    echo " Write the IP ADDRESS of bonding master "
    echo " ====================================== "
    read ip_addr

    echo " =========================================================== "
    echo " Write the PREFIX of bonding master ( ex. 16 -> 255.255.0.0 ) "
    echo " =========================================================== "
    read subnet_mask

    # echo " result : ${ip_addr}/${subnet_mask}"
    nmcli connection modify bond0 ipv4.addresses "${ip_addr}/${subnet_mask}"

    echo " ====================================== "
    echo " Write the GATEWAY IP of bonding master "
    echo " ====================================== "
    read gateway_ip

    nmcli connection modify bond0 ipv4.gateway "${gateway_ip}"

    nmcli connection modify ${master} ipv4.method.manual

    # active back-up mode : primary 설정 

    for slave in ${!bonding_members[@]}; do
        if [[ ${bonding_members[${slave}]} == *primary* ]]; then
            nmcli connection modify bond0 +bond.options "primary=${slave}"
        fi
    done
    
    # 1 : yes / 0 : no 
    nmcli connection modify bond0 connection.autoconnect-slaves 1

    nmcli connection up ${master}

    nmcli connection show 

fi
