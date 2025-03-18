#!/bin/bash
# Script para instalar ou remover o Stirling-PDF com Podman e criar o atalho no menu de aplicativos

# Função para instalação do Stirling-PDF
install_stirling_pdf() {
    clear
    set -e  # Interrompe o script em caso de erro

    # Se o script foi executado com sudo, usar o diretório home do usuário original
    if [ -n "$SUDO_USER" ]; then
        REAL_USER_HOME=$(eval echo "~$SUDO_USER")
    else
        REAL_USER_HOME="$HOME"
    fi

    USER_HOME="$REAL_USER_HOME"
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    ICON_SRC="$SCRIPT_DIR/stirling-pdf.png"
    ICON_DST="$USER_HOME/.local/share/icons/stirling-pdf.png"
    SERVICE_FILE="/etc/systemd/system/stirling-pdf.service"
    HELPER_SCRIPT="/usr/local/bin/start-stirling-pdf.sh"

    # Verificar se o ícone existe
    if [[ ! -f "$ICON_SRC" ]]; then
        echo -e "\033[1;31mErro: O ícone stirling-pdf.png não foi encontrado em $SCRIPT_DIR.\033[0m"
        exit 1
    fi

    # Instalação do Podman
    echo "Instalando o Podman com rpm-ostree..."
    if ! command -v podman &>/dev/null; then
        echo "Podman não encontrado. Instalando com rpm-ostree..."
        rpm-ostree install -y podman
    else
        echo "Podman já instalado, ignorando..."
    fi

    echo "Instalando o Tesseract com rpm-ostree..."
    packages=("tesseract" "tesseract-langpack-por" "tesseract-langpack-eng")
    missing_packages=()
    for pkg in "${packages[@]}"; do
        if ! rpm-ostree status | grep -q "$pkg"; then
            missing_packages+=("$pkg")
        fi
    done
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "Instalando pacotes ausentes: ${missing_packages[*]}"
        rpm-ostree install -y "${missing_packages[@]}"
    else
        echo "Tesseract já instalado, ignorando..."
    fi

    # Remover imagem antiga, se existir
    if podman images --format "{{.Repository}}:{{.Tag}}" | grep -q "^docker.io/frooodle/s-pdf:latest$"; then
        echo "Imagem 'frooodle/s-pdf:latest' já existe localmente. Removendo..."
        podman rmi -f docker.io/frooodle/s-pdf:latest
    fi

    echo -e "Baixando a imagem \033[1mdocker.io/frooodle/s-pdf:latest...\033[0m"
    podman pull frooodle/s-pdf:latest

    # Configurar as portas
    LOCAL_PORT=8081
    CONTAINER_PORT=8080

    # Criação do arquivo auxiliar que será executado no boot.
    # Esse script criará o container (se necessário) e o iniciará.
    cat > "$HELPER_SCRIPT" <<'EOF'
#!/bin/bash
# Script auxiliar para criação e inicialização do container Stirling-PDF
CONTAINER_NAME="stirling-pdf"
LOCAL_PORT=8081
CONTAINER_PORT=8080
IMAGE="frooodle/s-pdf:latest"

# Verifica se o container já existe
if ! podman container exists "$CONTAINER_NAME"; then
    echo "Criando o container $CONTAINER_NAME..."
    podman create --name "$CONTAINER_NAME" \
      -p ${LOCAL_PORT}:${CONTAINER_PORT} \
      -v "/usr/share/tesseract/tessdata:/usr/share/tessdata" \
      -e TESSDATA_PREFIX=/usr/share/tessdata \
      "$IMAGE"
else
    echo "Container $CONTAINER_NAME já existe."
fi

echo "Iniciando o container $CONTAINER_NAME..."
podman start -a "$CONTAINER_NAME"
EOF

    # Tornar o script auxiliar executável
    sudo chmod +x "$HELPER_SCRIPT"

    # Criar o arquivo de unidade systemd que executará o script auxiliar no boot
    echo "Criando o arquivo de serviço systemd para o Stirling-PDF..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Stirling-PDF Service
After=network.target local-fs.target
Requires=podman.service

[Service]
Type=simple
ExecStart=$HELPER_SCRIPT
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF

    # Recarregar o systemd e habilitar o serviço
    echo "Recarregando o systemd e habilitando o serviço..."
    sudo systemctl daemon-reload
    sudo systemctl enable stirling-pdf.service

    # Criar o atalho no menu de aplicativos
    echo "Criando o atalho no menu de aplicativos..."
    mkdir -p "$USER_HOME/.local/share/icons" "$USER_HOME/.local/share/applications"
    cp "$ICON_SRC" "$ICON_DST"
    cat > "$USER_HOME/.local/share/applications/stirling-pdf.desktop" <<EOF
[Desktop Entry]
Name=Stirling-PDF
Exec=xdg-open http://localhost:$LOCAL_PORT
Icon=$ICON_DST
Terminal=false
Type=Application
Categories=Utility;
EOF
    chmod +x "$USER_HOME/.local/share/applications/stirling-pdf.desktop"

    echo -e "\n\033[1;32mInstalação concluída!\033[0m"
    echo "As alterações do rpm-ostree (incluindo a criação de /usr/share/tesseract/tessdata) serão aplicadas após o reboot."
    echo "Após reiniciar, o serviço systemd criará e iniciará automaticamente o container do Stirling-PDF."
    echo "Você poderá acessar o Stirling-PDF em: http://localhost:$LOCAL_PORT"
    echo -e "\033[1mReinicie o sistema para efetivar todas as alterações!\033[0m"

    reiniciar_sistema
}

