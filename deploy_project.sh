#!/bin/bash
set -e

remote_host="eva.cs.unibo.it"

# Funzione per verificare lo spazio disponibile e mostrare i file più grandi
check_space() {
    ssh -T "$remote_user@$remote_host" 'bash -s' << EOF
    used_space=\$(du -sm ~ | cut -f1)
    printf "Spazio utilizzato: %sM\n" "\$used_space"
    if [ \$used_space -ge 409 ]; then
        printf "Attenzione: Superato il limite di 409M.\nFile più grandi nella home:\n"
        find ~ -type f -printf '%s %p\n' | sort -rn | head -10 | awk '{ printf "%.1fMB %s\n", \$1/1048576, \$2 }'
        exit 1
    fi
EOF
}

# Funzione per gestire authorized_keys
handle_authorized_keys() {
    ssh -T "$remote_user@$remote_host" 'bash -s' << EOF
    if [ ! -f ~/.ssh/authorized_keys ]; then
        mkdir -p ~/.ssh
        touch ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        printf "File authorized_keys creato.\n"
    fi
    
    if ! grep -q "$(cat ~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys; then
        if cat >> ~/.ssh/authorized_keys << EOK
$(cat ~/.ssh/id_rsa.pub)
EOK
        then
            printf "Nuova chiave pubblica aggiunta a authorized_keys.\n"
        else
            printf "Errore: Impossibile aggiungere la chiave.\n"
            exit 1
        fi
    else
        printf "La chiave pubblica è già presente in authorized_keys.\n"
    fi
EOF
}

# Funzione per ottenere e selezionare il sito dell'utente
get_user_site() {
    local sites=($(ssh "$remote_user@$remote_host" "getent group | grep $remote_user | grep '^site' | cut -d: -f1"))
    local num_sites=${#sites[@]}

    if [ $num_sites -eq 0 ]; then
        echo "Nessun sito trovato per l'utente."
        exit 1
    elif [ $num_sites -eq 1 ]; then
        echo "${sites[0]}"
    else
        local default_site=$(printf '%s\n' "${sites[@]}" | sort -n | tail -n1)
        # printf "Trovati multipli siti. Seleziona il sito da utilizzare:\n"
        select site in "${sites[@]}"; do
            if [ -n "$site" ]; then
                echo "$site"
                return
            fi
        done < /dev/tty
    fi
}

# Funzione per fermare il docker
stop_docker() {
    local site=$1

    # Richiedi la password per gocker
    read -s -p "Inserisci la password per gocker: " password
    echo

    # Usa SSH per connettersi a eva e poi a gocker, forzando l'uso della password
    ssh -t "$remote_user@$remote_host" << EOF
        ssh -tt -o PreferredAuthentications=password -o PubkeyAuthentication=no gocker "stop $site"
EOG
EOF
}

# Chiedi username
printf "Inserisci il tuo username Unibo: "
read remote_user

# Chiedi il percorso del progetto locale
printf "Inserisci il percorso del progetto locale (ad es. /path/to/project): "
read local_project_path

# Controlla se la path inserita esiste
if [ ! -d "$local_project_path" ]; then
    printf "Errore: il percorso del progetto non esiste.\n"
    exit 1
fi

# Ottieni il sito dell'utente
site=$(get_user_site)

printf "Utilizzo del sito: %s\n" "$site"

# Verifica la chiave SSH e copiala se necessario
if [ ! -f ~/.ssh/id_rsa ]; then
    printf "Nessuna chiave SSH trovata. Generazione di una nuova chiave...\n"
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
    printf "Nuova chiave SSH generata.\n"
fi

# Gestione di authorized_keys
handle_authorized_keys

# Verifica la connessione SSH
printf "Verifica della connessione SSH...\n"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_user@$remote_host" true; then
    printf "Errore: Impossibile stabilire una connessione SSH. Verifica la configurazione e riprova.\n"
    exit 1
fi

# Verifica lo spazio disponibile
if ! check_space; then
    printf "Spazio insufficiente sul server remoto. Libera spazio e riprova.\n"
    exit 1
fi

# Comprimi l'intero progetto
printf "Compressione dell'intero progetto...\n"

# Controlla se il file esiste già
if [ -f project.tar.gz ]; then
    printf "Il file project.tar.gz esiste già. Viene eliminato e ricreato.\n"
    rm project.tar.gz
fi

# Crea il file compresso
tar czf project.tar.gz -C "$local_project_path" .

# Crea la cartella remota e imposta i permessi
printf "Verifica e creazione delle cartelle remote...\n"
ssh -T "$remote_user@$remote_host" 'bash -s' << EOF
    folders=("/public/$remote_user" "/public/$remote_user/tmp")
    for folder in "\${folders[@]}"; do
        if [ -d "\$folder" ]; then
            printf "La cartella %s esiste già.\n" "\$folder"
        else
            mkdir -p "\$folder"
            printf "La cartella %s è stata creata.\n"
        fi
    done
    chmod 700 /public/$remote_user
    printf "Permessi impostati per /public/$remote_user\n"
EOF

printf "Verifica e creazione delle cartelle remote completata per l'utente %s.\n" "$remote_user"

# Trasferisci il file compresso
printf "Trasferimento del progetto compresso...\n"
scp project.tar.gz "$remote_user@$remote_host:/public/$remote_user/tmp/"

# Decomprimi, sostituisci i file e imposta i permessi sul server remoto
printf "Decompressione, sostituzione dei file e impostazione dei permessi sul server remoto...\n"
ssh -v -T "$remote_user@$remote_host" << EOF
    rm -rf "/home/web/$site/html/*"

    cd "/public/$remote_user/tmp"
    tar xzvf project.tar.gz -C "/home/web/$site/html/"

    chmod -R g+rwX "/home/web/$site/html"
    
    chmod g+s "/home/web/$site/html"
    
    rm -rf /public/$remote_user/tmp/*

EOF

printf "Procedura di deploy completata con successo.\n"
printf "Permessi impostati correttamente per il gruppo.\n"
printf "Ricorda di riavviare il docker manualmente se necessario.\n"

