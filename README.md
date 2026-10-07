# Docker Swarm — Laboratorio

Preparazione di uno **Swarm** con due VM Ubuntu (VirtualBox), installazione di **Docker Engine** e **Portainer**, e un primo test con un servizio replicato.

---

## 1. Presentazione del lavoro

**Obiettivo**: costruire un piccolo cluster Docker Swarm composto da 2 nodi, su due VM Ubuntu 24.04 eseguite in VirtualBox, e metterlo sotto controllo tramite l'interfaccia grafica di Portainer.

**Risultato atteso al termine della lezione**:
- 2 VM Ubuntu (manager + worker) raggiungibili via SSH;
- Docker Engine installato su entrambe;
- cluster Swarm inizializzato con 2 nodi `Ready`;
- Portainer accessibile dal browser a `http://192.168.56.11:9000`;
- un servizio di test (nginx) replicato 3 volte e raggiungibile su `http://192.168.56.11:8080`.

Il deploy dell'applicazione vera e propria verrà affrontato nel **passo successivo** (vedi §14).

---

## 2. Architettura di riferimento

```
                        HOST WINDOWS (VirtualBox)
        ┌──────────────────────────────────────────────┐
        │   browser  →  http://192.168.56.11:9000      │
        │                                  (Portainer) │
        └──────┬───────────────────────────────┬───────┘
               │            host-only          │
        192.168.56.0/24                        │
   ┌─────▼────────────┐          ┌─────────────▼─────────┐
   │   VM1 manager    │  swarm   │   VM2 worker          │
   │   Ubuntu 24.04   │◄────────►│   Ubuntu 24.04        │
   │   192.168.56.11  │  2377    │   192.168.56.12       │
   │   Docker + Porta │  7946    │   Docker              │
   └─────┬────────────┘  4789    └─────────────┬─────────┘
         │ NAT (internet)                      │ NAT (internet)
         └───────────────► apt / docker pull   └──────────────►
```

### Rete delle VM

| Adapter | Tipo | Ruolo |
|---|---|---|
| NIC 1 | **NAT** | accesso a internet (apt, docker pull) |
| NIC 2 | **Host-only** `192.168.56.0/24` | comunicazione tra VM e con l'host |

### Indirizzi

| VM | Hostname | IP host-only |
|---|---|---|
| 1 | `manager` | `192.168.56.11` |
| 2 | `worker` | `192.168.56.12` |

### Porte necessarie

| Porta | Protocollo | Uso |
|---|---|---|
| `22` | TCP | SSH |
| `2377` | TCP | gestione del cluster (Raft) |
| `7946` | TCP + UDP | comunicazione tra nodi (gossip) |
| `4789` | UDP | rete overlay (VXLAN) |
| `9000` | TCP | Portainer (HTTP) |
| `9443` | TCP | Portainer (HTTPS) |
| `8080` | TCP | servizio di test nginx |

---

## 3. Tecnologie spiegate

### 3.1 Docker Engine
Runtime che esegue i container. Con `docker container run ...` lanci un singolo container su un singolo host. Con Swarm i comandi diventano `docker service ...` e `docker stack ...` e il lavoro si distribuisce su più host.

### 3.2 Docker Swarm
Modalità *cluster* nativa di Docker Engine. Permette di gestire più macchine ("nodi") come un'unica piattaforma.

- **Manager**: prendono le decisioni (quorum, almeno 1; idealmente un numero dispari). Un manager *leader* guida il cluster.
- **Worker**: eseguono i container assegnati; non partecipano alle decisioni.
- **Raft (porta 2377)**: protocollo di consenso usato dai manager per mantenere lo stato del cluster.
- **Gossip (7946)**: propagazione delle informazioni tra nodi.
- **Overlay network / VXLAN (4789)**: rete virtuale che unisce i container su nodi diversi.
- **Service / Task**: un `service` è la descrizione di un'applicazione (immagine, repliche, porte); le repliche vengono materializzate in `task` (container) distribuiti sui nodi.
- **Routing mesh (ingress)**: pubblicando una porta su un nodo, la richiesta arriva automaticamente a un container qualsiasi del swarm (vedi §11).

### 3.3 Portainer
Interfaccia grafica per gestire Docker. Con l'installazione "CE + agent" (Community Edition, modalità agent) si gestisce l'intero swarm: nodi, servizi, stack, volumi, reti. UI sulla porta `9000`, HTTPS su `9443`.

### 3.4 VirtualBox — NAT vs Host-only
- **NAT**: la VM va su internet tramite l'host, ma non è raggiungibile da fuori (né dalle altre VM).
- **Host-only**: rete privata tra host e VM (interfaccia `vboxnet0`). Con un IP statico, host e VM si vedono in modo prevedibile. Per lo swarm servono **entrambi**.

### 3.5 Vagrant
Strumento che automatizza la creazione e il provisioning delle VM a partire da un `Vagrantfile`. Opzionale: permette di saltare l'installazione manuale di Ubuntu e Docker (vedi §5.2).

