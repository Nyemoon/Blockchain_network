# Bitcoin P2P Regtest — Lab Kathara

Análise do protocolo de transporte Bitcoin P2P em ambiente emulado.  
Protocolo analisado: **Bitcoin P2P** (TCP/18444, modo regtest)  
Modalidade: **B — Emulação com Kathara**

---

## Topologia

```
[server]─────eth0:LAN A─────[client]
10.0.0.1                    10.0.0.2
bitcoind (full node)        bitcoind (peer)
porta P2P: 18444/TCP        porta P2P: 18445/TCP
```

---

## Pré-requisitos

- Docker instalado e em execução
- Kathara instalado (`pip install kathara`)
- Wireshark instalado (para análise das capturas)

```bash
docker --version
kathara --version
```

**Build da imagem customizada (obrigatório, só na primeira vez):**

```bash
docker build -t btc-node .
```

> A imagem instala Bitcoin Core 26.0 (`x86_64`). Em ARM, substitua
> `x86_64-linux-gnu` por `aarch64-linux-gnu` no `Dockerfile`.

---

## Reproduzindo o experimento

### 1. Subir o lab

```bash
kathara lstart
```

Aguarde ~15 segundos para os containers iniciarem.

### 2. Configurar e iniciar o servidor

O `server.startup` pode falhar silenciosamente dependendo da versão do Bitcoin Core.
Inicie o `bitcoind` manualmente caso necessário:

```bash
kathara exec server -- bash -c "cat > /root/.bitcoin/bitcoin.conf << 'CONF'
regtest=1
server=1
debug=net
logips=1

[regtest]
listen=1
bind=10.0.0.1
port=18444
rpcport=18443
rpcuser=btcrpc
rpcpassword=rpcpass123
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
fallbackfee=0.0001
CONF
bitcoind -regtest -conf=/root/.bitcoin/bitcoin.conf -datadir=/root/.bitcoin -daemon"
```

Aguarde 5 segundos e verifique:

```bash
kathara exec server -- bitcoin-cli -regtest getblockchaininfo | grep '"blocks"'
```

Crie a wallet e minere 101 blocos (necessário para maturar o coinbase):

```bash
kathara exec server -- bash -c "bitcoin-cli -regtest createwallet default"
kathara exec server -- bash -c "ADDR=\$(bitcoin-cli -regtest getnewaddress) && bitcoin-cli -regtest generatetoaddress 101 \$ADDR | tail -3"
```

### 3. Configurar e iniciar o cliente

```bash
kathara exec client -- bash -c "cat > /root/.bitcoin/bitcoin.conf << 'CONF'
regtest=1
server=0
dnsseed=0
debug=net
logips=1

[regtest]
port=18445
connect=10.0.0.1:18444
CONF
bitcoind -regtest -conf=/root/.bitcoin/bitcoin.conf -datadir=/root/.bitcoin -daemon"
```

Verifique a conexão P2P:

```bash
sleep 5 && kathara exec server -- bitcoin-cli -regtest getpeerinfo | grep -E '"addr"|"subver"'
```

Deve aparecer `"addr": "10.0.0.2:..."` e `"subver": "/Satoshi:26.0.0/"`.

### 4. Capturar o handshake (Captura 1)

Obtenha o nome do container client:

```bash
docker ps | grep client
```

Inicie o tcpdump em background, reinicie o bitcoind do client para forçar um novo handshake e gere tráfego:

```bash
# Substitua CONTAINER pelo nome obtido acima
CONTAINER=<nome_do_container_client>

docker exec -d $CONTAINER bash -c "tcpdump -i eth0 -w /captures/01_handshake.pcap port 18444"
sleep 2
kathara exec client -- bash -c "kill \$(pidof bitcoind); sleep 4; bitcoind -regtest -conf=/root/.bitcoin/bitcoin.conf -datadir=/root/.bitcoin -daemon"
sleep 8
docker exec $CONTAINER pkill tcpdump
docker cp $CONTAINER:/captures/01_handshake.pcap ./01_handshake.pcap
```

