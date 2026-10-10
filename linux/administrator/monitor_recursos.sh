#!/bin/bash
# Script para registrar picos de consumo de CPU y RAM

FECHA=$(date '+%Y-%m-%d %H:%M:%S')

# Log de CPU
echo "=== TOP CPU: $FECHA ===" >> /tmp/cpu.log
ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -n 6 >> /tmp/cpu.log
echo "" >> /tmp/cpu.log

# Log de Memoria
echo "=== TOP MEMORIA: $FECHA ===" >> /tmp/memoria.log
ps -eo pid,user,%mem,cmd --sort=-%mem | head -n 6 >> /tmp/memoria.log
echo "" >> /tmp/memoria.log