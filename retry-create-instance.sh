#!/bin/bash
# ============================================================
# Reintenta crear una instancia Ampere A1 (Always Free) hasta
# que Oracle tenga capacidad disponible. Notifica por Telegram
# al conseguirla.
# ============================================================

# --- VALORES YA RELLENADOS ---
COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaaflp75xdj3sdf3bslw3npfeky5a7okqska33xiasotprlfg4yyapa"
SUBNET_ID="ocid1.subnet.oc1.iad.aaaaaaaajteccwlrho5y4jnyih3kz2iixhf7nlttybigy7w6zue5pdwj3r7q"
IMAGE_ID="ocid1.image.oc1.iad.aaaaaaaacuygljashkvpqu5qqmlausq2vwrwasp3lxpbpitxjhvbhsktlhma"
SSH_KEY_FILE="$HOME/.ssh/authorized_keys"   # o la ruta a tu .pub
DISPLAY_NAME="minecraft-ampere"
OCPUS=2
MEMORY_GB=12

# Notificación Telegram
TELEGRAM_BOT_TOKEN="7648677972:AAFrkKEl_qAG-KJjnj62UbVx7FRY44xoD_o"
TELEGRAM_CHAT_ID="7648677972"

# Dominios de disponibilidad a probar (prefijo real de tu tenancy: SHiu)
ADS=(
  "SHiu:US-ASHBURN-AD-1"
  "SHiu:US-ASHBURN-AD-2"
  "SHiu:US-ASHBURN-AD-3"
)

SLEEP_SECONDS=60
ATTEMPT=0

notify_telegram() {
  local MSG="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${MSG}" > /dev/null
}

SSH_KEY_CONTENT=$(cat "$SSH_KEY_FILE")

echo "Iniciando reintentos. Esto puede tardar minutos, horas o días."
echo "Presiona Ctrl+C para detener en cualquier momento."
echo ""

while true; do
  for AD in "${ADS[@]}"; do
    ATTEMPT=$((ATTEMPT + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] Intento #$ATTEMPT en $AD..."

    RESULT=$(oci compute instance launch \
      --compartment-id "$COMPARTMENT_ID" \
      --availability-domain "$AD" \
      --shape "VM.Standard.A1.Flex" \
      --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}" \
      --subnet-id "$SUBNET_ID" \
      --image-id "$IMAGE_ID" \
      --display-name "$DISPLAY_NAME" \
      --assign-public-ip true \
      --metadata "{\"ssh_authorized_keys\": \"$SSH_KEY_CONTENT\"}" \
      --wait-for-state RUNNING \
      --max-wait-seconds 120 2>&1)

    if echo "$RESULT" | grep -qi "OutOfCapacity\|LimitExceeded\|Out of host capacity"; then
      echo "  Sin capacidad en $AD. Probando el siguiente..."
      continue
    elif echo "$RESULT" | grep -qi "TooManyRequests"; then
      echo "  Límite de tasa alcanzado. Esperando un ciclo extra antes de seguir..."
      sleep "$SLEEP_SECONDS"
      continue
    elif echo "$RESULT" | grep -qi "\"lifecycle-state\": \"RUNNING\""; then
      echo ""
      echo "🎉 ¡Instancia creada exitosamente en $AD!"
      echo "$RESULT" | grep -A2 "public-ip"
      notify_telegram "✅ Instancia Oracle creada en $AD. Revisa la consola para ver la IP pública."
      echo ""
      echo "Revisa la consola de Oracle para ver la IP pública."
      exit 0
    else
      echo "  Respuesta inesperada, revisando:"
      echo "$RESULT" | head -20
      echo "  Reintentando de todas formas en el siguiente ciclo..."
    fi
  done
  echo "Ningún AD tuvo capacidad esta ronda. Esperando ${SLEEP_SECONDS}s..."
  sleep "$SLEEP_SECONDS"
done