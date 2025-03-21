#!/bin/bash

# Função para instalação
install_stirling_pdf() {
    # Limpando o terminal
    clear

    set -e  # Para o script em caso de erro

    # Verifica se o usuário é root
    if [ $EUID -ne 0 ]; then
        echo "Este script precisa ser executado como root ou com sudo."
        exit 1
    fi

    # Verificar se o ícone stirling-pdf.png está na pasta do script
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    ICON_SRC="$SCRIPT_DIR/stirling-pdf.png"
    ICON_DST="/usr/share/icons/stirling-pdf.png"

    # Verificar se o ícone existe antes de continuar
    if [ ! -f "$ICON_SRC" ]; then
        echo "Erro: O ícone stirling-pdf.png não foi encontrado no diretório $SCRIPT_DIR."
        exit 1
    fi

    # Instalar dependências necessárias
    apt update
    apt install -y docker.io tesseract-ocr tesseract-ocr-por tesseract-ocr-eng wget

    # Verificar se curl está instalado, caso contrário, instalar
    if ! command -v curl &> /dev/null; then
        echo "O curl não está instalado. Instalando..."
        apt install -y curl
    fi

    # Instalar Docker Compose V2
    echo "Instalando o Docker Compose V2..."
    curl -SL https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Baixar e instalar manualmente os dados do Tesseract para português do Brasil
    mkdir -p /usr/share/tessdata
    wget -O /usr/share/tessdata/por.traineddata "https://github.com/tesseract-ocr/tessdata_best/raw/main/por.traineddata"

    # Habilitar e iniciar Docker
    systemctl enable --now docker.service
    systemctl enable --now containerd.service

    # Criar diretório para o Stirling-PDF
    mkdir -p /opt/stirling-pdf && cd /opt/stirling-pdf

    # Baixar o docker-compose.yml oficial
    cat > docker-compose.yml <<EOF
services:
  stirling-pdf:
    image: frooodle/s-pdf
    container_name: stirling-pdf
    restart: always
    ports:
      - "8080:8080"
    volumes:
      - /usr/share/tessdata:/usr/share/tessdata
    environment:
      - TESSDATA_PREFIX=/usr/share/tessdata
EOF

    # Verificar se está usando Docker Compose V1 ou V2 e rodar o container
    if command -v docker-compose &> /dev/null; then
        echo "Usando Docker Compose V1"
        docker-compose up -d
    else
        echo "Usando Docker Compose V2"
        docker compose up -d
    fi

    # Criar um serviço systemd para iniciar automaticamente o Stirling-PDF
    cat > /etc/systemd/system/stirling-pdf.service <<EOF
[Unit]
Description=Stirling-PDF Service
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker start -a stirling-pdf
ExecStop=/usr/bin/docker stop stirling-pdf

[Install]
WantedBy=multi-user.target
EOF

    # Habilitar e iniciar o serviço
    systemctl daemon-reload
    systemctl enable --now stirling-pdf.service

    # Criar o atalho
    cat > /usr/share/applications/stirling-pdf.desktop <<EOF
[Desktop Entry]
Name=Stirling-PDF
Comment=Ferramenta de manipulação de PDFs
Exec=xdg-open http://localhost:8080
Icon=/usr/share/icons/stirling-pdf.png
Terminal=false
Type=Application
Categories=Utility;Office;
EOF

    # Criar o diretório /usr/share/icons caso não exista
    mkdir -p /usr/share/icons

    # Copiar o ícone para o diretório correto
    cp "$ICON_SRC" "$ICON_DST"

    # Informar o usuário que a instalação foi concluída
    echo "Instalação concluída! Acesse o Stirling-PDF em: http://localhost:8080 ou pelo menu de aplicativos."
}

# Função para remoção completa (Stirling-PDF, Docker e dependências)
remove_stirling_pdf() {
    # Limpando o terminal
    clear

    # Parar e desabilitar o Docker
    echo "Parando e desabilitando o Docker..."
    systemctl stop docker.service
    systemctl disable docker.service
    docker compose stop

    echo "Removendo o container do Stirling-PDF..."
    docker stop stirling-pdf
    docker rm stirling-pdf
    echo "Container Stirling-PDF removido."

    # Remover as imagens do Docker relacionadas ao Stirling-PDF
    echo "Removendo a imagem do Docker do Stirling-PDF..."
    docker rmi -f frooodle/s-pdf || echo "Imagem do Docker não encontrada."

    # Remover o diretório do Stirling-PDF
    echo "Removendo o diretório /opt/stirling-pdf..."
    rm -rf /opt/stirling-pdf

    # Remover pacotes do Docker e dependências
    echo "Removendo pacotes do Docker e dependências..."
    apt remove --purge -y docker.io docker-compose
    apt autoremove -y
    rm -rf /var/lib/docker

    # Remover o atalho do menu de aplicativos
    echo "Removendo o atalho do menu de aplicativos..."
    rm -f /usr/share/applications/stirling-pdf.desktop

    # Remover o Tesseract
    echo "Removendo o Tesseract..."
    apt remove --purge -y tesseract-ocr*
    rm -rf /usr/share/tessdata/

    #Limpando vestigios
    sudo rm /usr/local/bin/docker-compose
    sudo rm /usr/local/bin/docker

    echo "Remoção do Stirling-PDF, Docker e atalho concluída com sucesso!"
}

