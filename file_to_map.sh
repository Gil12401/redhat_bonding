#!/bin/bash

# 첫번째 argument ( $1 ) 의 결과 ( 특정파일에 대한 cat명령어 ) 를 key-value 연관 배열에 담아서 반환
# cat $1의 결과를 임시파일에 저장 
# 파일을 한줄씩 읽어들이면서 key-value 연관 배열에 담음

# declare -p release_map 제외 출력이 나오지 않도록 주의할 것  

unset ${map}
declare -A map

# echo "argument : $1"

touch /tmp_file 
tmp_file=$(find / -maxdepth 1 -name "tmp_file")

# cat /etc/*release | grep '=' > ${tmp_file}
cat $1 | grep '=' > ${tmp_file}

PRE_IFS=$IFS # IFS value back up

if [[ -f "${tmp_file}" ]]; then  
    IFS="="
    while read -r key value; do
        # Line is not empty and annotation 
        if [[ -n "${key}" && "${key}" != \#* ]]; then
            # echo " key : ${key} value : ${value} "

            value=$(echo "${value}" | tr -d '"')
            map[${key}]=${value}
        fi
    done < "${tmp_file}"
    IFS=$PRE_IFS
  else
      echo "${tmp_file} does not exist."
  fi

  rm -rv ${tmp_file} > /dev/null

declare -p map