#!/usr/bin/env bash
# Decodifica header e payload de um JWT (sem validar assinatura).
# Uso: jwt-decode <token>      ou   echo <token> | jwt-decode
#      jwt-decode -p <token>   -> imprime SÓ o payload em JSON (bom para 'jq')
set -euo pipefail
only_payload=0
if [ "${1:-}" = "-p" ]; then only_payload=1; shift; fi
tok="${1:-$(cat)}"
b64() { local s="${1//-/+}"; s="${s//_//}"; local pad=$(( (4 - ${#s} % 4) % 4 )); printf '%s' "$s$(printf '=%.0s' $(seq 1 $pad 2>/dev/null))" | base64 -d 2>/dev/null; }
IFS='.' read -r h p _ <<< "$tok"
if [ "$only_payload" = "1" ]; then b64 "$p" | jq .; exit 0; fi
echo "== header =="; b64 "$h" | jq .
echo "== payload =="; b64 "$p" | jq .
