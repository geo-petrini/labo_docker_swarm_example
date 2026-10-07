# FASE 2 — Deploy di un'applicazione multi-servizio sullo Swarm

Usiamo l'**Example Voting App** (esempio storico di Docker per i demo) per vedere una vera applicazione distribuita su Swarm, fatta di **5 servizi interconnessi**, e per **dimostrare il beneficio dello scaling**.

## 1. Obiettivo e risultato atteso

- fare il deploy di uno **stack multi-servizio** con un solo comando;
- mostrare le **overlay network** che collegano servizi su nodi diversi;
- giocare con `docker service scale` e vedere **in tempo reale** il vantaggio di scalare il worker;
- osservare come Swarm sposta i container tra i 2 nodi (repliche, drain, failover).

Risultato atteso:
- `http://192.168.56.11:8080` → pagina di **voto** (cats vs dogs);
- `http://192.168.56.11:8081` → pagina dei **risultati in tempo reale**.

## 2. Architettura dell'app

```
                        rete overlay "frontend"
        ┌──────────────────────────────────────────────┐
        │                                              │
        │   vote ──────────► redis ───────┐            │
        │  (Python, web)      (coda)       │            │
        └──────────────────────────────────┼────────────┘
                                           ▼
                                 ┌──────────────┐        rete overlay "backend"
                                 │    worker    │        ┌───────────────────────────────┐
                                 │  (.NET, CPU) │        │                               │
                                 └──────┬───────┘        │                               │
                                        └───────────────►│   db ───► result              │
                                           (PostgreSQL)  │ (Postgres, volume)  (Node web)│
                                                         └───────────────────────────────┘
```

- **vote** (Python) → frontend per l'utente, scrive il voto su **Redis**;
- **worker** (.NET) → consuma la coda Redis e salva il voto in **PostgreSQL**;
- **result** (Node) → legge PostgreSQL e aggiorna i risultati sul browser;
- **db** (Postgres) → unica parte **stateful**, con volume `db-data`.

Il worker è **CPU-bound**: più worker girano in parallelo, più voti vengono elaborati al secondo. È il punto perfetto per vedere lo scaling.

## 3. Tecnologie richiamate

- **overlay network** (`frontend`, `backend`): reti virtuali che attraversano i nodi dello swarm; il servizio `worker` è su entrambe.
- **ingress / routing mesh**: la porta pubblicata (`8080`, `8081`) è gestita dallo swarm: qualunque nodo risponde, anche se il container gira su un altro nodo.
- **replicas**: il numero di task (container) per servizio. Swarm li distribuisce in modo "spread" sui nodi.
- **volume**: `db-data` è condiviso a livello di nodo → il `db` va tenuto ancorato a un nodo (vincolo, vedi stack commentato).
- **restart policy / update_config**: come Swarm riavvia i task che falliscono e rolla gli aggiornamenti (esempi commentati in `docker-stack.yml`).

## 4. Deploy dello stack

Tutto dal **manager** (VM1).

```bash
# entra nella cartella del progetto (su git clone o copia manuale)
cd ~/app              # o la cartella dove hai messo docker-stack.yml

# deploy dello stack chiamato "vote"
docker stack deploy -c docker-stack.yml vote
```

Verifica:

```bash
docker stack ls                 # elenco stack
docker stack services vote      # servizi dello stack e repliche
docker service ps vote_vote     # dove sono stati piazzati i task "vote"
docker service ps vote_worker   # e i worker
docker service ps vote_result
```

`docker service ps` mostra **su quale nodo** (`Node`) gira ogni task: con 2 repliche su 2 nodi Swarm piazzerà tipicamente un task per nodo.

Apri nel browser:
- **http://192.168.56.11:8080** → vota (cats o dogs);
- **http://192.168.56.11:8081** → guarda i risultati aggiornarsi.

> Riprova aprire `:8080` anche da `192.168.56.12`: funziona identico → è il **routing mesh** (ingress).

## 5. Esercizi di scaling

### 5.1 Scalare il frontend (vote)

```bash
docker service scale vote_vote=4
docker service ls
docker service ps vote_vote
```

Ora ci sono 4 task `vote` distribuiti sui 2 nodi: più istanze in grado di accettare voti.

### 5.2 Scalare il worker — IL punto dell'esercizio

```bash
# parte da 2
docker service scale vote_worker=6
docker service ls
```

