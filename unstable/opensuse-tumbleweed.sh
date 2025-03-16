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

    if [[ ! -f "$ICON_SRC" ]]; then
        echo "Erro: O ícone stirling-pdf.png não foi encontrado no diretório $SCRIPT_DIR."
        exit 1
    fi

    # Instalar dependências necessárias (openSUSE)
    echo "Instalando dependências..."
    sudo zypper --non-interactive install docker docker-compose tesseract-ocr tesseract-ocr-traineddata-por tesseract-ocr-traineddata-eng

    # Habilitar o Docker para iniciar automaticamente no boot
    echo "Habilitando o Docker para iniciar no boot..."
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service

    # Iniciar o serviço Docker e garantir que ele esteja em execução
    echo "Iniciando o serviço Docker..."
    sudo systemctl start docker.service

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
    echo "Criando diretório para o Stirling-PDF..."
    mkdir -p /opt/stirling-pdf && cd /opt/stirling-pdf

    # Criar Dockerfile com instalação do OpenJDK
    echo "Criando Dockerfile para o Stirling-PDF com Java..."
    cat > Dockerfile <<EOF
FROM frooodle/s-pdf:latest

# Instalar OpenJDK 11 no Alpine
RUN apk update && \
    apk add --no-cache openjdk11 && \
    apk add --no-cache bash

# Defina o comando de execução
CMD ["sh", "-c", "java -Dfile.encoding=UTF-8 -jar /app.jar & /opt/venv/bin/unoserver --port 2003 --interface 0.0.0.0"]
EOF

    # Construir a imagem Docker com o Java
    echo "Construindo a imagem Docker com Java..."
    sudo docker build -t stirling-pdf-java .

    # Criar arquivo docker-compose.yml
    echo "Criando arquivo docker-compose.yml..."
    cat > docker-compose.yml <<EOF
services:
  stirling-pdf:
    image: stirling-pdf-java
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
    echo "Iniciando o container do Stirling-PDF..."
    #sudo docker compose up -d
    sudo docker run --privileged --security-opt seccomp=unconfined -d -p 8080:8080 --name stirling-pdf frooodle/s-pdf

    # Criar um serviço systemd para iniciar automaticamente o Stirling-PDF
    echo "Criando serviço systemd para o Stirling-PDF..."
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
    echo "Habilitando e iniciando o serviço Stirling-PDF..."
    sudo systemctl daemon-reload
    sudo systemctl enable --now stirling-pdf.service

    # Criar o atalho no menu de aplicativos
    echo "Criando atalho no menu de aplicativos..."
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
    echo "Criando diretório de ícones..."
    sudo mkdir -p /usr/share/icons

    # Copiar o ícone para o diretório correto
    echo "Copiando o ícone para o diretório de ícones..."
    sudo cp "$ICON_SRC" "$ICON_DST"

    # Informar o usuário que a instalação foi concluída
    echo "Instalação concluída! Acesse o Stirling-PDF em: http://localhost:8080 ou pelo menu de aplicativos."
}

# Função para remoção completa (Stirling-PDF, Docker e dependências)
remove_stirling_pdf() {
    # Limpando o terminal
    clear

    # Parar e desabilitar o Docker
    echo "Parando e desabilitando o Docker..."
    sudo systemctl stop docker.service
    sudo systemctl disable docker.service

    echo "Removendo o container do Stirling-PDF..."
    sudo docker stop stirling-pdf || true
    sudo docker rm stirling-pdf || true
    echo "Container Stirling-PDF removido."

    # Remover as imagens do Docker relacionadas ao Stirling-PDF
    echo "Removendo a imagem do Docker do Stirling-PDF..."
    sudo docker rmi -f stirling-pdf-java || echo "Imagem do Docker não encontrada."

    # Remover o diretório do Stirling-PDF
    echo "Removendo o diretório /opt/stirling-pdf..."
    sudo rm -rf /opt/stirling-pdf

    # Remover pacotes do Docker e dependências
    echo "Removendo pacotes do Docker e dependências..."
    sudo zypper --non-interactive remove --clean-deps docker docker-compose tesseract-ocr
    sudo rm -rf /usr/share/tessdata

    # Remover o atalho do menu de aplicativos
    echo "Removendo o atalho do menu de aplicativos..."
    sudo rm -f /usr/share/applications/stirling-pdf.desktop

    # Remover o ícone do sistema
    echo "Removendo o ícone..."
    sudo rm -f /usr/share/icons/stirling-pdf.png

    echo "Remoção do Stirling-PDF, Docker e atalho concluída com sucesso!"
}

# Função para remover apenas o Stirling-PDF e Tesseract (mantendo o Docker)
remove_stirling_pdf_only() {
    # Limpando o terminal
    clear

    echo "Removendo o Stirling-PDF junto com Tesseract..."

    # Verificar se o container stirling-pdf está em execução e removê-lo
    sudo docker stop stirling-pdf || true
    sudo docker rm stirling-pdf || true
    echo "Container Stirling-PDF removido."

    # Remover o diretório do Stirling-PDF
    echo "Removendo o diretório /opt/stirling-pdf..."
    sudo rm -rf /opt/stirling-pdf

    # Remover o atalho do menu de aplicativos
    echo "Removendo o atalho do menu de aplicativos..."
    sudo rm -f /usr/share/applications/stirling-pdf.desktop

    # Remover o ícone do sistema
    echo "Removendo o ícone..."
    sudo rm -f /usr/share/icons/stirling-pdf.png

    # Remover o Tesseract
    echo "Removendo o Tesseract..."
    sudo zypper --non-interactive remove --clean-deps tesseract-ocr
    sudo rm -rf /usr/share/tessdata/

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
