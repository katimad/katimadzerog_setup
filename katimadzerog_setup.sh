#!/bin/bash

# 필요한 패키지 설치
sudo apt update && \
sudo apt install curl git jq build-essential gcc unzip wget lz4 -y
sleep 1

# Go 설치
cd $HOME && \
ver="1.21.3" && \
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz" && \
sudo rm -rf /usr/local/go && \
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz" && \
rm "go$ver.linux-amd64.tar.gz" && \
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile && \
source ~/.bash_profile && \
go version
sleep 1

# evmosd 바이너리 빌드
git clone https://github.com/0glabs/0g-evmos.git
cd 0g-evmos
git checkout v1.0.0-testnet
make install
evmosd version
sleep 1

# 변수 설정
echo "노드의 명칭을 입력하세요 생각나는걸로 적으셈:"
read MONIKER
echo "지갑의 이름을 입력하세요 그냥 노드 명칭과 같아도 무방해요:"
read WALLET_NAME

echo "export MONIKER=\"$MONIKER\"" >> ~/.bash_profile
echo 'export CHAIN_ID="zgtendermint_9000-1"' >> ~/.bash_profile
echo "export WALLET_NAME=\"$WALLET_NAME\"" >> ~/.bash_profile
echo 'export RPC_PORT="26657"' >> ~/.bash_profile
source $HOME/.bash_profile
sleep 1

# 노드 초기화
cd $HOME
evmosd init $MONIKER --chain-id $CHAIN_ID
evmosd config chain-id $CHAIN_ID
evmosd config node tcp://localhost:$RPC_PORT
evmosd config keyring-backend os
sleep 1

# genesis.json 다운로드
wget https://github.com/0glabs/0g-evmos/releases/download/v1.0.0-testnet/genesis.json -O $HOME/.evmosd/config/genesis.json
sleep 1

# config.toml에 seed와 peer 추가
PEERS="1248487ea585730cdf5d3c32e0c2a43ad0cda973@peer-zero-gravity-testnet.trusted-point.com:26326" && \
SEEDS="8c01665f88896bca44e8902a30e4278bed08033f@54.241.167.190:26656,b288e8b37f4b0dbd9a03e8ce926cd9c801aacf27@54.176.175.48:26656,8e20e8e88d504e67c7a3a58c2ea31d965aa2a890@54.193.250.204:26656,e50ac888b35175bfd4f999697bdeb5b7b52bfc06@54.215.187.94:26656" && \
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.evmosd/config/config.toml
sleep 1

# 최소 gas 가격 설정
sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.00252aevmos\"/" $HOME/.evmosd/config/app.toml
sleep 1

# 서비스 파일 생성
sudo tee /etc/systemd/system/ogd.service > /dev/null <<EOF
[Unit]
Description=OG 노드
After=network.target

[Service]
User=$USER
Type=simple
ExecStart=$(which evmosd) start --home $HOME/.evmosd
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
sleep 1

# 노드 시작 및 로그 모니터링
(sudo systemctl daemon-reload && \
sudo systemctl enable ogd && \
sudo systemctl restart ogd && \
sudo journalctl -u ogd -f -o cat &)

# 명령어 실행 후 로그 모니터링 시작 및 종료 기다리기
pid=$!
echo "로그 모니터링을 중지합니다. 'Ctrl + C'를 누르세요."

# 5초 대기 후 로그 모니터링 중단 및 명령어 실행
sleep 5 && \
echo "로그 모니터링을 중단합니다." && \
sudo pkill -P $$ && \
echo "로그 모니터링이 중단되었습니다. 스냅샷 생성을 시작합니다." && \
echo "스냅샷 다운로드 중..." && \
wget https://rpc-zero-gravity-testnet.trusted-point.com/latest_snapshot.tar.lz4
sleep 1 && \
echo "노드 중지 중..." && \
sudo systemctl stop ogd && \
sleep 1 && \
echo "priv_validator_state.json 백업 중..." && \
cp $HOME/.evmosd/data/priv_validator_state.json $HOME/.evmosd/priv_validator_state.json.backup && \
sleep 1 && \
echo "DB 백업중..." && \
evmosd tendermint unsafe-reset-all --home $HOME/.evmosd --keep-addr-book && \
lz4 -d -c ./latest_snapshot.tar.lz4 | tar -xf - -C $HOME/.evmosd && \
mv $HOME/.evmosd/priv_validator_state.json.backup $HOME/.evmosd/data/priv_validator_state.json && \
sudo systemctl restart ogd && sudo journalctl -u ogd -f -o cat &

# 10초 후에 메시지 출력
sleep 10

# 로그 파일 업로드 중단 메시지 출력
until [[ ! -z "$USER_CANCEL" ]]; do
    sleep 0.3  # 0.3초 간격으로 메시지 출력
    echo "로그 파일 업로드를 중단하려면 Ctrl+C를 누르세요."
done
