#!/bin/bash

clear

#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 定义颜色
RED='\033[0;31m'    # 红色
GREEN='\033[0;32m'  # 绿色
YELLOW='\033[0;33m' # 黄色
NC='\033[0m'        # 无颜色

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

log_warning "当前运行目录为 $(pwd)" || true

set -x # 显示正在执行的命令

git_clone_or_pull() {
    set +x
    local repo_url=$1   # 仓库的URL
    local target_dir=$2 # 克隆的目标目录
    local branch=$3     # 选择的分支
    local retries=3     # 重试次数
    local delay=5       # 每次重试间隔的秒数
    local original_dir  # 记录当前工作目录
    original_dir=$(pwd)

    log_warning "正在拉取${repo_url}"

    # 如果未提供分支，尝试检测默认分支
    if [[ -z ${branch} ]]; then
        log_warning "未提供分支，尝试检测默认分支..."

        for ((i = 1; i <= retries; i++)); do
            log_success "正在获取 ${repo_url} 的默认分支"

            # 获取默认分支
            if branch=$(git ls-remote --symref "${repo_url}" HEAD 2>/dev/null | awk '/^ref:/ {print $2}' | sed 's|refs/heads/||' || true) && [[ -n ${branch} ]]; then
                log_success "获取成功！分支为 ${branch}"
                break
            else
                log_error "获取分支失败，第 ${i} 次重试..."
                sleep "${delay}"
            fi
        done

        # 如果检测不到默认分支，使用 'master' 或 'main'
        if [[ -z ${branch} ]]; then
            log_warning "检测默认分支失败，使用 'master' 或 'main'..."
            branch="master"

            # 检查 'master' 是否存在，如果不存在则使用 'main'
            if ! git ls-remote --exit-code --heads "${repo_url}" "${branch}" >/dev/null; then
                branch="main"
            fi
        fi

        log_success "使用的分支为：${branch}"
    fi

    # 如果目标目录存在，尝试 pull 更新
    if [[ -d ${target_dir} ]]; then
        log_warning "目录已存在，尝试更新仓库..."
        cd "${target_dir}" || exit 1

        for ((i = 1; i <= retries; i++)); do
            log_success "正在更新 ${repo_url} 的 ${branch} 分支"
            if git pull origin "${branch}"; then
                log_success "更新成功！"
                cd "${original_dir}" || exit 1 # 更新成功后恢复工作目录
                set -x
                return 0
            else
                log_error "更新失败，第 ${i} 次重试..."
                sleep "${delay}"
            fi
        done

        cd "${original_dir}" || exit 1 # 恢复工作目录
        log_error "更新多次失败，请检查网络或仓库状态。"
        return 1

        # 如果目标目录不存在，尝试浅克隆
    else
        log_warning "目录不存在，开始浅克隆仓库..."
        for ((i = 1; i <= retries; i++)); do
            log_success "正在克隆 ${repo_url} 的 ${branch} 分支, 目标目录 ${target_dir}"
            if git clone --depth 1 -b "${branch}" "${repo_url}" "${target_dir}"; then
                log_success "浅克隆成功！"
                cd "${original_dir}" || exit 1 # 克隆成功后恢复工作目录
                set -x
                return 0
            else
                log_error "浅克隆失败，第 ${i} 次重试..."
                sleep "${delay}"
            fi
        done

        log_error "浅克隆多次失败，请检查网络或仓库状态。"
        return 1
    fi
}

# 删除文件夹函数
delete_directory() {
    set +x
    local dir="$1"

    # 检查是否提供目录路径
    if [[ -z ${dir} ]]; then
        log_error "错误：没有提供要删除的文件夹路径。"
        return 1
    fi

    # 检查目录是否存在
    if [[ ! -d ${dir} ]]; then
        log_warning "警告：目录 '${dir}' 不存在。"
        return 1
    fi

    # 执行删除操作
    log_error "正在删除 ${dir}"

    # 检查删除是否成功
    if rm -rf "${dir}"; then
        log_success "成功：目录 '${dir}' 已删除。"
    else
        log_error "错误：删除目录 '${dir}' 失败。"
        return 1
    fi
    set -x
}

apply_patch() {
    set +x
    patch_file=$1
    if patch --dry-run -p1 <"${patch_file}" >/dev/null 2>&1; then
        patch -p1 <"${patch_file}"
        log_success "${patch_file} 补丁应用成功"
    else
        log_error "${patch_file} 补丁已经应用或无效"
    fi
    set -x
}

check_content_in_file() {
    set +x
    local content="$1"
    local file="$2"
    if grep -q "${content}" "${file}"; then
        log_error "文件 '${file}' 包含内容: '${content}', 跳过"
    else
        log_success "写入 '${content}' 到 '${file}'"
        echo "${content}" >>"${file}"
    fi
    set -x
}

