#!/bin/bash
# deploy_contract.sh
# 一键启动私链并部署合约

# =======================
# 配置项
# =======================
GETH_PATH="/mnt/i/web3/go-ethereum-1.11.6/build/bin/geth"
DATADIR="$HOME/wsl_chain"
NETWORK_ID=2025
MINER_ACCOUNT="0x83e61B16E254f9181EBA01f1D99d5570b136802a"
PASSWORD_FILE="/mnt/i/web3/solidity-learn/password.txt"
ABI_FILE="/mnt/i/web3/solidity-learn/contracts/task1/build/Test.abi"
BIN_FILE="/mnt/i/web3/solidity-learn/contracts/task1/build/Test.bin"
GAS_LIMIT=3000000

# =======================
# 生成私链 data 目录
# =======================
mkdir -p $DATADIR
if [ ! -f "$DATADIR/geth/genesis.json" ]; then
cat > "$DATADIR/geth/genesis.json" <<EOF
{
  "config": {
    "chainId": $NETWORK_ID,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "ethash": {}
  },
  "difficulty": "0x20000",
  "gasLimit": "0x8000000",
  "alloc": {
    "$MINER_ACCOUNT": {
      "balance": "0xffffffffffffffff"
    }
  }
}
EOF
    $GETH_PATH init "$DATADIR/geth/genesis.json"
fi

# =======================
# 启动 geth 私链（后台）
# =======================
echo "Starting private chain..."
$GETH_PATH --datadir $DATADIR \
  --networkid $NETWORK_ID \
  --http \
  --http.api eth,web3,personal,net,miner \
  --http.addr 0.0.0.0 \
  --http.port 8545 \
  --http.corsdomain "*" \
  --http.vhosts="*" \
  --allow-insecure-unlock \
  --unlock $MINER_ACCOUNT \
  --password $PASSWORD_FILE \
  --mine \
  --miner.threads=1 \
  --miner.etherbase=$MINER_ACCOUNT \
  --ipcdisable \
  > "$DATADIR/geth.log" 2>&1 &

# 等待 geth 启动
echo "Waiting for geth to start..."
sleep 5

# =======================
# 部署合约
# =======================
echo "Deploying contract..."
python3 <<EOF
from web3 import Web3
import json
import time

w3 = Web3(Web3.HTTPProvider("http://127.0.0.1:8545"))

# 等待节点 ready
while not w3.isConnected():
    print("Waiting for node...")
    time.sleep(1)

abi = json.load(open("$ABI_FILE"))
with open("$BIN_FILE") as f:
    bytecode = "0x" + f.read().strip()

account = "$MINER_ACCOUNT"

# 部署
Contract = w3.eth.contract(abi=abi, bytecode=bytecode)
tx_hash = Contract.constructor().transact({'from': account, 'gas': $GAS_LIMIT})

print("Transaction sent:", tx_hash.hex())

# 等待交易挖矿
receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
print("Contract deployed at:", receipt.contractAddress)
EOF

