#!/bin/bash

# 환경 변수 back up 
PRE_IFS=$IFS

# $1 : /bonding_members 

# bonding_members file을 map으로 가져오기 
eval "$(bash file_to_map.sh $1)" 

declare -A bonding_members

for key in ${!map[@]}; do 
    bonding_members[${key}]=${map[${key}]}    
done

# 현재 경로 내, 압축파일 가져오기 ( ./ )
# 편의상 절대경로부터 find

# 1. .tar.gz 로부터 설정 파일들 ( master , slave ) MAP에 할당 
# ifcfg_components_array[slave]=ifcfg-slave
# ifcfg_components_array[master]=ifcfg-master

declare -A ifcfg_components_array 
ifcfg_components=($(tar -xvzf $(find /redhat_bonding -maxdepth 1 -name "ifcfg_sample.tar.gz" 2> /dev/null)))

for element in ${ifcfg_components[@]}; do 
    type=$(echo ${element} | sed "s/"ifcfg-"/""/g")
    ifcfg_components_array[${type}]=${element}
done

# 2. 설정 파일 양식을 그대로 가져올 tmp file 생성 ( 임시 ) 
touch "/tmp_file"
chmod 777 /tmp_file

cat /dev/null > "/tmp_file"

# 3. Master
# DEVICE / IPADDR / NETMASK / GATEWAY / DNS1 / BONDING_OPTS ( primary 설정 )
ifcfg_master=${ifcfg_components_array["master"]}
master=""

ifcfg_slave=${ifcfg_components_array["slave"]}

if [[ -f ${ifcfg_master} ]]; then

    while IFS= read -r line; do   
        
        # echo " line : ${line} "

        # BONDING_OPTS : value가 공백을 포함하는 문자열임. 
        # BONDING_OPTS line에서 IFS를 임시로 '='로 변경. 
        key=$(echo ${line} | cut -d "=" -f 1)

        if [[ ${key} == *BONDING_OPTS* ]]; then

            # key 부분을 제외, value 부분을 추출. 
            # value='"mode=1 miimon=100 use_carrier=0 primary=eth0"'
            value=$(cat ${ifcfg_master} | tail -1)   
            value=$(echo "${value}" | sed "s/"BONDING_OPTS="/""/g")
            
            primary=""
            for nic in ${!bonding_members[@]}; do
                if [[ ${bonding_members[${nic}]} == *primary* ]]; then
                    primary=${nic}
                fi
            done

            # value에서 'primary='에 해당하는 값을 가져와서 수정
            old_primary=$(echo "${value}" | rev | cut -d " " -f 1 | rev | tr -d '"')
            old_primary=$(echo "${old_primary}" | rev | cut -d "=" -f 1 | rev)

            value=$(echo ${value} | sed "s/"${old_primary}"/"${primary}"/g" | tr -d "'")
            
            echo "${key}=${value}" >> $(find / -maxdepth 1 -name "tmp_file")

            continue
        fi

        value=$(echo ${line} | cut -d "=" -f 2)

        if [[ -z ${value} ]]; then
            echo "======================================"
            echo "Write the "${key}" of bonding master"
            echo "======================================"
        
            read value < /dev/tty # /dev/tty 즉, 키보드에서 입력받음을 명시. 
        fi

        # Bonding Master device name 
        # ifcfg-master / slave 설정 파일 양식 MASTER=master
        if [[ ${key} == *DEVICE* ]]; then
            master=${value}
        fi

        echo "${key}=${value}" >> $(find / -maxdepth 1 -name "tmp_file")

    done < "${ifcfg_master}"
fi

# 대상 파일을 만들어서 내용을 tmp_file로부터 복사.
ifcfg_path="/etc/sysconfig/network-scripts/"
cp /tmp_file "${ifcfg_path}ifcfg-${master}"

# 4. Slave

# bonding_members[eth99]="primary"
# bonding_members[eth100]="secondary"

# primary / secondary 구분 없이, 모든 bonding_members의 key에 대해 공통된 설정 양식 

for nic in ${!bonding_members[@]}; do
    
    # tmp_file은 내용을 다시 비움.
    cat /dev/null > "/tmp_file"

    slave=${nic}
    # echo " slave : ${slave} "

    while IFS= read -r line; do 

        key=$(echo ${line} | cut -d "=" -f 1)
        value=$(echo ${line} | cut -d "=" -f 2)
        
        if [[ -z ${value} ]]; then

            if [[ ${key} == *MASTER* ]]; then 
                value="${master}"
            else 
                value="${nic}"
            fi
        fi

        echo "${key}=${value}" >> "/tmp_file"

    done < "${ifcfg_slave}" # while IFS= read -r line; do 

    # 'NAME'에 해당하는 Value : 큰 따옴표 ("")로 감싸주기 
    old_value=$(cat /tmp_file | grep 'NAME' | cut -d "=" -f 2)
    new_value='"'"${old_value}"'"'

    # echo "old_value : ${old_value}"
    # echo "new_value : ${new_value}"

    name_value=$(sed -i "s/"NAME=${old_value}"/"NAME=${new_value}"/g" "/tmp_file")

    cp /tmp_file "${ifcfg_path}ifcfg-${slave}"

done # for nic in ${!bonding_members[@]}; do

# remove tmp_file after creating slave ifcfg config files 
rm -rv /tmp_file








































# echo "====================================="
# cat /tmp_file
# rm -rv /tmp_file

# if [[ -f ${ifcfg_slave} ]]; then

#     while IFS= read -r line; do   
#         echo " line : ${line} "
#     done < "${ifcfg_slave}"

# fi










