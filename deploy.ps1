# -----------------------------
# 配置路径和变量
# -----------------------------
$solc = "I:\web3\solc.exe"
$contractPath = "I:\web3\solidity-learn\contracts\task1\Test.sol"
$buildDir = "I:\web3\solidity-learn\contracts\task1\build"

$wslGeth = "/mnt/i/web3/go-ethereum-1.11.6/build/bin/geth"
$wslDatadir = "/mnt/i/web3/gethdata"
$rpcUrl = "http://127.0.0.1:8545"
$account = "0x83e61B16E254f9181EBA01f1D99d5570b136802a"
$passwordFile = "/mnt/i/web3/gethdata/password.txt"

# -----------------------------
# 编译合约
# -----------------------------
Write-Host "Compiling contract..."
& $solc --optimize --bin --abi $contractPath -o $buildDir

$abiPath = Join-Path $buildDir "Test.abi"
$binPath = Join-Path $buildDir "Test.bin"

# -----------------------------
# 启动私链节点（如果没启动）
# -----------------------------
Write-Host "Starting private chain in WSL..."
Start-Process wsl -ArgumentList "$wslGeth --datadir $wslDatadir --networkid 2025 --http --http.api eth,web3,personal,net,miner --http.addr 0.0.0.0 --http.port 8545 --allow-insecure-unlock --unlock $account --password $passwordFile --mine --miner.threads=1 --ipcdisable" -NoNewWindow

# 等待节点启动
Start-Sleep -Seconds 5

# -----------------------------
# 部署合约
# -----------------------------
Write-Host "Deploying contract..."
$pythonScript = @"
import json
from web3 import Web3

w3 = Web3(Web3.HTTPProvider('$rpcUrl'))

with open(r'$abiPath') as f:
    abi = json.load(f)

with open(r'$binPath') as f:
    bytecode = '0x' + f.read().strip()

w3.eth.default_account = '$account'

tx_hash = w3.eth.contract(abi=abi, bytecode=bytecode).constructor().transact()
receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
print('Contract deployed at:', receipt.contractAddress)
"@

$tmpPy = "$env:TEMP\deploy_temp.py"
$pythonScript | Out-File -FilePath $tmpPy -Encoding utf8

python $tmpPy

Remove-Item $tmpPy
