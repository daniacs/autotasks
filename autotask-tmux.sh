#!/bin/bash 
# Automatizador de tarefas e conexoes SSH
# As senhas sao mantidas em arquivos criptografados pelo utilizador
# Os arquivos criptografados ficam em uma "carteira" (diretorio wallet)
# Outra pessoa nao deveria conseguir descriptografar

# Ajuda logo abaixo ;)
function help_wallet {
  cat <<EOF

O diretorio \$WALLET_DIR contem os arquivos criptografados das senhas
que estao nos arquivos xxxxx.raw.gpg
So quem tem a senha da chave GPG que criptografou os arquivos possui
acesso ao conteudo dos arquivos em texto plano.

Para ter uma "wallet" funcional:
1) Gerar a chave GPG
   gpg --generate-key

2) Gerar os arquivos .raw com as senhas em texto plano

3) Os arquivos .raw devem ser criptografados com 
   gpg --multifile --encrypt --recipient <EMAIL_CHAVE_GPG> *

4) Documentar num arquivo README que senha eh cada um dos arquivos

5) Remover todos os arquivos .raw e deixar os .gpg
A keygrip deve ser a da "subchave" e pode ser consultada com
gpg --list-keys --with-keygrip

6) Zipar o diretorio wallet
zip -r wallet.zip wallet/

7) Criptografar tambem o arquivo zip!
gpg --encrypt --recipient <EMAIL_CHAVE_GPG> wallet.zip
EOF
}

# Variaveis do Oracle
export ORACLE_HOME=/usr/lib/oracle/11.2/client64
export LD_LIBRARY_PATH=/usr/lib/oracle/11.2/client64/lib/

# Informacoes da chave GPG utilizada para criptografar os arquivos
# gpg --list-keys --with-keygrip (keygrip da subkey e nao da master)
export KEYGRIP=FCDC13183F8B6152FB441C0F7112CC50A35AC861
export RECIPIENT=daniel.andrade@almg.gov.br

# Binarios do GPG
export GPG_CONN_AGENT=/usr/bin/gpg-connect-agent
export GPG_PRESET=/usr/lib/gnupg2/gpg-preset-passphrase

# $WORKDIR/$WALLET_NAME.zip.gpg 
#  --> $WORKDIR/$WALLET_NAME.zip 
#   --> $WORKDIR/$WALLET_NAME  (diretorio com os arquivos de senha)
export WORKDIR=$HOME/Documents
export WALLET_NAME=wallet
export WALLET_DIR=$WORKDIR/$WALLET_NAME

# Arquivo de configuracao do gpg
export GPG_CONF=$HOME/.gnupg/gpg-agent.conf

# Montar os diretorios necessarios pra trabalhar
# //miranda/homes  /mnt/mail cifs  credentials=/home/m23360/.smbcred,domain=REDE,vers=1.0,noauto,rw,users 0 0
# Precisa do ~/.smbcred
function monta_diretorios {
  mount /mnt/alfresco
  mount /mnt/GTI-GTec
  mount /mnt/install
  mount /mnt/temp
  sleep 1
}

# Verifica se a KEYGRIP ta com a senha em cache
function senha_em_cache {
  echo "KEYINFO $KEYGRIP" | $GPG_CONN_AGENT | grep '1 P'
  RET=$?
  return $RET
}

# Coloca a senha em cache e verifica se a senha esta correta
function atualiza_cache {
  sed -i 's/^/#/' $GPG_CONF
  cat <<EOF >>$GPG_CONF
  pinentry-program /usr/bin/pinentry-tty
  pinentry-timeout 1
  allow-preset-passphrase
EOF
  $GPG_CONN_AGENT RELOADAGENT /bye

  printf "Digite a senha da chave GPG: "
  read -s SENHA
  echo $SENHA | $GPG_PRESET --verbose --preset $KEYGRIP
  unset SENHA
  # Verificar se a chave inserida na cache eh a correta
  # Se o decrypt der erro, eh porque a senha esta errada
  FRASE="Issoehumteste"
  tmp=`mktemp`
  echo $FRASE > $tmp
  gpg --encrypt --recipient $RECIPIENT $tmp
  gpg --decrypt --output $tmp.out $tmp.gpg 2>/dev/null
  RET=$?
  rm -f $tmp $tmp.gpg $tmp.out
  sed -i '/^[^#]/d; s/^#//' $GPG_CONF
  return $RET
}


function abre_carteira {
  cd $WORKDIR
  if ! [ -f $WALLET_NAME.zip.gpg ]; then
    echo "O arquivo $WALLET_NAME.zip.gpg nao existe. Abortando"
    return 1
  fi
  gpg --output $WALLET_NAME.zip --decrypt $WALLET_NAME.zip.gpg
  unzip $WALLET_NAME.zip
  rm -f $WALLET_NAME.zip
}

function fecha_carteira {
  rm -rf $WORKDIR/$WALLET_NAME
}

function erro_carteira {
  echo Houve um erro com a senha GPG.
  echo Se nao lembra a senha, crie outra chave com gpg --generate-key
  help_wallet
  $GPG_CONN_AGENT RELOADAGENT /bye
}

