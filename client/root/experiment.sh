#!/bin/bash
# experiment.sh — roda DENTRO do container client após o lab subir
# Gera as 3 capturas .pcap anotadas exigidas pelo rubric
#
# Uso: kathara exec client -- bash /root/experiment.sh

set -euo pipefail

BTC_SERVER="10.0.0.1"
BTC_CLI="bitcoin-cli -regtest"
CAPTURE_DIR="/captures"

log() { echo "[experiment] $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# CAPTURA 1: já foi iniciada no client.startup (01_handshake.pcap)
# Aguarda conexão P2P ser estabelecida
# ─────────────────────────────────────────────────────────────────────────────
log "Aguardando conexão P2P com server..."
for i in $(seq 1 20); do
    PEERS=$($BTC_CLI getpeerinfo 2>/dev/null | grep -c '"id"' || echo 0)
    if [ "$PEERS" -gt 0 ]; then
        log "Conectado a $PEERS peer(s)."
        break
    fi
    sleep 2
done

# Encerra captura 1 (handshake já completo)
TCPDUMP_PID=$(cat /root/tcpdump.pid 2>/dev/null | grep -oP '(?<=TCPDUMP_PID=)\d+' || true)
if [ -n "$TCPDUMP_PID" ]; then
    kill "$TCPDUMP_PID" 2>/dev/null || true
    sleep 1
fi
log "Captura 01_handshake.pcap encerrada (TCP 3-way + version/verack)"

# ─────────────────────────────────────────────────────────────────────────────
# CAPTURA 2: propagação de transação (inv → getdata → tx)
# ─────────────────────────────────────────────────────────────────────────────
log "Iniciando captura 02_tx_propagation.pcap..."
tcpdump -i eth0 -w "$CAPTURE_DIR/02_tx_propagation.pcap" port 18444 &
TC2_PID=$!

sleep 1

# Cria wallet no server (se não existir) e envia transação
log "Criando transação no server via RPC..."
# Executa RPC no server (precisa de um canal — usamos o bitcoin-cli do próprio client com -rpcconnect NÃO é possível sem credenciais no client)
# Alternativa limpa: gerar tx usando o servidor via kathara exec
log ">> Rode no terminal HOST: kathara exec server -- bitcoin-cli -regtest sendtoaddress \$(bitcoin-cli -regtest getnewaddress) 1.0"
log "   Depois pressione ENTER aqui para encerrar a captura 2."
read -r

kill $TC2_PID 2>/dev/null || true
sleep 1
log "Captura 02_tx_propagation.pcap encerrada"

# ─────────────────────────────────────────────────────────────────────────────
# CAPTURA 3: propagação de bloco (inv → getdata → block)
# ─────────────────────────────────────────────────────────────────────────────
log "Iniciando captura 03_block_propagation.pcap..."
tcpdump -i eth0 -w "$CAPTURE_DIR/03_block_propagation.pcap" port 18444 &
TC3_PID=$!

sleep 1

log ">> Rode no terminal HOST: kathara exec server -- bitcoin-cli -regtest generatetoaddress 1 \$(bitcoin-cli -regtest getnewaddress)"
log "   Depois pressione ENTER aqui para encerrar a captura 3."
read -r

kill $TC3_PID 2>/dev/null || true
sleep 1
log "Captura 03_block_propagation.pcap encerrada"

# ─────────────────────────────────────────────────────────────────────────────
# Status final
# ─────────────────────────────────────────────────────────────────────────────
log "Capturas geradas em $CAPTURE_DIR:"
ls -lh "$CAPTURE_DIR"/*.pcap 2>/dev/null || log "Nenhum .pcap encontrado — verifique se o tcpdump capturou tráfego."

log "Para copiar para o host:"
log "  kathara exec client -- cat /captures/01_handshake.pcap > 01_handshake.pcap"
log "  kathara exec client -- cat /captures/02_tx_propagation.pcap > 02_tx_propagation.pcap"
log "  kathara exec client -- cat /captures/03_block_propagation.pcap > 03_block_propagation.pcap"