---

## 4. Prerequisiti (host Windows)

- **VirtualBox** 7.x installato (verifica: `vboxmanage --version`)
- **Docker** installato (opzionale, per il passo successivo)
- **Vagrant** installato (opzionale, per il Metodo B): `vagrant --version`
- ~10 GB di spazio su disco libero
- una box Ubuntu 24.04 (Vagrant la scarica da solo la prima volta)

---

## 5. Preparazione dell'host

### 5.1 Creare la rete host-only `192.168.56.0/24`

VirtualBox di solito crea già una interfaccia host-only a default. Per avere una configurazione **deterministica** (stessi IP per tutti i compagni):

1. Apri VirtualBox → menu **File → Tools → Network Manager**.
2. Crea (o modifica) l'interfaccia **Host-only**, nome `vboxnet0`.
3. **IPv4 Adapter**: indirizzo `192.168.56.1`, netmask `255.255.255.0`.
4. **DHCP Server**: disattivalo (gli IP li assegneremo statici).

> Da terminale: `VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0`

---

## 6. Metodo B — Creazione delle VM con Vagrant (consigliato)

La cartella `vagrant/` contiene `Vagrantfile` + script di provisioning, già configurati:
- VM `manager` → `192.168.56.11`
- VM `worker` → `192.168.56.12`
- provisioning che installa Docker Engine + plugin compose su entrambe.

```powershell
# da una shell sulla cartella
cd esercizi/swarm/vagrant

# crea e avvia le due VM (la prima volta scarica la box, ci vuole qualche minuto)
vagrant up

# stato delle VM
vagrant status

# entrare nella VM manager
vagrant ssh manager
# ... e nella VM worker (da un altro terminale, o dopo exit)
vagrant ssh worker
```

Verifica rapida Docker (in entrambe le VM):

```bash
docker --version
docker compose version
```

> Se la box `ubuntu/noble64` desse problemi, cambia in `Vagrantfile` `config.vm.box = "ubuntu/jammy64"` e ripeti `vagrant up`.

> Dalle VM si esce con `exit` (o `logout`).

---

## 7. Metodo A — Creazione delle VM in modalità manuale

Per chi preferisce creare le VM a mano in VirtualBox:

1. **Crea VM** *manager*: Ubuntu 24.04, RAM 2048 MB, CPU 2, disco dinamico 20 GB.
   - NIC1 **NAT**
   - NIC2 **Host-only** `vboxnet0`
2. **Installa Ubuntu Server 24.04** (minimal), utente e password a scelta. Lascia attivo OpenSSH Server al passo "SSH key" della schermata di installazione (o installalo poi con `sudo apt install openssh-server`).
3. **Ripeti** per la VM *worker*.
4. **Assegna gli IP statici** (in ogni VM, adatta il nome della seconda scheda, spesso `enp0s8` — verifica con `ip -br a`):

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.11/24    # .12 sulla VM worker
      routes:
        - to: 192.168.56.0/24
          scope: link
```

```bash
sudo netplan apply
ip -br a          # verifica l'indirizzo 192.168.56.x
```

5. Da PowerShell, SSH per comodità (facoltativo): `ssh utente@192.168.56.11`.

> Se DHCP è rimasto attivo sulla host-only, è sufficiente `ip a` per leggere l'IP assegnato; il valore consigliato è comunque statico per ripetibilità.

---

## 8. Installazione di Docker Engine

> **Nel Metodo B è già fatta** — salta al §9.

Sulle *due* VM, in questa sequenza:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# aggiungi il tuo utente al gruppo docker (valido dopo un nuovo login)
sudo usermod -aG docker $USER
```

Verifica:

```bash
sudo systemctl enable docker --now
sudo systemctl status docker --no-pager
docker --version
```

> Il `docker run hello-world` richiede di rientrare nella sessione (riaprire la shell) per il gruppo `docker`.

**Firewall** (solo se `ufw` è attivo — di default su Ubuntu è disattivato). Su entrambe le VM:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 2377/tcp
sudo ufw allow 7946/tcp
sudo ufw allow 7946/udp
sudo ufw allow 4789/udp
sudo ufw allow 9000/tcp
sudo ufw allow 9443/tcp
sudo ufw allow 8080/tcp
```

---

## 9. Creazione dello Swarm

### 9.1 Inizializza il manager (VM1)

```bash
docker swarm init --advertise-addr 192.168.56.11
```

L'output mostra il token e il comando per far entrare i worker (lo usiamo al punto 9.2). Se perdi il token:

```bash
docker swarm join-token worker
```

### 9.2 Unisci il worker (VM2)

```bash
docker swarm join --token SWMTKN-1-xxxxxxxxx 192.168.56.11:2377
```

### 9.3 Verifica dal manager

```bash
docker node ls
```

Esito atteso: 2 righe con stato `Ready`, ruoli `Leader` (manager) e `Worker`.

### 9.4 Comandi di gestione

```bash
# disconnettere un worker (dal manager)
docker node update --availability drain worker