function tmux_oracle_enterprise {
  cached=`senha_em_cache`
  if [ $? -ne 0 ]; then
    atualiza_cache
    RET=$?
    if [ $RET -ne 0 ]; then
      erro_carteira
      exit
    fi
  fi
  ORAENTPW="SENHA DO ORACLE ENTERPRISE"
  abre_carteira
  tmux new-session -s ORAENT -d -n ORAT
  tmux send-keys 'ssh root@orat' C-m
  sleep 0.8
  tmux send-keys $ORAENTPW C-m
  tmux split-window -c $HOME -v 'ssh root@orat'
  sleep 0.5
  tmux send-keys $ORAENTPW C-m
  tmux split-window -c $HOME -h -f 'ssh root@orastandard'
  sleep 0.5
  tmux send-keys $ORAENTPW C-m
  tmux split-window -c $HOME -v 'ssh root@orastandard'
  sleep 0.5
  tmux send-keys $ORAENTPW C-m
  fecha_carteira
}


# Cada sessao ssh eh uma janela diferente
function tmux_postgres_ssh {
  cached=`senha_em_cache`
  if [ $? -ne 0 ]; then
    atualiza_cache
    RET=$?
    if [ $RET -ne 0 ]; then
      erro_carteira
      exit
    fi
  fi
  abre_carteira
  tmux new-session -s PGSSH -d -n PG_DEV
  tmux send-keys 'ssh root@postgresql-dev1' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwprinsrval.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour22' -T DEV
  tmux split-window -c $HOME -h
  tmux send-keys 'ssh root@postgresql-dev1' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwprinsrval.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour22' -T DEV
  sleep 0.5
  tmux rename-window PG_DEV

  tmux new-window -c $HOME -n PG_HMG
  tmux send-keys 'ssh root@postgresql1h' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwprinsrval.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour18'
  tmux split-window -c $HOME -h
  tmux send-keys 'ssh root@postgresql1h' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwprinsrval.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour18' -T HMG
  sleep 0.5
  tmux rename-window PG_HMG

  tmux new-window -c $HOME -n PG_PROD
  tmux send-keys 'ssh root@postgresql01' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwprinsrval.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour52'
  tmux split-window -c $HOME -h
  tmux send-keys 'ssh root@postgresql01' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwprinsrval.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour52' -T PROD
  sleep 0.5
  tmux rename-window PG_PROD

  fecha_carteira
}

# Cada sessao ssh eh uma janela diferente
function tmux_oracle_ssh {
  cached=`senha_em_cache`
  if [ $? -ne 0 ]; then
    atualiza_cache
    RET=$?
    if [ $RET -ne 0 ]; then
      erro_carteira
      exit
    fi
  fi
  abre_carteira
  tmux new-session -s ORASSH -d -n DESENVOLVIMENTO
  tmux send-keys 'ssh oracle@desoracle' C-m
  sleep 1
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwdhpelcaro.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour22'

  tmux new-window -c $HOME -n HOMOLOGAÇÃO
  tmux send-keys 'ssh oracle@homoloracle' C-m
  sleep 1
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwdhpelcaro.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour18'
  tmux split-window -c $HOME -h
  tmux send-keys 'ssh root@homoloracle' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwdhpelcaro.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour18' -T HMG
  sleep 0.5

  tmux new-window -c $HOME -n PRODUÇÃO
  tmux send-keys 'ssh oracle@oracle-rac1' C-m
  sleep 1
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwdhpelcaro.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour52' -T PRD
  tmux split-window -c $HOME -h
  tmux send-keys 'ssh root@oracle-rac1' C-m
  sleep 0.5
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/pwdhpelcaro.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour52' -T PRD
  sleep 0.5
  fecha_carteira
}

# Cada sessao oracle eh um "pane" diferente
function tmux_oracle_db {
  cached=`senha_em_cache`
  if [ $? -ne 0 ]; then
    atualiza_cache
    RET=$?
    if [ $RET -ne 0 ]; then
      erro_carteira
      exit
    fi
  fi
  abre_carteira
  tmux new-session -c $HOME -s ORADB -d 

  tmux send-keys '/usr/bin/sqlplus64 alemg@D10' C-m
  sleep 1
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/alemgdesoracle.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour22'
  tmux send-keys -l 'SELECT HOST_NAME FROM V$INSTANCE\;'
  tmux send-keys C-m

  tmux split-window -c $HOME -h
  tmux send-keys '/usr/bin/sqlplus64 abd7@H11' C-m
  sleep 1
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/abd7homoloracle.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour18'
  tmux send-keys -l 'SELECT HOST_NAME FROM V$INSTANCE\;'
  tmux send-keys C-m

  tmux split-window -c $HOME -h
  tmux send-keys '/usr/bin/sqlplus64 abd7@P10' C-m
  sleep 1
  tmux send-keys `gpg --decrypt --quiet $WALLET_DIR/abd7homoloracle.raw.gpg` C-m
  tmux select-pane -P 'fg=white,bg=colour52'
  tmux send-keys -l 'SELECT HOST_NAME FROM V$INSTANCE\;'
  tmux send-keys C-m

  tmux select-layout even-horizontal
  fecha_carteira
}

function inicia_tudo {
  /usr/bin/google-chrome-stable &
  /usr/bin/thunderbird &
  /home/m23360/Downloads/dbeaver/dbeaver &
  /usr/bin/libreoffice /home/m23360/Documents/Dropbox/Documentos/empresas/04-ALMG/1-controle/atividades-diarias-2019-2.ods &
  if VBoxManage showvminfo win10 | grep ^State | grep "powered off"; then
    VBoxManage startvm win10 --type gui &
  fi
}


#monta_diretorios
#inicia_tudo
#tmux_oracle_db
#tmux_oracle_ssh
#tmux_postgres_ssh
#tmux_oracle_enterprise
