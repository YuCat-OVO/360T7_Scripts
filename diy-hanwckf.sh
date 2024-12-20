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

log_warning "当前运行目录为 $(pwd)"


set -x  # 显示正在执行的命令
git_clone_or_pull() {
    set +x
    local repo_url=$1   # 仓库的URL
    local target_dir=$2 # 克隆的目标目录
    local branch=$3     # 选择的分支
    local retries=3     # 重试次数
    local delay=5       # 每次重试间隔的秒数
    local original_dir=$(pwd) # 记录当前工作目录

    log_warning "正在拉取$repo_url"

    # 如果未提供分支，尝试检测默认分支
    if [ -z "$branch" ]; then
        echo -e "${YELLOW}未提供分支，尝试检测默认分支...${NC}"

        # 获取默认分支
        branch=$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null | awk '/^ref:/ {print $2}' | sed 's|refs/heads/||')

        # 如果检测不到默认分支，使用 'master' 或 'main'
        if [ -z "$branch" ]; then
            echo -e "${YELLOW}检测默认分支失败，使用 'master' 或 'main'...${NC}"
            branch="master"

            # 检查 'master' 是否存在，如果不存在则使用 'main'
            if ! git ls-remote --exit-code --heads "$repo_url" "$branch" >/dev/null; then
                branch="main"
            fi
        fi

        echo -e "${GREEN}使用的分支为：$branch${NC}"
    fi

    # 如果目标目录存在，尝试 pull 更新
    if [ -d "$target_dir" ]; then
        echo -e "${YELLOW}目录已存在，尝试更新仓库...${NC}"
        cd "$target_dir" || exit 1

        for ((i = 1; i <= retries; i++)); do
            log_success "正在更新 ${repo_url} 的 ${branch} 分支"
            git pull origin "$branch"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}更新成功！${NC}"
                cd "$original_dir" || exit 1  # 更新成功后恢复工作目录
                return 0
            else
                echo -e "${RED}更新失败，第 $i 次重试...${NC}"
                sleep $delay
            fi
        done

        cd "$original_dir" || exit 1  # 恢复工作目录
        log_error "更新多次失败，请检查网络或仓库状态。"
        return 1

    # 如果目标目录不存在，尝试浅克隆
    else
        echo -e "${YELLOW}目录不存在，开始浅克隆仓库...${NC}"
        for ((i = 1; i <= retries; i++)); do
            log_success "正在克隆 ${repo_url} 的 ${branch} 分支, 目标目录 ${target_dir}"
            git clone --depth 1 -b "$branch" "$repo_url" "$target_dir"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}浅克隆成功！${NC}"
                cd "$original_dir" || exit 1  # 克隆成功后恢复工作目录
                return 0
            else
                echo -e "${RED}浅克隆失败，第 $i 次重试...${NC}"
                sleep $delay
            fi
        done

        echo -e "${RED}浅克隆多次失败，请检查网络或仓库状态。${NC}"
        return 1
    fi
    set -x
}

# 删除文件夹函数
delete_directory() {
    set +x
    local dir="$1"

    # 检查是否提供目录路径
    if [ -z "$dir" ]; then
        echo -e "${RED}错误：没有提供要删除的文件夹路径。${NC}"
        return 1
    fi

    # 检查目录是否存在
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}警告：目录 '$dir' 不存在。${NC}"
        return 1
    fi

    # 执行删除操作
    log_error "正在删除 ${dir}"
    rm -rf "$dir"

    # 检查删除是否成功
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}成功：目录 '$dir' 已删除。${NC}"
    else
        echo -e "${RED}错误：删除目录 '$dir' 失败。${NC}"
        return 1
    fi
    set -x
}

apply_patch() {
  patch_file=$1
  if patch --dry-run -p1 < "$patch_file" > /dev/null 2>&1; then
    patch -p1 < "$patch_file"
    log_success "$patch_file 补丁应用成功"
  else
    log_error "$patch_file 补丁已经应用或无效"
  fi
}

./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds install -a

# 修改时区 UTF-8
echo -e "${GREEN}修改时区${NC}"
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate

