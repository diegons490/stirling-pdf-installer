#!/bin/bash

# Função para instalação
install_stirling_pdf() {
    # Limpando o terminal
    clear

    set -e  # Para o script em caso de erro

    # Verifica se o usuário é root
    if [[ $EUID -ne 0 ]]; then
        echo "Este script precisa ser executado como root ou com sudo."
        exit 1
    fi

    # Verificar se o ícone stirling-pdf.png está na pasta do script
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    ICON_SRC="$SCRIPT_DIR/stirling-pdf.png"
    ICON_DST="/usr/share/icons/stirling-pdf.png"

    # Verificar se o ícone existe antes de continuar
    if [[ ! -f "$ICON_SRC" ]]; then
        echo "Erro: O ícone stirling-pdf.png não foi encontrado no diretório $SCRIPT_DIR."
        exit 1
    fi

    # Instalar dependências necessárias (Fedora)
    dnf install -y docker docker-compose tesseract tesseract-langpack-por tesseract-langpack-eng

    # Baixar e instalar manualmente os dados do Tesseract para português do Brasil
    mkdir -p /usr/share/tessdata
    wget -O /usr/share/tessdata/por.traineddata "https://github.com/tesseract-ocr/tessdata_best/raw/main/por.traineddata"
    wget -O /usr/share/tessdata/eng.traineddata "https://github.com/tesseract-ocr/tessdata_best/raw/main/eng.traineddata"


    # Habilitar e iniciar Docker
    systemctl enable --now docker.service
    systemctl enable --now containerd.service

    # Loop para aguardar até o Docker estar ativo
    while ! sudo systemctl is-active --quiet docker.service; do
        echo "Aguardando o Docker iniciar..."
        sleep 2  # Aguarda 2 segundos antes de verificar novamente
    done

    # Garantir que o Docker foi iniciado com sucesso
    echo "Docker está ativo e em execução!"

    # Verificar se o container stirling-pdf já existe e removê-lo
    echo "Verificando se o container stirling-pdf já existe..."
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^stirling-pdf$"; then
        echo "Removendo container antigo stirling-pdf..."
        sudo docker rm -f stirling-pdf
    fi

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

    # Iniciar o container do Stirling-PDF
    docker-compose up -d

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
    dnf remove -y docker docker-compose docker-cli docker-buildx
    rm -rf /var/lib/docker
    # Remover o atalho do menu de aplicativos
    echo "Removendo o atalho do menu de aplicativos..."
    rm -f /usr/share/applications/stirling-pdf.desktop

    # Remover o Tesseract
    echo "Removendo o Tesseract..."
    dnf remove -y tesseract
    rm -rf /usr/share/tessdata/

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
    dnf remove -y tesseract
    rm -rf /usr/share/tessdata/

    echo "Remoção do Stirling-PDF, Tesseract e arquivos relacionados concluída com sucesso!"
}

# Pergunta ao usuário se deseja instalar, remover completamente ou remover parcialmente
echo "Escolha uma opção:"
echo "1 - Instalar Stirling-PDF"
echo "2 - Remover Stirling-PDF e Docker"
echo "3 - Remover apenas o Stirling-PDF e Tesseract --Mantendo o Docker no sistema--"
echo "0 - Cancelar e sair"
read -p "Digite o número da opção desejada: " opcao

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
    0)
        echo "Operação cancelada. Saindo..."
        exit 0
        ;;
    *)
        echo "Opção inválida. Saindo..."
        exit 1
        ;;
esac
