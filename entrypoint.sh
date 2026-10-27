#!/usr/bin/env bash
# Envoie une mini-requête à Claude dès que la fenêtre d'usage de 5h se termine,
# en se calant sur l'heure de fin réelle renvoyée par Claude Code.
set -u

MARGIN_SECONDS="${MARGIN_SECONDS:-60}"            # attente après la fin de fenêtre
FALLBACK_SECONDS="${FALLBACK_SECONDS:-18060}"     # si l'heure de fin est introuvable
RETRY_SECONDS="${RETRY_SECONDS:-300}"             # nouvel essai si échec réseau/API
MAX_SLEEP_SECONDS=$(( 5 * 3600 + MARGIN_SECONDS ))
MODEL="${MODEL:-haiku}"
PROMPT="${PROMPT:-Réponds juste: ok}"

log() { echo "$(date '+%F %T %Z') $*"; }
fmt() { date -d "@$1" '+%F %T'; }

if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  log "ERREUR: CLAUDE_CODE_OAUTH_TOKEN absent (génère-le avec 'claude setup-token')."
  exit 1
fi

# Attente optionnelle jusqu'à une heure de départ (ex. START_AT=06:00)
if [ -n "${START_AT:-}" ]; then
  target=$(date -d "$START_AT" +%s)
  now=$(date +%s)
  [ "$target" -le "$now" ] && target=$(date -d "tomorrow $START_AT" +%s)
  log "Premier ping prévu à $(fmt "$target")"
  sleep $(( target - now ))
fi

while true; do
  out=$(timeout 120 claude -p "$PROMPT" --model "$MODEL" --output-format stream-json --verbose < /dev/null 2>&1)
  code=$?
  reply=$(jq -r 'select(.type == "result") | .result // empty' <<<"$out" 2>/dev/null)
  reset=$(jq -r 'select(.type == "rate_limit_event") | .rate_limit_info
                 | .unifiedWindows.five_hour.resetsAt
                   // (select(.rateLimitType == "five_hour") | .resetsAt) // empty' <<<"$out" 2>/dev/null | tail -1)
  now=$(date +%s)

  if [ "$code" -eq 0 ]; then
    log "Ping OK: ${reply:-?}"
  else
    log "Ping en échec [exit $code]: ${reply:-$(tail -c 300 <<<"$out")}"
  fi

  if [[ "$reset" =~ ^[0-9]+$ ]] && [ "$reset" -gt "$now" ]; then
    wait_s=$(( reset - now + MARGIN_SECONDS ))
    [ "$wait_s" -gt "$MAX_SLEEP_SECONDS" ] && wait_s=$MAX_SLEEP_SECONDS
    log "Fenêtre en cours jusqu'à $(fmt "$reset"), prochain ping à $(fmt $(( now + wait_s )))"
  elif [ "$code" -eq 0 ]; then
    wait_s=$FALLBACK_SECONDS
    log "Heure de fin introuvable, prochain ping à $(fmt $(( now + wait_s )))"
  else
    wait_s=$RETRY_SECONDS
    log "Nouvel essai à $(fmt $(( now + wait_s )))"
  fi
  sleep "$wait_s"
done