# togliere un nodo dal cluster (dal worker)
docker swarm leave
# se era anche manager, forzare: docker swarm leave --force
```

---

## 10. Portainer (modalità CE + agent)

Dal **manager**:

```bash
# scarica lo stack di deploy ufficiale (CE con agent)
curl -L https://downloads.portainer.io/ce2-27/portainer-agent-stack.yml -o portainer-agent-stack.yml

# deploy come stack dello swarm
docker stack deploy -c portainer-agent-stack.yml portainer

# stato
docker stack services portainer
docker service ps portainer_portainer
```

Poi nel browser: **http://192.168.56.11:9000** (HTTPS: `https://192.168.56.11:9443`).

Al primo accesso viene chiesto di creare l'**account amministratore** (nome utente + password, min 12 caratteri).

**Cosa è successo**: lo stack ha creato
- `portainer` → UI, vincolata al ruolo manager;
- `portainer-agent` → **global service**, ossia un agente su *ogni* nodo dello swarm, che permette a Portainer di controllare l'intero cluster.

Dopo il login puoi vedere **Environment → local** con entrambi i nodi (o almeno, dai servizi e log, l'intero swarm). Esplora le viste *Stacks*, *Services*, *Nodes*, *Volumes*, *Networks*.

---

## 11. Mini-test: servizio replicato con nginx

Verifichiamo che lo swarm distribuisca davvero i container sui nodi.

Dal **manager**:

```bash
# servizio con 3 repliche, porta pubblicata 8080
docker service create --name test-web --replicas 3 \
  --publish published=8080,target=80 \
  nginx:alpine

# stato del servizio
docker service ls
docker service ps test-web        # su quali nodi sono finite le repliche?
docker service inspect test-web   # dettagli

# test di funzionamento
curl http://192.168.56.11:8080
curl http://192.168.56.12:8080    # funziona pure dal worker: routing mesh!
```

Entrambe le `curl` rispondono: la porta `8080` è pubblicata sulla **mesh ingress**, quindi qualunque nodo ospita il servizio risponde, indipendentemente da dove gira il container.

Esercizi rapidi:

```bash
docker service scale test-web=5   # porta le repliche a 5
docker service scale test-web=2   # e poi a 2
docker service ls
```

Per la gestione dal browser: Portainer → **Stacks / Services** → `test-web` → scale direttamente dall'interfaccia.

Pulizia a fine test:

```bash
docker service rm test-web
```

---

## 12. Verifiche e troubleshooting

| Sintomo | Causa probabile | Rimedio |
|---|---|---|
| `docker node ls` mostra `Down`  | VM spenta o rete host-only non configurata | accendere la VM; verificare NIC2 e `ip -br a` |
| il join dà `timeout`  | porta 2377 bloccata / IP sbagliato | controllare `ufw` (§8) e `--advertise-addr` (§9.1) |
| i container overlay non si parlano  | porta 4789 UDP bloccata o modulo overlay mancante | aprirla in `ufw`; controllare `lsmod \| grep overlay` |
| Portainer non si apre  | stack non ancora pronto / porta 9000 chiusa | `docker stack services portainer`; `docker service ps portainer_portainer` |
| hello-world dà "permission denied"  | utente non nel gruppo docker | rieseguire `sudo usermod -aG docker $USER` e rientrare nella shell |

---

## 13. Comandi riassuntivi

| Comando | Descrizione |
|---|---|
| `docker swarm init --advertise-addr IP` | inizializza il cluster (nodo manager) |
| `docker swarm join-token worker` | mostra token di ingresso |
| `docker swarm join --token ... IP:2377` | fa entrare un worker |
| `docker node ls` | elenco nodi e stato |
| `docker service create --replicas N --publish p:p img` | crea un servizio replicato |
| `docker service ls / ps / scale / rm` | gestione dei servizi |
| `docker stack deploy -c file.yml nome` | deploy di uno stack (multi-servizio) |
| `docker stack ls / services / rm` | gestione degli stack |

---

## 14. Prossimo step — deploy dell'applicazione

Il materiale della Fase 2 è pronto nella cartella **`app/`**: contiene lo stack ufficiale dell'**Example Voting App** (`docker-stack.yml`) e un README con esercizi di scaling, failover e verifica delle reti.

In preparazione si può già pensare a:
- come passa da un deploy `docker compose` a uno stack Swarm (`deploy: replicas`, overlay network);
- cos'è un **volume condiviso** (`--mount type=volume ...`) e perché conviene ancorare le parti stateful a un nodo;
- come gestire i **secret** in Swarm (`docker secret`).

---

## 15. Riferimenti

- Docker docs — Swarm: https://docs.docker.com/engine/swarm/
- Docker docs — Swarm services: https://docs.docker.com/engine/reference/commandline/swarm_init/
- Portainer CE: https://docs.portainer.io/start/install-ce/server/swarm/linux
- Vagrant: https://developer.hashicorp.com/vagrant/docs