# Função para remoção do Stirling-PDF (mantida similar à versão anterior)
remove_stirling_pdf() {
    clear
    set -e

    if [ -n "$SUDO_USER" ]; then
        REAL_USER_HOME=$(eval echo "~$SUDO_USER")
    else
        REAL_USER_HOME="$HOME"
    fi

    echo "Removendo o Stirling-PDF e limpando arquivos associados..."

    sudo systemctl stop stirling-pdf.service || true
    sudo systemctl disable stirling-pdf.service || true
    sudo rm -f /etc/systemd/system/stirling-pdf.service
    sudo systemctl daemon-reload

    podman stop stirling-pdf || true
    podman rm stirling-pdf || true
    podman rmi -f frooodle/s-pdf:latest || true

    rm -rf "$REAL_USER_HOME/.local/share/stirling-pdf"
    rm -f "$REAL_USER_HOME/.local/share/icons/stirling-pdf.png"
    rm -f "$REAL_USER_HOME/.local/share/applications/stirling-pdf.desktop"


    # Remover Tesseract
    rpm-ostree uninstall -y tesseract tesseract-langpack-por tesseract-langpack-eng

    find "$REAL_USER_HOME/.local/share" -type f -name "*stirling*" -exec rm -f {} \;

    echo "Stirling-PDF removido completamente."
    echo -e "\e[1mReinicie o sistema para efetivar as alterações!\e[0m"
    reiniciar_sistema
}

# Função para perguntar se deseja reiniciar o sistema
reiniciar_sistema() {
    while true; do
        read -rp "Deseja reiniciar o sistema agora? (s/n): " resposta
        case "$resposta" in
            [Ss]) echo "Reiniciando o sistema..."; systemctl reboot ;;
            [Nn]) echo "Reinicialização adiada. Reinicie manualmente quando desejar."; break ;;
            *) echo "Por favor, responda com 's' para sim ou 'n' para não." ;;
        esac
    done
}

# Menu de opções
PS3="Escolha uma opção: "
options=("Instalar Stirling-PDF" "Remover Stirling-PDF" "Sair")
select opt in "${options[@]}"; do
    case "$REPLY" in
        1) install_stirling_pdf; break;;
        2) remove_stirling_pdf; break;;
        3) echo "Saindo..."; exit 0;;
        *) echo "Opção inválida. Tente novamente.";;
    esac
done
