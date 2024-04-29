#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi


function install_node() {

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

# 设置 Solana 测试网
solana config set --url https://api.testnet.solana.com

# 获取测试币
solana airdrop 1

# 查询余额（测试币）
solana balance

# 迁移地址文件
mv -f /root/.config/solana/id.json /root/.config/solana/id1.json

# 迁移地址文件
solana-keygen new
solana airdrop 1
solana balance
mv -f /root/.config/solana/id.json /root/.config/solana/id2.json

# 备用水龙头链接
echo "如果领取失败，请访问: https://faucet.solana.com/ or https://www.testnetfaucet.org/"

# 浏览器查询余额
echo "Check balance online at: https://explorer.solana.com/address/8u3pJcoHCW1FkLZ2sNoPsowV5d6MTSVVGrfTdhWgqbKH?cluster=testnet"

# 配置其他环境
source ~/.bashrc

# 创建新的 Rust 项目
cargo new my_project
cd my_project

# 编辑 Cargo.toml 文件，添加 Solana 依赖
echo 'solana-client = "1.10"' >> Cargo.toml
echo 'solana-sdk = "1.10"' >> Cargo.toml

# 编辑 Rust 程序文件
cat <<EOF >src/main.rs
use solana_client::rpc_client::RpcClient;
use solana_sdk::{
    compute_budget::ComputeBudgetInstruction,
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    transaction::Transaction,
    system_instruction,
};
use solana_sdk::signer::keypair::read_keypair_file;
use std::{str::FromStr, sync::Arc, thread};
use std::path::PathBuf;

fn main() {
    // RPC URL for the Solana testnet
    let rpc_url = String::from("https://api.testnet.solana.com");
    let client = RpcClient::new(&rpc_url);
    let client = Arc::new(client);

    // Load keypairs from files
    let keypair_path1 = PathBuf::from("/root/.config/solana/id1.json");
    let keypair_path2 = PathBuf::from("/root/.config/solana/id2.json");
    let payer1 = read_keypair_file(&keypair_path1).expect("Failed to read keypair from file 1");
    let payer2 = read_keypair_file(&keypair_path2).expect("Failed to read keypair from file 2");

    // Multithreading example with Solana transactions
    let key_bytes1 = payer1.to_bytes();
    let key_bytes2 = payer2.to_bytes();

    let handles1: Vec<_> = (0..10).map(|_| {
        let client = Arc::clone(&client);
        let key_bytes = key_bytes1.clone();

        thread::spawn(move || {
            let payer = Keypair::from_bytes(&key_bytes).expect("Failed to deserialize keypair");
            send_transaction(&client, &payer);
        })
    }).collect();

    let handles2: Vec<_> = (0..10).map(|_| {
        let client = Arc::clone(&client);
        let key_bytes = key_bytes2.clone();

        thread::spawn(move || {
            let payer = Keypair::from_bytes(&key_bytes).expect("Failed to deserialize keypair");
            send_transaction(&client, &payer);
        })
    }).collect();

    for handle in handles1.into_iter().chain(handles2) {
        handle.join().unwrap();
    }
}

fn send_transaction(client: &RpcClient, payer: &Keypair) {
    let program_id = Pubkey::from_str("7R2KMCUW1GimTEiS8tp8jJrde2N66yQiJ1MEUTbaPgfq").unwrap();
    let result_account = Keypair::new();
    let space = 5;
    let rent_exemption = client.get_minimum_balance_for_rent_exemption(space).unwrap();
    let create_account_instruction = system_instruction::create_account(&payer.pubkey(), &result_account.pubkey(), rent_exemption, space as u64, &program_id);
    let process_instruction_accounts = vec![AccountMeta::new(result_account.pubkey(), false)];
    let process_instruction = Instruction::new_with_bincode(program_id, &[0], process_instruction_accounts);
    let max_units = 1_200_000;
    let compute_budget_instruction = ComputeBudgetInstruction::set_compute_unit_limit(max_units);
    let mut transaction = Transaction::new_with_payer(&[compute_budget_instruction, create_account_instruction, process_instruction], Some(&payer.pubkey()));
    let recent_blockhash = client.get_latest_blockhash().unwrap();
    transaction.sign(&[payer, &result_account], recent_blockhash);
    match client.send_and_confirm_transaction(&transaction) {
        Ok(_) => println!("Transaction sent successfully."),
        Err(e) => eprintln!("Failed to send transaction: {}", e),
    }
}
EOF

# 安装 GCC
sudo apt install gcc

# 构建项目
cargo build

# 运行项目
screen -dmS SOLXEN bash -c 'while true; do cargo run; echo "程序已退出，将在5秒后重启..."; sleep 5; done'

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