Vota **rapidamente diverse volte** e guarda la pagina dei risultati: la coda Redis viene svuotata molto più velocemente. Scalando di nuovo:

```bash
docker service scale vote_worker=1
```

I risultati "rallentano". È la dimostrazione diretta del **beneficio dello scaling orizzontale**.

### 5.3 Pulire le repliche extra (facoltativo, per tornare alla configurazione base)

```bash
docker service scale vote_vote=2
docker service scale vote_worker=2
```

## 6. Ridondanza e failover (drain)

Dal **manager**:

```bash
# metti il nodo worker in modalità "drain": nessun task viene piazzato lì
docker node update --availability drain worker

# i task che giravano sul worker vengono rischedulati altrove (manager)
docker service ps vote_vote
docker service ps vote_worker

# riattiva il nodo
docker node update --availability active worker
```

Osservazione: i task **non si fermano**: Swarm li riconcilia sui nodi disponibili.

## 7. Reti, volumi e interni

```bash
docker network ls                       # le reti dello stack: vote_frontend, vote_backend
docker network inspect vote_frontend    # quali servizi sono collegati

docker volume ls                        # il volume db-data
docker stack services vote --format "table {{.Name}}\t{{.Replicas}}"
docker service inspect vote_worker      # dettagli (immagini, networks, restart policy)
```

## 8. Vincolo: ancorare il DB al manager

Il volume `db-data` esiste sul nodo dove è finito il task `db`. Su un cluster di laboratorio è comodo **vincolare** il DB al manager. Nello stack commentato c'è la riga:

```yaml
db:
  deploy:
    placement:
      constraints: [node.role == manager]
```

Da applicare modificando `docker-stack.yml` e ridistribuendo:

```bash
docker stack deploy -c docker-stack.yml vote
```

## 9. Pulizia

```bash
docker stack rm vote        # rimuove servizi, reti, ingress (i volumi restano)
docker volume rm vote_db-data   # rimuove anche il volume (se vuoi azzerare i dati)
```

## 10. Troubleshooting

| Sintomo | Causa | Rimedio |
|---|---|---|
| `:8080` non risponde | stack non pronto / ingress ancora in avvio | `docker stack services vote`, `docker service ps vote_vote` |
| task in stato `Pending` | Swarm non trova le risorse o non riesce a scaricare l'immagine | `docker service ps vote_vote` per l'errore; verificare rete/registro col `docker service logs` |
| worker usa 100% CPU su un nodo | 6 repliche concentrate su 1 nodo | `docker node ls`; valutare un terzo nodo o meno repliche |
| i risultati non aggiornano | coda Redis piena e worker lenti | scalare `vote_worker`; controllare `docker service logs vote_worker` |

## 11. Comandi riassuntivi

| Comando | Descrizione |
|---|---|
| `docker stack deploy -c docker-stack.yml vote` | deploy dello stack |
| `docker stack ls / services vote` | stato dello stack |
| `docker service ls` | tutti i servizi del cluster |
| `docker service ps vote_worker` | task di un servizio e nodi |
| `docker service scale vote_worker=6` | scaling orizzontale |
| `docker node update --availability drain worker` | failover verso altri nodi |
| `docker network inspect vote_frontend` | dettagli overlay |
| `docker stack rm vote` | rimozione |

## 12. Sitografia

- Example Voting App (sorgente ufficiale): https://github.com/dockersamples/example-voting-app
- Docker docs — Swarm overview: https://docs.docker.com/engine/swarm/
- Docker docs — Deploy services to a swarm: https://docs.docker.com/engine/swarm/services/
- Docker docs — How services work (task/replicas): https://docs.docker.com/engine/swarm/how-swarm-mode-works/services/
- Docker docs — Stack deploy reference: https://docs.docker.com/reference/cli/docker/stack/deploy/
- Docker docs — service scale: https://docs.docker.com/reference/cli/docker/service/scale/
- Docker docs — node update (drain): https://docs.docker.com/reference/cli/docker/node/update/
- Docker docs — Overlay network driver: https://docs.docker.com/network/overlay/
- Docker docs — Placement constraints: https://docs.docker.com/engine/swarm/services/#control-service-placement
- Redis (image ufficiale): https://hub.docker.com/_/redis
- Postgres (image ufficiale): https://hub.docker.com/_/postgres