# 时区
echo -e "${GREEN}修改NTP服务器${NC}"
sed -i 's/time1.apple.com/time1.cloud.tencent.com/g' package/base-files/files/bin/config_generate
sed -i 's/time1.google.com/ntp.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/time.cloudflare.com/cn.ntp.org.cn/g' package/base-files/files/bin/config_generate
sed -i 's/pool.ntp.org/cn.pool.ntp.org/g' package/base-files/files/bin/config_generate

# 修改主机名 OP
echo -e "${GREEN}修改主机名${NC}"
sed -i 's/OpenWrt/ImmortalWrt/g' package/base-files/files/bin/config_generate

# 修改wifi名称（mtwifi-cfg）
echo -e "${GREEN}修改wifi名称${NC}"
sed -i 's/ssid="ImmortalWrt-2.4G"/ssid="YuGuGu_ImmortalWrt-2.4G"/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh
sed -i 's/ssid="ImmortalWrt-5G"/ssid="YuGuGu_ImmortalWrt-5G"/g' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh

# 替换源
echo -e "${GREEN}替换仓库默认源${NC}"
sed -i 's,mirrors.vsean.net/openwrt,mirror.nju.edu.cn/immortalwrt,g' package/emortal/default-settings/files/99-default-settings-chinese

# 修改默认IP
echo -e "${GREEN}修改默认IP${NC}"
sed -i 's/192.168.1.1/192.168.114.1/g' package/base-files/files/bin/config_generate # 定制默认IP

# 修改编译信息
echo -e "${GREEN}修改编译信息${NC}"
sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By YuGuGu ($(date "+%Y-%m-%d %H:%M"))'/g" package/base-files/files/etc/openwrt_release

# sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By YuGuGu ($(date +%Y-%m-%d %H:%M)) '/g" package/base-files/files/etc/openwrt_release

echo -e "${GREEN}拉取最新分支${NC}"
git_clone_or_pull https://github.com/immortalwrt/luci.git immortalwrt-luci
git_clone_or_pull https://github.com/immortalwrt/packages.git immortalwrt-packages
# git_clone_or_pull https://github.com/kiddin9/openwrt-packages.git kiddin9-packages

# 移除主题重复软件包
find ./ | grep Makefile | grep package/feeds/luci/luci-theme-argon | xargs rm -f
find ./ | grep Makefile | grep package/feeds/luci/luci-app-argon-config | xargs rm -f

# 修改 argon 为默认主题,可根据你喜欢的修改成其他的（不选择那些会自动改变为默认主题的主题才有效果）
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

find ./feeds -type f -regex ".*/root/etc/uci-defaults/.*theme.*" | xargs sed -i 's@luci.main.mediaurlbase=/luci-static/.*@luci.main.mediaurlbase=/luci-static/argon@g'

find . -type f -regex ".*bg1.jpg" -exec cp -f bg1.jpg {} \;

# Themes
git_clone_or_pull https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon master
git_clone_or_pull https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config master

# 移除官方golang防止mosdns编译爆炸
delete_directory feeds/packages/lang/golang
git_clone_or_pull https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang 23.x

# 移除mosdns重复软件包防止mosdns编译爆炸
find ./ | grep Makefile | grep feeds/packages/.*/v2ray-geodata | xargs rm -f
find ./ | grep Makefile | grep feeds/packages/.*/mosdns | xargs rm -f

delete_directory feeds/packages/net/v2ray-geodata

git_clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
git_clone_or_pull https://github.com/sbwml/luci-app-mosdns package/mosdns v5

# minieap
find ./ | grep Makefile | grep feeds/luci/.*/luci-app-minieap | xargs rm -f
delete_directory feeds/luci/applications/luci-app-minieap
find ./ | grep Makefile | grep feeds/luci/.*/luci-proto-minieap | xargs rm -f
delete_directory feeds/luci/protocols/luci-proto-minieap

# git clone https://github.com/AutoCONFIG/luci-app-minieap.git feeds/luci/applications/luci-app-minieap

find ./ | grep Makefile | grep feeds/packages/net/minieap | xargs rm -f
delete_directory feeds/packages/net/minieap