# 获取 GitHub API 数据的函数，带有 API 限制重试和提醒机制
fetch_mihomo_branch_data() {
    set +x
    local API_URL="https://api.github.com/repos/MetaCubeX/mihomo/branches"
    local BRANCH_NAME="Alpha"
    local mihomo_config="package/nikki/Makefile"  # 需要替换的文件名
    local retries=3                               # 最大重试次数
    local retry_interval=60                       # 每次重试的等待时间 (秒)

    # 将分支名称转换为小写
    local lower_branch=${BRANCH_NAME}
    lower_branch=$(echo "${BRANCH_NAME}" | tr '[:upper:]' '[:lower:]')

    for ((i = 1; i <= retries; i++)); do
        log_warning "尝试第 ${i} 次获取分支数据..."

        # 使用 curl 获取 JSON 并使用 jq 解析
        sha=$(curl -s -H "Accept: application/vnd.github.v3+json" "${API_URL}" | jq -r --arg branch "${BRANCH_NAME}" '.[] | select(.name == $branch) | .commit.sha') || true

        # 检查是否获取到了数据
        if [[ -n ${sha} ]]; then
            # 获取短格式的 sha (前7位)
            short_sha=$(echo "${sha}" | cut -c 1-7)

            # 替换 PKG_SOURCE_VERSION 和 PKG_BUILD_VERSION 中的内容
            sed -i "s/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=${sha}/" "${mihomo_config}"
            sed -i "s/PKG_BUILD_VERSION:=${lower_branch}-.*/PKG_BUILD_VERSION:=${lower_branch}-${short_sha}/" "${mihomo_config}"

            # 移除 PKG_MIRROR_HASH 行
            sed -i "s/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/" "${mihomo_config}"

            log_success "成功更新配置文件: ${mihomo_config}"
            break
        else
            # 如果没有获取到 sha，可能是因为 API 达到了限制
            remaining_rate_limit=$(curl -s -I "${API_URL}" | grep -FiX "X-RateLimit-Remaining" | awk '{print $2}' | tr -d '\r') || true

            if [[ ${remaining_rate_limit} == "0" ]]; then
                log_error "API 请求达到限制，等待 ${retry_interval} 秒后重试..."
                sleep "${retry_interval}"
            else
                log_error "获取分支数据失败，请检查 API 请求或网络连接。"
                exit 1
            fi
        fi
    done
    set -x
}

# 更新
git pull

# Add a feed source
#echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
# check_content_in_file 'src-git mosdns https://github.com/sbwml/luci-app-mosdns.git;v5' 'feeds.conf.default'
# check_content_in_file 'src-git mihomo https://github.com/morytyann/OpenWrt-mihomo.git;main' 'feeds.conf.default'

./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds install -a

# 修改时区 UTF-8
log_success "修改时区"
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate

# 时区
log_success "修改NTP服务器"
sed -i 's/time1.apple.com/time1.cloud.tencent.com/g' package/base-files/files/bin/config_generate
sed -i 's/time1.google.com/ntp.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/time.cloudflare.com/cn.ntp.org.cn/g' package/base-files/files/bin/config_generate
sed -i 's/pool.ntp.org/cn.pool.ntp.org/g' package/base-files/files/bin/config_generate

# 修改主机名 OP
log_success "修改主机名"
sed -i 's/OpenWrt/ImmortalWrt/g' package/base-files/files/bin/config_generate

# 修改wifi名称（mtwifi-cfg）
log_success "修改wifi名称"
sed -i 's/ssid="ImmortalWrt-2.4G"/ssid="YuGuGu_IMM-2.4G"/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh
sed -i 's/ssid="ImmortalWrt-5G"/ssid="YuGuGu_IMM-5G"/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh

# 替换源
log_success "替换仓库默认源"
sed -i 's,mirrors.vsean.net/openwrt,mirror.nju.edu.cn/immortalwrt,g' package/emortal/default-settings/files/99-default-settings-chinese

# 修改默认IP
log_success "修改默认IP"
sed -i 's/192.168.1.1/192.168.114.1/g' package/base-files/files/bin/config_generate # 定制默认IP

# 修改编译信息
log_success "修改编译信息"
sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By YuGuGu ($(date "+%Y-%m-%d %H:%M"))'/g" package/base-files/files/etc/openwrt_release || true

# sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By YuGuGu ($(date +%Y-%m-%d %H:%M)) '/g" package/base-files/files/etc/openwrt_release

# 修改 ash 为 bash
log_success "修改 ash 为 bash"
sed -i "s#/bin/ash#/bin/bash#g" package/base-files/files/etc/passwd

