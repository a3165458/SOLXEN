#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi


function install_node() {

read -p "请输入助记词: " mnemonic
read -p "请输入并发数量: " num
read -p "请输入优先级费用: " fee
read -p "请输入间隔时间(毫秒): " time


# 更新系统和安装必要的包
echo "更新系统软件包..."
sudo apt update && sudo apt upgrade -y
echo "安装必要的工具和依赖..."
sudo apt install -y curl build-essential jq git libssl-dev pkg-config screen

# 安装 Rust 和 Cargo
echo "正在安装 Rust 和 Cargo..."
curl https://sh.rustup.rs -sSf | sh -s -- -y
source $HOME/.cargo/env

# 安装 Solana CLI
echo "正在安装 Solana CLI..."
sh -c "$(curl -sSfL https://release.solana.com/v1.18.4/install)"

# 检查 solana-keygen 是否在 PATH 中
if ! command -v solana-keygen &> /dev/null; then
    echo "将 Solana CLI 添加到 PATH"
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    export PATH="$HOME/.cargo/bin:$PATH"
    

fi

# 创建 Solana 密钥对
echo "正在创建 Solana 密钥对..."
solana-keygen new --derivation-path m/44'/501'/0'/0' --force | tee solana-keygen-output.txt

# 显示提示信息，要求用户确认已备份
echo "请确保你已经备份了上面显示的助记词和私钥信息。"
echo "请向pubkey充值sol资产，用于挖矿gas费用。"

echo "备份完成后，请输入 'yes' 继续："

read -p "" user_confirmation

if [[ "$user_confirmation" == "yes" ]]; then
    echo "确认备份。继续执行脚本..."
else
    echo "脚本终止。请确保备份你的信息后再运行脚本。"
    exit 1
fi

# 迁移地址文件
mv -f /root/.config/solana/id.json /root/.config/solana/id1.json


# 获取操作系统类型和架构
OS=$(uname -s)
ARCH=$(uname -m)

# 确定下载 URL
case "$OS" in
  "Darwin")
    if [ "$ARCH" = "x86_64" ]; then
      URL="https://github.com/mmc-98/solxen-tx/releases/download/mainnet-alpha/solxen-tx-mainnet-alpha-darwin-amd64.tar.gz"
    elif [ "$ARCH" = "arm64" ]; then
      URL="https://github.com/mmc-98/solxen-tx/releases/download/mainnet-alpha/solxen-tx-mainnet-alpha-darwin-arm64.tar.gz"
    else
      echo "不支持的架构: $ARCH"
      exit 1
    fi
    ;;
  "Linux")
    if [ "$ARCH" = "x86_64" ]; then
      URL="https://github.com/mmc-98/solxen-tx/releases/download/mainnet-alpha/solxen-tx-mainnet-alpha-linux-amd64.tar.gz"
    elif [ "$ARCH" = "aarch64" ]; then
      URL="https://github.com/mmc-98/solxen-tx/releases/download/mainnet-alpha/solxen-tx-mainnet-alpha-linux-arm64.tar.gz"
    else
      echo "不支持的架构: $ARCH"
      exit 1
    fi
    ;;
  *)
    echo "无法支持的系统: $OS"
    exit 1
    ;;
esac

# 创建临时目录并下载文件
TMP_DIR=$(mktemp -d)
cd $TMP_DIR
echo "下载对应文件 $URL..."
curl -L -o solxen-tx.tar.gz $URL

# 解压缩文件
echo "解压文件中 solxen-tx.tar.gz..."
tar -xzvf solxen-tx.tar.gz

# 确保 /usr/local/bin 目录存在
sudo mkdir -p /usr/local/bin

# 创建根目录的 solxen 文件夹
sudo mkdir -p solxen

# 假设解压后的文件包含一个可执行文件 solxen-tx
# 将 solxen-tx 移动到 /usr/local/bin，其他文件移动到 /solxen
for file in *; do
  if [ "$file" = "solxen-tx" ]; then
    echo "Moving $file to /usr/local/bin..."
    sudo mv $file /usr/local/bin
  else
    echo "Moving $file to /solxen..."
    sudo mv $file ~/solxen
  fi
done

SOLXEN_FILE="/root/solxen/solxen-tx.yaml"

sudo sed -i "s|Mnemonic:.*|Mnemonic: \"$mnemonic\"|" $SOLXEN_FILE
sudo sed -i "s|Num:.*|Num: $num|" $SOLXEN_FILE
sudo sed -i "s|Fee:.*|Fee: $fee|" $SOLXEN_FILE
sudo sed -i "s|Time:.*|Time: $time|" $SOLXEN_FILE

# 清理临时目录
cd ~
rm -rf $TMP_DIR

screen -dmS solxen bash -c 'solxen-tx miner'



echo '====================== 安装完成，节点已经后台启动，请使用脚本功能2/输入screen -r SOLXEN 查看运行情况==========================='

}

# 查看进度
function check_XEN() {
    screen -r SOLXEN
}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
        echo "================================================================"
        echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
        echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "1. 安装节点"
        echo "2. 查看运行情况"
        read -p "请输入选项（1-2）: " OPTION

        case $OPTION in
        1) install_node ;;
        2) check_XEN ;;
        *) echo "无效选项。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
    
}

# 显示主菜单
main_menu
