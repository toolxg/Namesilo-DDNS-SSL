#!/bin/bash

### 用户数据

# 域名
DOMAIN=""

# 前缀主机名
HOST=""

# API key
APIKEY=""

# 接口超时时间(秒)
# UTO=url time out
UTO=5

# cron循环时间>10分钟运行一次<(请参照 cron 规则填写)
looptime="*/10 * * * *"

### 脚本定义

## 定义时间格式(使用于日志)
# Stime=systeml time
Stime="$(date +\%Y-\%m-\%d-\%H:\%M) --"

## 获取运行目录
# dirname $0,取得当前执⾏的脚本⽂件⽗⽬录
# cd `dirname $0`,进⼊这个⽬录(切换当前⼯作⽬录)
# pwd,显⽰当前⼯作⽬录(cd执⾏后的)
# Rpath=run path
# --修改方法:--
# $ mkdir ddns 新建目录(需提前创建自定义目录)
# Rpath="$(cd `dirname $0`; pwd)/ddns/"(注意最后/ 不可缺少)则可将脚本生成文件放置于 运行目录/ddns 下
Rpath="$(cd `dirname $0`; pwd)/"

## 判断用户数据是否为空
if [[ -z $DOMAIN ]] || [[ -z $HOST ]] || [[ -z $APIKEY ]]; then
    echo $Stime "用户数据存在未填写项，注意检查配置 >DOMAIN< >HOST< >APIKEY< 为必填项" >> ${Rpath}ddnslog.log
    echo -e "" >> ${Rpath}ddnslog.log
    exit 0
fi

## cron配置文件检查与替换
# cronLTR=cron loop time rule
# $(basename $0)获取当前运行的文件名
cronLTR="$looptime ${Rpath}$(basename $0)"

# cron配置文件地址(使用当前登录用户cron文件)
# ${USER}为系统自带环境变量
cronPath="/var/spool/cron/crontabs/${USER}"

# 以脚本路径判断cron配置文件内是否存在循环规则
# 使用脚本路径判断避免因时间规则不同而无法匹配
if cat $cronPath | grep -q -F "${Rpath}$(basename $0)"
then
    # 此处返回cron匹配全循环规则
    returnTxt=`cat $cronPath | grep -F "${Rpath}$(basename $0)"`
    
    # 判断cron配置文件内循环规则与本脚循环规则是否相同
    if [ "$returnTxt" != "$cronLTR" ]; then
        # 获取匹配文本行数
        # RTR=return txt rows
        RTR=`grep -n -F "$returnTxt" "$cronPath" | cut -d ":" -f 1`
        # 删除行
        sed -i ${RTR}d $cronPath
        # 置入
        echo "$cronLTR" >> $cronPath
        echo $Stime "cron循环规则与脚本不同,已做更改 >${cronLTR}<" >> ${Rpath}ddnslog.log
    fi
    # cron循环规则与脚本循环规则相同(可自行删除注释)
    # echo $Stime "cron循环规则相同，不做更改" >> ${Rpath}ddnslog.log
else
    echo "$cronLTR" >> $cronPath
    echo $Stime "cron配置文件添加循环规则 >${cronLTR}<" >> ${Rpath}ddnslog.log
fi

## 公网IP接口
# 亚马逊
IPURL[1]="https://checkip.amazonaws.com"
# 开源公网IP api
IPURL[2]="https://api.ipify.org"
#
IPURL[3]="https://ifconfig.me/ip"
#
IPURL[4]="https://api.my-ip.io/ip"


## 上次获取的公网IP
# 判断文件是否存在，不存在则新建oldip文件并置入0.0.0.0
# oIPPath=old ip path
oIPPath=${Rpath}oldip

if [ -f $oIPPath ]; then
    oldip=`cat $oIPPath`
else
    echo "0.0.0.0" > $oIPPath
    oldip="0.0.0.0"
fi

## 获取公网iP 
# iLoop=internet Loop
iLoop=0
while (($iLoop < 4)) #此处循环次数与 IPURL 定义数组数关联
do

    ((iLoop++))

    # 使用curl -w 获取返回状态码，使用-o 输出至文件使判断更简单,-s 静默输出。
    # 因curl使用-w时会与返回的网页数据组合但无明显分割所以将网页数据导出至文件。
    # --connect-timeout 设置连接超时时间以免过长时间的等待
    # gIIPStatus=Get internet IP status
    # iIPSatus=internet IP status
    # newIP 新获取的ip 单独使用于API提交

    gIIPStatus=`curl --connect-timeout $UTO -o ${Rpath}nowip -s -w %{http_code} ${IPURL[$i]}`
   
    # 判断返回的状态码为200则跳出循环，否则继续循环。
    if (($gIIPStatus == "200")); then 
        iIPSatus=`cat ${Rpath}nowip`
        break
    fi

    # 在循环最后一次后仍然无法获取则退出脚本并输出错误。
    if (($iLoop == 4)); then
        echo $Stime "接口错误，检查网络环境" >> ${Rpath}ddnslog.log
        echo -e "" >> ${Rpath}ddnslog.log
        exit 0
    fi

done

## 判断本次获取与上次获取IP是否相同
if [ "$iIPSatus" = "$oldip" ]; then
    echo $Stime "公网IP未改变" >> ${Rpath}ddnslog.log
    echo -e "" >> ${Rpath}ddnslog.log
    exit 0
else
    echo $iIPSatus > $oIPPath
    newIP=$iIPSatus
    echo $Stime "公网IP由>$oldip<更改为>$iIPSatus<"  >> ${Rpath}ddnslog.log
fi

## 获取namesilo Api Token
curl -s "https://www.namesilo.com/api/dnsListRecords?version=1&type=xml&key=$APIKEY&domain=$DOMAIN" > ${Rpath}${DOMAIN}.xml

## 提取resource id
ResourceID=`xmllint --xpath "//namesilo/reply/resource_record/record_id[../host/text() = '${HOST}.${DOMAIN}' ]"  ${Rpath}${DOMAIN}.xml | grep -oP '(?<=<record_id>).*?(?=</record_id>)'`

## 更新DNS记录
curl -s "https://www.namesilo.com/api/dnsUpdateRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrid=$ResourceID&rrhost=$HOST&rrvalue=$newIP&rrttl=3600" > ${Rpath}${DOMAIN}-ret.xml

## 判断是否提交成功
# Api状态解析 https://www.namesilo.com/api-reference
# submitS=submit status
submitS=`xmllint --xpath "//namesilo/reply/code/text()"  ${Rpath}${DOMAIN}-ret.xml`
if [ "$submitS" = "300" ]; then
    echo $Stime "Api更新成功" >> ${Rpath}ddnslog.log
    echo -e "" >> ${Rpath}ddnslog.log
    else
    echo $Stime "Api更新错误,返回状态码为$submitS" >> ${Rpath}ddnslog.log
    echo -e "" >> ${Rpath}ddnslog.log
fi

exit 0