log_success "设置sysctl"
check_content_in_file "net.core.default_qdisc = cake" package/base-files/files/etc/sysctl.d/99-custom.conf
check_content_in_file "net.ipv4.tcp_congestion_control = bbr" package/base-files/files/etc/sysctl.d/99-custom.conf

log_success "设置minieap重启脚本"
cp -rf reminieap package/base-files/files/bin/reminieap
chmod +x package/base-files/files/bin/reminieap

# 移除主题重复软件包
log_success "设置argon主题"
find ./ | grep Makefile | grep feeds/luci/luci-theme-argon | xargs rm -f || true
find ./ | grep Makefile | grep feeds/luci/luci-app-argon-config | xargs rm -f || true

# Themes
git_clone_or_pull https://github.com/jerrykuku/luci-theme-argon luci-theme-argon master
# git_clone_or_pull https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config master

delete_directory package/luci-theme-argon
delete_directory feeds/luci/themes/luci-theme-argon

cp -rf luci-theme-argon package/luci-theme-argon
cp -rf luci-theme-argon feeds/luci/themes/luci-theme-argon

# 修改 argon 为默认主题,可根据你喜欢的修改成其他的（不选择那些会自动改变为默认主题的主题才有效果）
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
find ./feeds -type f -regex ".*/root/etc/uci-defaults/.*theme.*" -exec sed -i 's@luci.main.mediaurlbase=/luci-static/.*@luci.main.mediaurlbase=/luci-static/argon@g' {} \;

# Replace bg file
find ./package/ ./feeds/ -type f -regex ".*bg1.jpg$" -exec cp -f bg1.jpg {} \;

log_success "设置mosdns"
# 移除官方golang防止mosdns编译爆炸
delete_directory feeds/packages/lang/golang
# git_clone_or_pull https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang 23.x
git_clone_or_pull https://github.com/sbwml/packages_lang_golang packages_lang_golang 24.x
cp -rf packages_lang_golang/ feeds/packages/lang/golang/

# 移除mosdns重复软件包防止mosdns编译爆炸
find ./ | grep "Makefile" | grep "feeds/packages/.*/v2ray-geodata" | xargs rm -f || true
find ./ | grep "Makefile" | grep "feeds/packages/.*/mosdns" | xargs rm -f || true

delete_directory feeds/packages/net/v2ray-geodata

git_clone_or_pull https://github.com/sbwml/v2ray-geodata v2ray-geodata
git_clone_or_pull https://github.com/sbwml/luci-app-mosdns mosdns v5

delete_directory package/mosdns/
cp -rf mosdns/mosdns/ package/mosdns/

delete_directory package/luci-app-mosdns/
cp -rf mosdns/luci-app-mosdns/ package/luci-app-mosdns/

delete_directory package/v2ray-geodata/
cp -rf v2ray-geodata/ package/v2ray-geodata/

delete_directory package/v2dat/
cp -rf mosdns/v2dat/ package/v2dat/

sed -i '/PKG_VERSION:=/s/-//g' package/v2ray-geodata/Makefile

# mihomo
log_success "设置mihomo"
git_clone_or_pull https://github.com/nikkinikki-org/OpenWrt-nikki OpenWrt-nikki main

delete_directory package/nikki/
cp -rf OpenWrt-nikki/nikki/ package/nikki/

delete_directory package/luci-app-nikki/
cp -rf OpenWrt-nikki/luci-app-nikki/ package/luci-app-nikki/

fetch_mihomo_branch_data

# # UA2F
# log_success "设置UA2F"
# find ./ | grep "Makefile" | grep "feeds/packages/.*/ua2f" | xargs rm -f || true
# git_clone_or_pull https://github.com/Zxilly/UA2F package/UA2F

# git_clone_or_pull https://github.com/lucikap/luci-app-ua2f.git luci-app-ua2f
# delete_directory luci-app-ua2f
# cp -rf luci-app-ua2f/luci-app-ua2f/ package/luci-app-ua2f/

# tailscale
log_success "设置tailscale"
sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' feeds/packages/net/tailscale/Makefile
git_clone_or_pull https://github.com/asvow/luci-app-tailscale.git luci-app-tailscale
delete_directory package/luci-app-tailscale
cp -rf luci-app-tailscale package/luci-app-tailscale

# eqosplus
log_success "设置eqosplus"
git_clone_or_pull https://github.com/sirpdboy/luci-app-eqosplus.git luci-app-eqosplus
delete_directory package/luci-app-eqosplus
cp -rf luci-app-eqosplus package/luci-app-eqosplus

# autotimeset
log_success "设置autotimeset"
git_clone_or_pull https://github.com/sirpdboy/luci-app-autotimeset luci-app-autotimeset
delete_directory package/luci-app-autotimeset
cp -rf luci-app-autotimeset package/luci-app-autotimeset

