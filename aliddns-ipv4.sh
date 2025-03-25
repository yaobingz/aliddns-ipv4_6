#!/bin/bash
#脚本最好用bash运行，命令格式：bash aliddns
#下面引号内改成你的阿里ak
aliddnsipv4_ak=""
#下面引号内改成你的阿里sk
aliddnsipv4_sk=""
#下面引号内改成你要解析域名的前缀，根域名填@
aliddnsipv4_name1=""
#下面引号内改成你的主域名，例如：baidu.com  
aliddnsipv4_domain=""
#解析TTL时间（阿里默认600秒）
aliddnsipv4_ttl="600"

# 处理根域名情况
if [ "$aliddnsipv4_name1" = "@" ]
then
  aliddnsipv4_name=$aliddnsipv4_domain
else
  aliddnsipv4_name=$aliddnsipv4_name1.$aliddnsipv4_domain
fi

# 获取当前时间
echo "当前时间为：$(date)"

# 获取本机IPv4地址（双保险机制）
ipv4=$(curl -sL --connect-timeout 3 members.3322.org/dyndns/getip) 
[ -z "$ipv4" ] && ipv4=$(curl -s whatismyip.akamai.com)
echo "当前本机IPv4：$ipv4"

# 获取当前解析记录
current_ipv4=$(curl -sL --connect-timeout 3 "119.29.29.29/d?dn=$aliddnsipv4_name&type=A")
echo "当前阿里解析IP：$current_ipv4"

# IP对比检查
if [ "$ipv4" = "$current_ipv4" ]
then
   echo "IP未变化，无需更新"
   exit
else
   unset aliddnsipv4_record_id
fi

# 编码函数
urlencode() {
    out=""
    while read -n1 c
    do
        case $c in
            [a-zA-Z0-9._-]) out="$out$c" ;;
            *) out="$out$(printf '%%%02X' "'$c")" ;;
        esac
    done
    echo -n $out
}

enc() {
    echo -n "$1" | urlencode
}

# 阿里云API请求
send_request() {
    local args="AccessKeyId=$aliddnsipv4_ak&Action=$1&Format=json&$2&Version=2015-01-09"
    local hash=$(echo -n "GET&%2F&$(enc "$args")" | openssl dgst -sha1 -hmac "$aliddnsipv4_sk&" -binary | openssl base64)
    curl -s "http://alidns.aliyuncs.com/?$args&Signature=$(enc "$hash")"
}

# 记录操作函数
get_recordid() {
    grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"'
}

query_recordid() {
    send_request "DescribeSubDomainRecords" "SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&SubDomain=$aliddnsipv4_name&Timestamp=$timestamp&Type=A"
}

update_record() {
    send_request "UpdateDomainRecord" "RR=$aliddnsipv4_name1&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$aliddnsipv4_ttl&Timestamp=$timestamp&Type=A&Value=$(enc $ipv4)"
}

add_record() {
    send_request "AddDomainRecord&DomainName=$aliddnsipv4_domain" "RR=$aliddnsipv4_name1&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$aliddnsipv4_ttl&Timestamp=$timestamp&Type=A&Value=$(enc $ipv4)"
}

# 主流程
timestamp=$(date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ")
aliddnsipv4_record_id=$(query_recordid | get_recordid)

if [ -z "$aliddnsipv4_record_id" ]
then
    aliddnsipv4_record_id=$(add_record | get_recordid)
    echo "已添加新解析记录：$aliddnsipv4_name -> $ipv4 (RecordID: $aliddnsipv4_record_id)"
else
    update_record $aliddnsipv4_record_id
    echo "已更新解析记录：$aliddnsipv4_name -> $ipv4"
fi