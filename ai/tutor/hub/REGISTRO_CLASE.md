---
id: labs-hub-mcp-registro-clase
title: "Registro de clase: práctica MCP de 15 minutos (H07) y prueba de VS Code (H05)"
tipo: plantilla
version: 1.0.0
fecha_ultimo_cambio: '2026-11-17'
categoria: continuidad
tags: [clase, registro, mcp, h05, h07]
---

# Registro de clase

Hoja para el docente. Completar una fila por alumno durante la clase; con una fila completa con los dos retos en OK, H07 queda cerrado en [PLAN_DE_ACCION.md](PLAN_DE_ACCION.md).

## Antes de la clase (5 min)

```bash
git pull
bash ai/tutor/demo_practica_15_min_mcp.sh --auto   # tiene que terminar en TODO OK
```

Si falla, la clase usa la práctica igual pero se anota el fallo abajo.

## Práctica de 15 minutos (H07)

Guía para el alumno: [../PRACTICA_15_MIN_MCP.md](../PRACTICA_15_MIN_MCP.md).

| Fecha | Alumno (alias) | SO | Cliente y versión | Minutos | Llamada real vista | Reto 1: herramienta oculta | Reto 2: token | Qué lo trabó |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| | | | | | sí / no | OK / falla | OK / falla | |

## VS Code con Copilot (H05)

En la máquina que tenga VS Code y Copilot:

```bash
python3 ai/tutor/hub/hub.py config vscode --write
```

Abrir el chat en modo **Agent**, revisar que aparezcan los MCP en herramientas y pedir «buscá un lab de RAID» (tiene que llamar a `search_curriculum`).

| Fecha | VS Code | Copilot Chat | Aparece el MCP | `search_curriculum` devolvió | Notas |
| :--- | :--- | :--- | :---: | :--- | :--- |
| | | | sí / no | | |

## Fallos conocidos

- Open WebUI con el modelo de la P4 a veces responde sin usar herramientas (pendiente `tutor-modelo-mas-grande`). La práctica no depende de Open WebUI; si igual bloquea a un alumno, anotarlo en «Qué lo trabó».
