#!/bin/bash
ZABBIX_SERVER="10.1.0.9"   
HOST_NAME=$HOSTNAME        
ITEM_KEY="custom.nodes.consumer.queueName"  
TEMP_FILE=" /tmp/consumer_queue.log"  
MAP_FILE="/tmp/consumer_queue_map.txt"      

PROCESS_LIST=$(ps -axu | grep -e "RunConsumer" | grep -v "grep" | grep -oP '(?<=--queueName=)[^\s]+')

if [[ -z "$PROCESS_LIST" ]]; then
  echo "empty processlist"
  exit 1
fi

declare -A QUEUE_MAP
if [[ -f "$MAP_FILE" ]]; then
  while IFS=":" read -r QUEUE_NAME QUEUE_ID; do
    QUEUE_MAP["$QUEUE_NAME"]="$QUEUE_ID"
  done < "$MAP_FILE"
fi

# Присваиваем ID новым очередям
NEXT_ID=$(( $(printf "%s\n" "${QUEUE_MAP[@]}" | sort -n | tail -n 1) + 1 ))
NEW_STATE=""
QUEUE_CODES=()

while IFS= read -r QUEUE_NAME; do
  if [[ -z "${QUEUE_MAP[$QUEUE_NAME]}" ]]; then
    QUEUE_MAP["$QUEUE_NAME"]=$NEXT_ID
    NEXT_ID=$((NEXT_ID + 1))
  fi
  QUEUE_CODES+=("${QUEUE_MAP[$QUEUE_NAME]}")
  NEW_STATE+="$QUEUE_NAME"$'\n'
done <<< "$PROCESS_LIST"

# Сохраняем маппинг в файл
> "$MAP_FILE"
for QUEUE_NAME in "${!QUEUE_MAP[@]}"; do
  echo "$QUEUE_NAME:${QUEUE_MAP[$QUEUE_NAME]}" >> "$MAP_FILE"
done

# Проверяем изменения состояния
NEW_STATE=$(echo "$NEW_STATE" | sed '/^$/d') # Убираем пустые строки
if [[ "$NEW_STATE" != "$(cat "$TEMP_FILE" 2>/dev/null)" ]]; then
  # Сохраняем новое состояние
  echo "$NEW_STATE" > "$TEMP_FILE"

  # Отправляем данные в Zabbix
  for CODE in "${QUEUE_CODES[@]}"; do
    /usr/bin/zabbix_sender -z "$ZABBIX_SERVER" -s "$HOST_NAME" -k "$ITEM_KEY" -o "$CODE"
  done
fi
