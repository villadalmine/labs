#!/usr/bin/env bash
# ==============================================================================
# DEMO Lab 3.7 · RAID desde cero (sin root, sin discos): striping, espejo y
# paridad XOR con bytes reales + calculadora de capacidad + bit rot.
#
# Uso: ./demo_raid_teoria.sh [--auto <segundos>]
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_common_args "$@"

hex() { printf '%02x' "$1"; }
show_disk() { # nombre, bytes...
    local n="$1"; shift
    local out="" b
    for b in "$@"; do out+="$(hex "$b") "; done
    printf "   %-10s [ %s]\n" "$n" "$out"
}

header "LAB 3.7 · RAID desde cero: todo con bytes reales (sin root)"
echo "Vamos a simular discos con arrays de bash. Cada 'disco' guarda bytes."

# ------------------------------------------------------------------ RAID 0
header "PASO 1 · RAID 0 (striping)"
MSG="RAID0DATA"
bytes=(); for ((i=0;i<${#MSG};i++)); do bytes+=($(printf '%d' "'${MSG:$i:1}")); done
d1=(); d2=()
for i in "${!bytes[@]}"; do
    if (( i % 2 == 0 )); then d1+=("${bytes[$i]}"); else d2+=("${bytes[$i]}"); fi
done
echo "Mensaje: '$MSG' ($(( ${#MSG} )) bytes) repartido en round-robin:"
show_disk "Disco 1" "${d1[@]}"
show_disk "Disco 2" "${d2[@]}"
echo -e "${YELLOW}Si muere el Disco 2, solo quedan bytes alternados: el mensaje es irrecuperable.${RESET}"
echo "Capacidad útil = 2 discos = 100 %. Tolerancia a fallas = 0."
pause_step "ENTER para RAID 1..."

# ------------------------------------------------------------------ RAID 1
header "PASO 2 · RAID 1 (espejo)"
m1=("${bytes[@]}"); m2=("${bytes[@]}")
show_disk "Disco 1" "${m1[@]}"
show_disk "Disco 2" "${m2[@]}"
echo -e "${RED}💥 Falla el Disco 1${RESET}  → leemos del Disco 2:"
recovered=""; for b in "${m2[@]}"; do recovered+=$(printf "\\x$(hex "$b")"); done
echo -e "${GREEN}Recuperado: '$recovered'${RESET}  (capacidad útil 50 %)"
pause_step "ENTER para RAID 5 (paridad XOR)..."

# ------------------------------------------------------------------ RAID 5
header "PASO 3 · RAID 5 (paridad XOR distribuida, 3 discos)"
MSG5="PARIDAD-XOR!"
b5=(); for ((i=0;i<${#MSG5};i++)); do b5+=($(printf '%d' "'${MSG5:$i:1}")); done
A=(); B=(); P=()
for ((i=0;i<${#b5[@]};i+=2)); do
    a=${b5[$i]}; b=${b5[$((i+1))]:-0}
    A+=("$a"); B+=("$b"); P+=($(( a ^ b )))
done
echo "Mensaje: '$MSG5'  → franjas de 2 bloques de datos + 1 de paridad (P = A ⊕ B)"
show_disk "Disco A" "${A[@]}"
show_disk "Disco B" "${B[@]}"
show_disk "Paridad" "${P[@]}"
echo -e "\n${RED}💥 Se rompe el Disco A (sus bytes se pierden).${RESET} Reconstruimos con A = B ⊕ P:"
R=(); for i in "${!B[@]}"; do R+=($(( B[i] ^ P[i] ))); done
show_disk "A recup." "${R[@]}"
ok=true; for i in "${!A[@]}"; do [ "${A[$i]}" -eq "${R[$i]}" ] || ok=false; done
$ok && echo -e "${GREEN}✔ Reconstrucción PERFECTA: cada byte coincide con el original.${RESET}"
echo -e "\nEjemplo de un solo byte:  A=0x$(hex "${A[0]}")  B=0x$(hex "${B[0]}")  →  P=A⊕B=0x$(hex "${P[0]}")"
echo "                          B⊕P = 0x$(hex "${B[0]}") ⊕ 0x$(hex "${P[0]}") = 0x$(hex $(( B[0] ^ P[0] ))) = A ✔"
echo -e "\n${YELLOW}Límite del XOR:${RESET} con 2 discos perdidos hay 2 incógnitas y 1 ecuación → por eso RAID 6 agrega una 2ª paridad (Q)."
pause_step "ENTER para la calculadora de capacidad..."

# ------------------------------------------------------------------ Capacidad
header "PASO 4 · Calculadora de capacidad y tolerancia"
N=6; S=4
echo "Con N=$N discos de ${S} TB:"
printf "   %-10s %-14s %-12s %-s\n" "Nivel" "Útil (TB)" "Eficiencia" "Tolerancia"
printf "   %-10s %-14s %-12s %-s\n" "RAID 0"  "$(( N*S ))"       "100%"                      "0 discos"
printf "   %-10s %-14s %-12s %-s\n" "RAID 1"  "$S (N copias)"    "$(( 100/N ))%"             "$((N-1)) discos"
printf "   %-10s %-14s %-12s %-s\n" "RAID 5"  "$(( (N-1)*S ))"   "$(( (N-1)*100/N ))%"       "1 disco"
printf "   %-10s %-14s %-12s %-s\n" "RAID 6"  "$(( (N-2)*S ))"   "$(( (N-2)*100/N ))%"       "2 discos"
printf "   %-10s %-14s %-12s %-s\n" "RAID 10" "$(( N/2*S ))"     "50%"                       "1 por par (hasta $((N/2)))"
pause_step "ENTER para ver bit rot..."

# ------------------------------------------------------------------ Bit rot
header "PASO 5 · Bit rot: ¿quién miente?"
orig=$(printf '%d' "'X")
c1=$orig; c2=$(( orig ^ 4 ))   # un solo bit alterado en el espejo 2
echo "Espejo 1 guarda 0x$(hex $c1) ('X').  Espejo 2 tiene un bit volteado: 0x$(hex $c2)."
echo -e "${YELLOW}RAID clásico (mdadm/LVM):${RESET} sin checksum, ambas copias 'parecen' válidas → leer del espejo 2 devuelve basura SIN AVISO."
chk() { echo $(( $1 * 31 + 7 )); }   # checksum de juguete
stored=$(chk $orig)
echo -e "${YELLOW}Btrfs/ZFS:${RESET} guardan checksum del bloque en el puntero padre (= $stored)."
for n in 1 2; do
    v=$([ $n -eq 1 ] && echo $c1 || echo $c2)
    if [ "$(chk "$v")" -eq "$stored" ]; then echo "   copia $n: checksum OK ✔"
    else echo -e "   copia $n: ${RED}checksum NO coincide ✘ → se lee la otra copia y se REPARA (self-healing)${RESET}"; fi
done

header "FIN · Siguiente: Lab 3.8 RAID con mdadm (raid_mdadm.md)"
pie_clase
