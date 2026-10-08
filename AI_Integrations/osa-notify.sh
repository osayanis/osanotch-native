#!/bin/bash
# Script de notification pour OsaNotch (CLI AIs)
# Utilisation : ./osa-notify.sh "Claude Code a terminé sa tâche !"
# Ou en suffixe : claude-code --task "Fais un script" ; ./osa-notify.sh "Claude a fini"

MSG=${1:-"Tâche terminée"}
JSON_PAYLOAD="{\"msg\": \"$MSG\"}"

curl -s -X POST http://localhost:8081/notify -d "$JSON_PAYLOAD" > /dev/null

echo "Notification envoyée au Notch."