remove_stirling_pdf_only() {
    # Limpando o terminal
    clear

    echo "Removendo o Stirling-PDF junto com Tesseract..."

    # Verificar se o container stirling-pdf está em execução e removê-lo
    if docker ps -a --filter "name=stirling-pdf" --format '{{.Names}}' | grep -q stirling-pdf; then
        echo "Parando o container do Stirling-PDF..."
        docker stop stirling-pdf
        echo "Container Stirling-PDF parado."
        docker rm stirling-pdf
        echo "Container Stirling-PDF removido."
    else
        echo "Container Stirling-PDF não encontrado ou já removido."
    fi

    # Remover o diretório do Stirling-PDF
    echo "Removendo o diretório /opt/stirling-pdf..."
    rm -rf /opt/stirling-pdf

    # Remover o atalho do menu de aplicativos
    echo "Removendo o atalho do menu de aplicativos..."
    rm -f /usr/share/applications/stirling-pdf.desktop

    # Remover o ícone do sistema
    echo "Removendo o ícone..."
    rm -f /usr/share/icons/stirling-pdf.png

    # Remover o Tesseract
    echo "Removendo o Tesseract..."
    apt remove --purge -y tesseract-ocr*
    rm -rf /usr/share/tessdata/

    echo "Remoção do Stirling-PDF, Tesseract e arquivos relacionados concluída com sucesso!"
}

# Pergunta ao usuário se deseja instalar, remover completamente, remover parcialmente ou atualizar o Docker Compose
echo "Escolha uma opção:"
echo "1 - Instalar Stirling-PDF"
echo "2 - Remover Stirling-PDF e Docker"
echo "3 - Remover apenas o Stirling-PDF e Tesseract --Mantendo o Docker no sistema--"
echo "4 - Atualizar Docker Compose (Ubuntu)"
echo "0 - Cancelar e sair"
read -p "Digite o número da opção desejada: " opcao

atualizar_docker_compose() {
    # Verifica se o Docker Compose está instalado
    if ! command -v docker-compose &>/dev/null && ! command -v docker &>/dev/null; then
        echo "Docker Compose não está instalado!"
        echo "Instale-o primeiro antes de tentar atualizar."
        return
    fi

    # Obtém a versão atual instalada (compatível com "docker-compose" e "docker compose")
    if command -v docker-compose &>/dev/null; then
        versao_atual=$(docker-compose version --short)
    elif command -v docker &>/dev/null; then
        versao_atual=$(docker compose version --short)
    fi

    # Exibe a versão atual do Docker Compose
    echo "Versão atual do Docker Compose: $versao_atual"

    # Obtém a versão mais recente disponível no GitHub
    versao_nova=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d '"' -f 4 | sed 's/v//')

    if [[ -z "$versao_nova" ]]; then
        echo "Não foi possível obter a versão mais recente. Tente novamente mais tarde."
        return
    fi

    # Exibe a versão mais recente disponível
    echo "Versão mais recente disponível: $versao_nova"

    # Compara as versões
    if [[ "$versao_atual" == "$versao_nova" ]]; then
        echo "Você já está na versão mais recente do Docker Compose!"
        return
    fi

    # Pergunta se o usuário deseja atualizar
    read -p "Deseja atualizar para a versão $versao_nova? (s/n): " confirmacao
    if [[ "$confirmacao" != "s" ]]; then
        echo "Atualização cancelada."
        return
    fi

    # Atualiza o Docker Compose
    echo "Atualizando Docker Compose para a versão mais recente..."
    sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    echo "Atualização concluída!"
    docker-compose version
}

case $opcao in
    1)
        install_stirling_pdf
        ;;
    2)
        remove_stirling_pdf
        ;;
    3)
        remove_stirling_pdf_only
        ;;
    4)
        atualizar_docker_compose
        ;;
    0)
        echo "Operação cancelada. Saindo..."
        exit 0
        ;;
    *)
        echo "Opção inválida. Saindo..."
        exit 1
        ;;
esac
