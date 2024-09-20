#!/bin/bash
set -e

# Impostazioni per la connessione SSH
remote_host="eva.cs.unibo.it"

# Chiedi all'utente di inserire il suo username Unibo
printf "Inserisci il tuo username Unibo: "
read remote_user

# Controlla se esiste una chiave SSH, altrimenti la genera
if [ ! -f ~/.ssh/id_rsa ]; then
    printf "Nessuna chiave SSH trovata. Generazione di una nuova chiave...\n"
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
    printf "Nuova chiave SSH generata.\n"
else
    printf "Chiave SSH esistente trovata.\n"
fi

# Funzione per gestire authorized_keys e pulizia cache
handle_remote_setup() {
    printf "Gestione di authorized_keys e pulizia cache...\n"
    ssh -T "$remote_user@$remote_host" 'bash -s' << EOF
    # Pulizia della cache
    find ~/.cache -type f -delete 2>/dev/null || true
    
    # Verifica dello spazio utilizzato
    used_space=\$(du -sm ~ | cut -f1)
    printf "Spazio utilizzato: %sM\n" "\$used_space"
    if [ \$used_space -ge 409 ]; then
        printf "Superato il limite di 409M.\nFile più grandi nella home:\n"
        find ~ -type f -printf '%s %p\n' | sort -rn | head -10 | awk '{ printf "%.1fMB %s\n", \$1/1048576, \$2 }'
    fi

    # Gestione di authorized_keys
    if [ ! -f ~/.ssh/authorized_keys ]; then
        mkdir -p ~/.ssh
        touch ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        printf "File authorized_keys creato.\n"
    fi
    
    # Aggiunta della chiave pubblica
    if ! grep -q "$(cat ~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys; then
        if cat >> ~/.ssh/authorized_keys << EOK
$(cat ~/.ssh/id_rsa.pub)
EOK
        then
            printf "Nuova chiave pubblica aggiunta a authorized_keys.\n"
        else
            printf "Errore: Impossibile aggiungere la chiave.\n"
        fi
    else
        printf "La chiave pubblica è già presente in authorized_keys.\n"
    fi
EOF
}

# Esegui la configurazione remota
handle_remote_setup

# Verifica la connessione SSH
printf "Verifica della connessione SSH...\n"
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_user@$remote_host" true; then
    printf "Connessione SSH stabilita con successo.\n"
else
    printf "Errore: Impossibile stabilire una connessione SSH. Verifica la configurazione e riprova.\n"
    exit 1
fi

# Crea la cartella remota e imposta i permessi
printf "Verifica e creazione delle cartelle remote...\n"
ssh -T "$remote_user@$remote_host" 'bash -s' << EOF
    folders=("/public/$remote_user" "/public/$remote_user/.vscode-server" "/public/$remote_user/.vscode-server-insiders")
    for folder in "\${folders[@]}"; do
        if [ -d "\$folder" ]; then
            printf "La cartella %s esiste già.\n" "\$folder"
        else
            mkdir -p "\$folder"
            printf "La cartella %s è stata creata.\n" "\$folder"
        fi
    done
    chmod 700 /public/$remote_user
    printf "Permessi impostati per /public/$remote_user\n"
EOF

printf "Verifica e creazione delle cartelle remote completata per l'utente %s.\n" "$remote_user"

# Chiedi all'utente se vuole aprire VSCode
printf "Vuoi aprire Visual Studio Code? (s/n): "
read open_vscode

if [[ $open_vscode == "s" || $open_vscode == "S" ]]; then
    printf "Quale versione di Visual Studio Code vuoi usare?\n1) VSCode\n2) VSCode Insiders\nInserisci il numero della tua scelta (1 o 2): "
    read choice

    case $choice in
        1) vscode_command="code";;
        2) vscode_command="code-insiders";;
        *) printf "Scelta non valida. Uso VSCode normale.\n"; vscode_command="code";;
    esac

    printf "Avvio di %s con connessione remota...\n" "$vscode_command"
    
    # Apri VSCode localmente con connessione remota
    "$vscode_command" --remote ssh-remote+"$remote_user@$remote_host" &
    
    printf "Visual Studio Code (%s) è stato avviato localmente con connessione remota a %s@%s\n" "$vscode_command" "$remote_user" "$remote_host"
else
    printf "Operazione completata. Non è stato avviato Visual Studio Code.\n"
fi