# git clone -b default https://github.com/AutoCONFIG/minieap-openwrt.git package/minieap-openwrt
# git clone https://github.com/AutoCONFIG/minieap-openwrt.git package/minieap-openwrt

cp -rf immortalwrt-luci/applications/luci-app-minieap feeds/luci/applications/luci-app-minieap
cp -rf immortalwrt-luci/protocols/luci-proto-minieap feeds/luci/protocols/luci-proto-minieap

cp -rf immortalwrt-packages/net/minieap feeds/packages/net/minieap

# mentohust
find ./ | grep Makefile | grep feeds/luci/.*/luci-app-mentohust | xargs rm -f
delete_directory feeds/luci/applications/luci-app-mentohust

cp -rf immortalwrt-luci/applications/luci-app-mentohust feeds/luci/applications/luci-app-mentohust

find ./ | grep Makefile | grep feeds/net/mentohust | xargs rm -f
delete_directory feeds/packages/net/mentohust

cp -rf immortalwrt-packages/net/mentohust feeds/packages/net/mentohust

# openclash
# find ./ | grep Makefile | grep feeds/luci/.*/luci-app-openclash | xargs rm -f
# delete_directory feeds/luci/applications/luci-app-openclash

# cp -rf immortalwrt-luci/applications/luci-app-openclash feeds/luci/protocols/luci-app-openclash

# UA2F
find ./ | grep Makefile | grep feeds/packages/.*/ua2f | xargs rm -f
git_clone_or_pull https://github.com/Zxilly/UA2F package/UA2F

git_clone_or_pull https://github.com/lucikap/luci-app-ua2f.git luci-app-ua2f
cp -rf luci-app-ua2f/luci-app-ua2f/ package/luci-app-ua2f/
# delete_directory luci-app-ua2f

# mwan3
find ./ | grep Makefile | grep feeds/packages/net/mwan3 | xargs rm -f
delete_directory feeds/packages/net/mwan3
cp -rf immortalwrt-packages/net/mwan3 feeds/packages/net/mwan3

find ./ | grep Makefile | grep feeds/luci/.*/luci-app-mwan3/ | xargs rm -f
delete_directory feeds/luci/applications/luci-app-mwan3
cp -rf immortalwrt-luci/applications/luci-app-mwan3 feeds/luci/applications/luci-app-mwan3

# find ./ | grep Makefile | grep feeds/luci/.*/luci-app-mwan3helper | xargs rm -f
# delete_directory feeds/luci/applications/luci-app-mwan3helper
# cp -rf immortalwrt-luci/applications/luci-app-mwan3helper feeds/luci/applications/luci-app-mwan3helper

# tailscale
find ./ | grep Makefile | grep feeds/packages/net/tailscale | xargs rm -f
delete_directory feeds/packages/net/tailscale
cp -rf immortalwrt-packages/net/tailscale feeds/packages/net/tailscale

sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' feeds/packages/net/tailscale/Makefile
git_clone_or_pull https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale

# eqosplus
git_clone_or_pull https://github.com/sirpdboy/luci-app-eqosplus.git package/luci-app-eqosplus

# advancedplus
git_clone_or_pull https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat js
git_clone_or_pull https://github.com/sirpdboy/luci-app-advancedplus.git package/luci-app-advancedplus

sed -i "s/option gossr 'bypass'/option gossr 'openclash'/g" package/luci-app-advancedplus/root/etc/config/advancedplus
sed -i "s/option gossr 'bypass'/option gossr 'openclash'/g" package/luci-app-advancedplus/root/etc/init.d/advancedplus
sed -i "s/e.default = 'bypass'/e.default = 'openclash'/g" package/luci-app-advancedplus/luasrc/model/cbi/advancedplus/kucatset.lua
sed -i "/zsh/d" package/luci-app-advancedplus/root/etc/init.d/advancedplus

# autotimeset
git_clone_or_pull https://github.com/sirpdboy/luci-app-autotimeset package/luci-app-autotimeset

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

log_warning "当前运行目录为 $(pwd)"

if [ ! -e .config ]; then
    cp -f defconfig/mt7981-ax3000.config .config
fi

apply_patch autotimeset.diff
apply_patch minieap.diff

make defconfig