### 5. Capturar propagação de transação (Captura 2)

```bash
docker exec -d $CONTAINER bash -c "tcpdump -i eth0 -w /captures/02_tx.pcap port 18444"
sleep 2
kathara exec server -- bash -c "ADDR=\$(bitcoin-cli -regtest getnewaddress) && bitcoin-cli -regtest sendtoaddress \$ADDR 1.0"
sleep 3
docker exec $CONTAINER pkill tcpdump
docker cp $CONTAINER:/captures/02_tx.pcap ./02_tx.pcap
```

### 6. Capturar propagação de bloco (Captura 3)

```bash
docker exec -d $CONTAINER bash -c "tcpdump -i eth0 -w /captures/03_block.pcap port 18444"
sleep 2
kathara exec server -- bash -c "ADDR=\$(bitcoin-cli -regtest getnewaddress) && bitcoin-cli -regtest generatetoaddress 1 \$ADDR"
sleep 3
docker exec $CONTAINER pkill tcpdump
docker cp $CONTAINER:/captures/03_block.pcap ./03_block.pcap
```

### 7. Analisar no Wireshark

```bash
wireshark 01_handshake.pcap
wireshark 02_tx.pcap
wireshark 03_block.pcap
```

Aplique o filtro `bitcoin` para ver apenas as mensagens de aplicação decodificadas.

### 8. Parar o lab

```bash
kathara lclean
```

---

## Capturas geradas e o que observar

| Arquivo | Conteúdo | Filtro Wireshark |
|---|---|---|
| `01_handshake.pcap` | TCP 3-way handshake + `version` + `verack` | `bitcoin` |
| `02_tx.pcap` | `inv` (TX) → `getdata` → `tx` | `bitcoin` |
| `03_block.pcap` | `inv` (BLOCK) → `getdata` → `block` | `bitcoin` |

---

## Formato de mensagem Bitcoin P2P

```
┌──────────────┬──────────┬──────────────────────────────────────┐
│ Campo        │ Tamanho  │ Descrição                            │
├──────────────┼──────────┼──────────────────────────────────────┤
│ Magic        │ 4 bytes  │ Identifica a rede                    │
│              │          │ regtest: 0xDAB5BFFA                  │
│ Command      │ 12 bytes │ Nome da mensagem (null-padded)       │
│              │          │ ex: "version\x00\x00\x00"            │
│ Length       │ 4 bytes  │ Tamanho do payload (little-endian)   │
│ Checksum     │ 4 bytes  │ SHA256(SHA256(payload))[0:4]         │
│ Payload      │ variável │ Conteúdo específico da mensagem      │
└──────────────┴──────────┴──────────────────────────────────────┘
```

---

## Diagrama de sequência — handshake P2P

```
Client (10.0.0.2)              Server (10.0.0.1)
      │                               │
      │──── TCP SYN ─────────────────>│
      │<─── TCP SYN-ACK ─────────────│
      │──── TCP ACK ─────────────────>│  ← 3-way handshake TCP
      │                               │
      │──── version ─────────────────>│  protocol version, services,
      │                               │  timestamp, user_agent, height
      │<─── version ─────────────────│
      │<─── verack ──────────────────│
      │──── verack ─────────────────>│  ← handshake P2P completo
      │                               │
      │<─── sendheaders ─────────────│
      │<─── sendcmpct ───────────────│  negociação de features
      │──── sendcmpct ──────────────>│
      │<─── ping ────────────────────│
      │──── pong ───────────────────>│
      │<─── getheaders ─────────────│
      │──── headers ────────────────>│
```

---

## Referências

- [Bitcoin P2P Network Protocol](https://en.bitcoin.it/wiki/Protocol_documentation)
- [Bitcoin Core RPC Reference](https://developer.bitcoin.org/reference/rpc/)
- [Wireshark Bitcoin dissector](https://wiki.wireshark.org/Bitcoin)
- [Kathara documentation](https://github.com/KatharaFramework/Kathara)