# # MentoHUST
# log_success "设置MentoHUST"
# sed -i "s/PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/" feeds/packages/net/mentohust/Makefile

# miniupnp
log_success "设置miniupnp"
git_clone_or_pull https://github.com/kiddin9/kwrt-packages.git kwrt-packages
delete_directory feeds/packages/net/miniupnpd/
cp -rf kwrt-packages/miniupnpd/ feeds/packages/net/miniupnpd/

# wolplus
log_success "设置wolplus"
git_clone_or_pull https://github.com/animegasan/luci-app-wolplus.git luci-app-wolplus
delete_directory package/luci-app-wolplus/
cp -rf luci-app-wolplus/ package/luci-app-wolplus/

# # MiniEAP
# log_success "设置minieap"
# # 移除 PKG_HASH 行
# sed -i "s/PKG_HASH:=.*/PKG_HASH:=skip/" feeds/packages/net/minieap/Makefile
# sed -i "s#PKG_SOURCE_URL:=.*#PKG_SOURCE_URL:=https://codeload.github.com/chenjunyu19/minieap/tar.gz/dev#" feeds/packages/net/minieap/Makefile

# lucky
log_success "设置lucky"
git_clone_or_pull https://github.com/gdy666/luci-app-lucky.git luci-app-lucky
delete_directory package/luci-app-lucky/
cp -rf luci-app-lucky/ package/luci-app-lucky/

# 设置密码为空（安装固件时无需密码登陆，然后自己修改想要的密码）
# sed -i 's@.*CYXluq4wUazHjmCDBCqXF*@#&@g' package/lean/default-settings/files/zzz-default-settings

# 添加额外软件包
# git clone --depth 1 https://github.com/kongfl888/luci-app-adguardhome package/luci-app-adguardhome
# git clone --depth 1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata
# git clone --depth 1 -b lede https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns

# 科学上网插件
# svn co https://github.com/kiddin9/openwrt-bypass/trunk/luci-app-bypass package/luci-app-bypass
# svn co https://github.com/vernesong/OpenClash/trunk/luci-app-openclash package/luci-app-openclash
# svn co https://github.com/xiaorouji/openwrt-passwall/branches/luci/luci-app-passwall package/luci-app-passwall
# svn co https://github.com/fw876/helloworld/trunk/luci-app-ssr-plus package/luci-app-ssr-plus

# 科学上网插件依赖
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/brook package/brook
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/chinadns-ng package/chinadns-ng
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/dns2socks package/dns2socks
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/dns2tcp package/dns2tcp
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/hysteria package/hysteria
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/ipt2socks package/ipt2socks
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/microsocks package/microsocks
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/naiveproxy package/naiveproxy
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/pdnsd-alt package/pdnsd-alt
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/sagernet-core package/sagernet-core
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/ssocks package/ssocks
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/tcping package/tcping
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/trojan-go package/trojan-go
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/trojan-plus package/trojan-plus
# svn co https://github.com/xiaorouji/openwrt-passwall/trunk/v2ray-geodata package/v2ray-geodata
# svn co https://github.com/fw876/helloworld/trunk/simple-obfs package/simple-obfs
# svn co https://github.com/fw876/helloworld/trunk/v2ray-core package/v2ray-core
# svn co https://github.com/fw876/helloworld/trunk/v2ray-plugin package/v2ray-plugin
# svn co https://github.com/fw876/helloworld/trunk/shadowsocks-rust package/shadowsocks-rust
# svn co https://github.com/fw876/helloworld/trunk/shadowsocksr-libev package/shadowsocksr-libev
# svn co https://github.com/fw876/helloworld/trunk/xray-core package/xray-core
# svn co https://github.com/fw876/helloworld/trunk/xray-plugin package/xray-plugin
# svn co https://github.com/fw876/helloworld/trunk/lua-neturl package/lua-neturl
# svn co https://github.com/fw876/helloworld/trunk/trojan package/trojan

log_warning "当前运行目录为 $(pwd)" || true

if [[ ! -e .config ]]; then
    # wget https://github.com/kiddin9/Kwrt/raw/master/devices/mediatek_filogic/.config -O .config
    wget https://github.com/YuCat-OVO/360T7_Scripts/raw/main/.config -O .config
fi

apply_patch autotimeset.diff
apply_patch minieap.diff
apply_patch eqosplus.diff
apply_patch geodata.diff

# wget https://github.com/kiddin9/Kwrt/raw/master/devices/mediatek_filogic/patches/01-360t7.patch -O 01-360t7.patch

# apply_patch 01-360t7.patch

make defconfig
