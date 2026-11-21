---
id: linux-admin-glosario-tecnico-oficial
title: 'Glosario Técnico de Administración Linux: Kernel, Virtualización, Almacenamiento y Resiliencia'
difficulty_level: 1
difficulty_label: 'Nivel 1-4: Referencia Conceptual y Documentación Oficial'
section: '1.0'
sections:
- '1.0'
- 'glossary'
category: reference
resource_type: cheatsheet
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: reading_only
tags:
- glosario
- kernel
- unix
- posix
- lkm
- sysfs
- sysctl
- ostree
- ebpf
- virtualizacion
- kvm
- hyper-v
- freebsd-jails
- solaris-zones
- aix-lpar
- contenedores
- kubernetes
- k9s
- openstack
- hpc
- slurm
- storage
- raid
- cifrado
tools:
- modprobe
- sysctl
- dmesg
- bpftool
- dracut
- qemu-system-x86_64
- virsh
- docker
- podman
- kubectl
- k9s
- sbatch
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Bare-Metal
  type: local
  os: Fedora Linux 44 / Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Referencia cruzada y enlaces a documentación oficial verificados.
environments:
- Bare-Metal
- QEMU/KVM
- WSL2
- AWS EC2
operating_systems:
- Agnóstico
status: VERIFIED
rag_summary: Glosario técnico oficial y compendio de referencia cruzada del plan de estudios Linux SysAdmin. Reúne definiciones detalladas, impacto operativo en producción y enlaces a documentación oficial para almacenamiento (Write-Intent Bitmap, Write-Hole, CoW, ZFS, Btrfs), criptografía (SSH, TLS, mTLS, LUKS2), automatización (Cron, Systemd Timers, Chrony), logging/AI SRE, Kernel Linux (Ring 0/3, Syscalls, IRQ, MMU, VFS, FUSE, LKM, SysFS, Sysctl, initramfs, OSTree/bootc, DKMS/kABI, Livepatch, Taint/Lockdown, eBPF/XDP, io_uring, EEVDF, sched_ext, Device Tree, Zephyr RTOS, familias UNIX/AIX/BSD/Solaris/XNU/Windows/Android) y Virtualización/Contenedores/Cloud/HPC (VT-x/AMD-V, SLAT, IOMMU/VFIO, KVM/QEMU, ESXi, Hyper-V/WSL2, Xen, Jails, LPAR, Zones, Namespaces/Cgroups v2, Firecracker, OpenStack, Kubernetes/K9s/KubeVirt y Slurm).
files:
  guide: linux/administrator/GLOSARIO.md
  script: null
  terraform: null
---

# 📚 Glosario Técnico de Administración Linux: Kernel, Virtualización, Almacenamiento & Resiliencia

Este glosario funciona como **diccionario técnico vivo e índice conceptual cruzado** del plan de estudios de administración de sistemas Linux. La idea pedagógica es mantener las guías de clase ágiles y legibles en voz alta, delegando aquí la **definición técnica precisa**, su **impacto real en producción** y los **enlaces directos a la documentación oficial** de cada tecnología.

---

## 🧭 Índice Temático y Alfabético

| Término | Tecnologías Relacionadas | Laboratorios de Aplicación |
| :--- | :--- | :--- |
| [**Write-Intent Bitmap**](#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura) | `mdadm`, `lvmraid` (`_rmeta`), ZFS, Btrfs | [Lab 3.7](raid/raid_teoria.md), [Lab 3.8](raid/raid_mdadm.md), [Lab 3.9](raid/raid_lvm.md), [Lab 4.5](raid/integrador_aws/trabajo_integrador_raid.md) |
| [**Write-Hole (Agujero de Escritura)**](#write-hole-agujero-de-escritura) | RAID 4/5/6, `mdadm`, LVM, Btrfs | [Lab 3.7](raid/raid_teoria.md), [Lab 3.11](raid/raid_zfs.md) |
| [**Copy-on-Write (CoW)**](#copy-on-write-cow-copia-en-escritura) | ZFS, Btrfs, LVM Snapshots | [Lab 3.1](filesystems/anatomia_filesystems.md), [Lab 3.10](raid/raid_btrfs.md), [Lab 3.11](raid/raid_zfs.md), [Integrador Btrfs](trabajo_integrador_btrfs/trabajo_integrador_btrfs.md) |
| [**Dirty Time Logs (DTL) / TXG**](#dirty-time-logs-dtl--transaction-groups-txg) | OpenZFS | [Lab 3.11](raid/raid_zfs.md), [Integrador ZFS](trabajo_integrador_zfs/trabajo_integrador_zfs.md) |
| [**ZIL (ZFS Intent Log) & SLOG**](#zil-zfs-intent-log--slog-separate-intent-log) | OpenZFS, NVMe | [Lab 3.11](raid/raid_zfs.md) |
| [**Hot Spare**](#hot-spare-disco-de-reserva-en-caliente) | `mdadm`, LVM, ZFS | [Lab 3.8](raid/raid_mdadm.md), [Lab 4.5](raid/integrador_aws/trabajo_integrador_raid.md) |
| [**Scrubbing y Resilvering**](#scrubbing-y-resilvering) | `mdadm`, Btrfs, ZFS | [Lab 3.8](raid/raid_mdadm.md), [Lab 3.10](raid/raid_btrfs.md), [Lab 3.11](raid/raid_zfs.md), [Lab 4.5](raid/integrador_aws/trabajo_integrador_raid.md) |
| [**Hard Link vs Soft Link (Enlaces en Filesystems)**](#hard-link-vs-soft-link-enlaces-en-filesystems) | VFS, ext4, XFS, Btrfs, `ln`, `find`, `rsync` | [Lab 3.12](filesystems/enlaces_hard_soft_links.md) |
| [**Criptografía Simétrica vs Asimétrica e Híbrida**](#criptografía-simétrica-vs-asimétrica-y-criptografía-híbrida) | AES, RSA, Ed25519, TLS, SSH, LUKS | [Lab 3.3 Fundamentos](cifrado/fundamentos_criptografia_llaves_certificados.md), [Lab 3.3.0](cifrado/cifrado_arquitecturas_comparativa.md) |
| [**Challenge-Response (Reto-Respuesta)**](#challenge-response-reto-respuesta) | SSH (`id_ed25519`), AWS EC2 (`.pem`) | [Lab 3.3 Fundamentos](cifrado/fundamentos_criptografia_llaves_certificados.md) |
| [**Mutual TLS (mTLS) y PKI**](#mutual-tls-mtls-y-autoridad-certificadora-pki) | OpenVPN, TLS 1.3, Certificados X.509 | [Lab 3.3 Fundamentos](cifrado/fundamentos_criptografia_llaves_certificados.md) |
| [**Perfect Forward Secrecy (PFS)**](#perfect-forward-secrecy-pfs) | Diffie-Hellman efímero, TLS, OpenVPN | [Lab 3.3 Fundamentos](cifrado/fundamentos_criptografia_llaves_certificados.md) |
| [**Cron, Anacron, at y Systemd Timers**](#automatización-planificación-de-tareas-y-sincronización-ntp) | `crontab`, `anacron`, `at`, `systemd.timer`, `chronyd` | [Lab 2.0](automatizacion/automatizacion_arquitecturas_comparativa.md), [Lab 2.4](automatizacion/cron_crontab_planificacion.md), [Lab 2.5](automatizacion/anacron_at_tareas_asincronas.md), [Lab 2.6](automatizacion/systemd_timers_vs_cron_chrony.md) |
| [**Syslog, Severities, Facilities y PRI (RFC 3164/5424)**](#gestión-de-logs-syslog-journald-y-arquitecturas-de-logging) | `syslog`, `logger`, `rsyslog`, `dmesg` | [Teoría 3.18](logs/logs_arquitecturas_teoria.md), [Lab 3.19](logs/logs_fundamentos_varlog_dmesg.md) |
| [**systemd-journald, journalctl y FSS**](#gestión-de-logs-syslog-journald-y-arquitecturas-de-logging) | `systemd-journald`, `journalctl`, `-o json` | [Teoría 3.18](logs/logs_arquitecturas_teoria.md), [Lab 3.20](logs/journald_journalctl_troubleshooting.md) |
| [**rsyslog (RainerScript), TLS, RELP y Disk Queues**](#gestión-de-logs-syslog-journald-y-arquitecturas-de-logging) | `rsyslogd`, `imfile`, `omfwd`, `gtls`/`ossl` | [Teoría 3.18](logs/logs_arquitecturas_teoria.md), [Lab 3.21](logs/rsyslog_filtrado_plantillas_tls_colas.md) |
| [**logrotate, Event Queues, SIEM, Drain3 y Log Prompt Injection**](#gestión-de-logs-syslog-journald-y-arquitecturas-de-logging) | `logrotate`, Kafka, Loki, ELK, Splunk, AI SRE | [Teoría 3.18](logs/logs_arquitecturas_teoria.md), [Lab 3.22](logs/logging_centralizado_estructurado_ai_sre.md) |
| [**POSIX y Familias de Sistemas Operativos (UNIX, AIX, Solaris, BSD, XNU, Windows NT, Linux y Android)**](#posix-y-familias-de-sistemas-operativos-unix-aix-solaris-bsd-xnu-windows-nt-linux-y-android) | SysV, BSD, IBM AIX, Solaris, macOS XNU, NT, Android | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md) |
| [**Núcleo Monolítico Modular, Ring 0/3, Syscalls y Preemption**](#núcleo-monolítico-modular-ring-03-syscalls-y-preemption) | Kernel Linux, LKM, `strace`, `PREEMPT_RT` | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md) |
| [**IRQ (Interrupciones de Hardware), DMA y Top/Bottom Half**](#irq-interrupciones-de-hardware-dma-y-topbottom-half) | `softirq`, `kworker`, PCIe, NIC, Intel FRED | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md) |
| [**MMU (Memory Management Unit), Paginación, Page Cache y OOM Killer**](#mmu-memory-management-unit-paginación-page-cache-y-oom-killer) | Memoria virtual, swap, `SLUB`, HugePages | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Lab 1.8](kernel/sysfs_proc_sysctl_tuning.md) |
| [**VFS (Virtual File System) y FUSE**](#vfs-virtual-file-system-y-fuse) | ext4, XFS, Btrfs, `sshfs`, `gocryptfs`, `borg` | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Lab 3.1](filesystems/anatomia_filesystems.md) |
| [**LKM (Loadable Kernel Modules), modprobe y Blacklists**](#lkm-loadable-kernel-modules-modprobe-y-blacklists) | `.ko`, `lsmod`, `modprobe`, `depmod`, `modprobe.d` | [Lab 1.7](kernel/modulos_lkm_blacklists_boot.md), [Lab 3.23](kernel/modulo_lkm_firmware_sim.md) |
| [**sysfs (/sys), procfs (/proc) y udev**](#sysfs-sys-procfs-proc-y-udev) | `/sys`, `/proc`, `kobject`, `udevadm` | [Lab 1.8](kernel/sysfs_proc_sysctl_tuning.md) |
| [**sysctl (/proc/sys)**](#sysctl-procsys) | `sysctl -w/-p/--system`, `/etc/sysctl.d/` | [Lab 1.8](kernel/sysfs_proc_sysctl_tuning.md), [Lab 3.25](kernel/seguridad_ataques_kernel_ebpf.md) |
| [**initramfs (cpio) y switch_root**](#initramfs-cpio-y-switch_root) | `initrd`, `cpio.gz`, `/init`, BusyBox, `dracut` | [Lab 1.7](kernel/modulos_lkm_blacklists_boot.md), [Lab 3.24](kernel/compilacion_kernel_initramfs.md) |
| [**BLS (Boot Loader Specification) y UKI**](#bls-boot-loader-specification-y-uki) | `/boot/loader/entries`, GRUB2, Unified Kernel Image | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Lab 1.7](kernel/modulos_lkm_blacklists_boot.md) |
| [**Distros Inmutables (OSTree, rpm-ostree y bootc)**](#distros-inmutables-ostree-rpm-ostree-y-bootc) | Fedora Atomic, Image Mode, `akmods`, `dm-verity`, `fs-verity`, `sysext` | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Lab 2.7](kernel/actualizacion_kernel_rollback_livepatch.md) |
| [**DKMS y kABI**](#dkms-y-kabi) | `dkms`, `linux-headers`, módulos out-of-tree | [Lab 2.7](kernel/actualizacion_kernel_rollback_livepatch.md) |
| [**Livepatching (kpatch / Canonical Livepatch) y kexec**](#livepatching-kpatch--canonical-livepatch-y-kexec) | `/sys/kernel/livepatch`, `ftrace`, `kexec` | [Lab 2.7](kernel/actualizacion_kernel_rollback_livepatch.md) |
| [**Kernel Taint, KASLR, kptr_restrict y Kernel Lockdown**](#kernel-taint-kaslr-kptr_restrict-y-kernel-lockdown) | `/proc/sys/kernel/tainted`, ASLR, Secure Boot, TOCTOU | [Lab 3.23](kernel/modulo_lkm_firmware_sim.md), [Lab 3.25](kernel/seguridad_ataques_kernel_ebpf.md) |
| [**eBPF, BPF Verifier, JIT y CO-RE (BTF)**](#ebpf-bpf-verifier-jit-y-co-re-btf) | `bpftool`, `bpftrace`, XDP, Cilium, Tetragon | [Lab 3.25](kernel/seguridad_ataques_kernel_ebpf.md) |
| [**io_uring, EEVDF, PSI, TCP BBR y sched_ext**](#io_uring-eevdf-y-sched_ext) | Kernel `6.6+` / `6.12+` / `7.x`, async I/O, CAS | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md) |
| [**Confidential Computing (AMD SEV-SNP e Intel TDX)**](#confidential-computing-amd-sev-snp-e-intel-tdx) | Cifrado RAM VM, atestación hardware, Cloud | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Device Tree (.dtb), MMU, uClinux y Zephyr RTOS**](#device-tree-dtb-mmu-uclinux-y-zephyr-rtos) | Edge, ARM64, Yocto, Buildroot, OpenWrt, MCU | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Lab 3.24](kernel/compilacion_kernel_initramfs.md) |
| [**Android GKI y Binder IPC**](#android-gki-y-binder-ipc) | Generic Kernel Image, Rust Binder (`6.18`), AOSP | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md) |
| [**Hipervisor Tipo 1 (Bare-Metal) vs Tipo 2 (Hosted)**](#hipervisor-tipo-1-bare-metal-vs-tipo-2-hosted) | VMware ESXi, KVM, Hyper-V, Xen, VirtualBox | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Virtualización Asistida por Hardware (VT-x, AMD-V, SLAT/EPT e IOMMU)**](#virtualización-asistida-por-hardware-intel-vt-x-amd-v-slatept-e-iommu) | VMX Ring -1, Nested Paging, `VT-d`, `AMD-Vi` | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Virtualización Completa, Paravirtualización (VirtIO) y Emulación**](#virtualización-completa-paravirtualización-virtio-y-emulación) | QEMU TCG, `virtio-blk`, `virtio-net`, `balloon` | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**KVM, QEMU, libvirt y Proxmox VE**](#kvm-qemu-libvirt-y-proxmox-ve) | `/dev/kvm`, `virsh`, `virt-install`, cluster PVE | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Xen, VMware ESXi, Microsoft Hyper-V y WSL2**](#xen-vmware-esxi-microsoft-hyper-v-y-wsl2) | Dom0/DomU, VMkernel, `hv_vmbus`, kernel WSL2 | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**SR-IOV y VFIO (PCIe Passthrough)**](#sr-iov-y-vfio-pcie-passthrough) | GPU passthrough, NIC VFs, bypass hipervisor | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**AIX LPAR y WPAR (IBM PowerVM)**](#aix-lpar-y-wpar-ibm-powervm) | POWER, DLPAR, VIOS, Workload Partitions | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Solaris Zones (Containers) y LDOMs**](#solaris-zones-containers-y-ldoms) | Global Zone, Branded Zones, SMF, ZFS | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**FreeBSD Jails y bhyve**](#freebsd-jails-y-bhyve) | `jail(8)`, VNET, ZFS datasets, `bhyve` | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Contenedores Linux: chroot, Namespaces, Cgroups v2, OCI, Docker y Podman**](#contenedores-linux-chroot-namespaces-cgroups-v2-oci-docker-y-podman) | `clone()`, `runc`, `containerd`, rootless, `seccomp` | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md), [Lab 2.3](systemd/systemd-cgroups.md) |
| [**MicroVMs y Sandboxes: Firecracker, Kata Containers y gVisor**](#microvms-y-sandboxes-firecracker-kata-containers-y-gvisor) | AWS Lambda, multi-tenant cloud, interceptación syscalls | [Guía Maestra 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Cloud IaaS y OpenStack (Nova, Neutron, Cinder, Glance, Keystone)**](#cloud-iaas-y-openstack-nova-neutron-cinder-glance-keystone) | AWS Nitro, SDN, Ceph, Bare-Metal Ironic | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**Orquestación: Kubernetes (K8s), K9s y KubeVirt**](#orquestación-kubernetes-k8s-k9s-y-kubevirt) | Control Plane, Pods, consola TUI `k9s`, VMs en K8s | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**HPC (High-Performance Computing) y Slurm**](#hpc-high-performance-computing-y-slurm) | `slurmctld`, `slurmd`, MPI, RDMA/InfiniBand, GPUs IA | [Teoría 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md) |
| [**X11 / X.Org, Modelo Invertido y $DISPLAY**](#sistemas-gráficos-en-linux-x11xorg-wayland-gestores-y-acceso-remoto) | `Xorg`, `xdpyinfo`, `xwininfo`, `$DISPLAY` | [Teoría 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md), [Lab 3.27](graficos/x11_inspeccion_headless_xvfb_xauth.md) |
| [**Display Server, Compositor, WM, DE y Display Manager**](#sistemas-gráficos-en-linux-x11xorg-wayland-gestores-y-acceso-remoto) | `LightDM`, `GDM3`, `SDDM`, `Sway`, `KDE`, `GNOME`, `XFCE` | [Teoría 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md) |
| [**Wayland, DMA-BUF, XWayland y PipeWire**](#sistemas-gráficos-en-linux-x11xorg-wayland-gestores-y-acceso-remoto) | `$WAYLAND_DISPLAY`, `Xwayland`, `xdg-desktop-portal` | [Teoría 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md), [Lab 3.27](graficos/x11_inspeccion_headless_xvfb_xauth.md) |
| [**DRM / KMS, modesetting, xhost, xauth y Xvfb**](#sistemas-gráficos-en-linux-x11xorg-wayland-gestores-y-acceso-remoto) | `MIT-MAGIC-COOKIE-1`, `Xvfb`, `xorg.conf.d`, `cvt` | [Teoría 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md), [Lab 3.27](graficos/x11_inspeccion_headless_xvfb_xauth.md) |
| [**SSH X11 Forwarding (-X/-Y), Waypipe, VNC, RDP, SPICE y XDMCP**](#sistemas-gráficos-en-linux-x11xorg-wayland-gestores-y-acceso-remoto) | `sshd`, `TigerVNC`, `noVNC`, `Remmina`, `Guacamole` | [Teoría 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md), [Lab 3.28](graficos/acceso_grafico_remoto_ssh_x11_vnc.md), [Lab 3.30](graficos/podman_x11_vnc_novnc_doom.md) |
| [**Terminales Tontas, Thin Clients (POS/LTSP) y Zero Clients HTML5**](#sistemas-gráficos-en-linux-x11xorg-wayland-gestores-y-acceso-remoto) | `VT100`, `LTSP`, `x11vnc`, `KasmVNC`, `noVNC`, `guacd` | [Teoría 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md), [Lab 3.30](graficos/podman_x11_vnc_novnc_doom.md) |
| [**Accesibilidad en Linux: AccessX, Orca, brltty y kmag**](#sistemas-gráficos-en-linux-x11xorg-wayland-gestores-y-acceso-remoto) | `StickyKeys`, `SlowKeys`, `orca --setup`, `brltty` | [Teoría 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md) |

---

## Conceptos Técnicos en Profundidad

---

### Write-Intent Bitmap (Mapa de Bits de Intención de Escritura)

Un **write-intent bitmap** (mapa de bits de intención de escritura) es un mecanismo de seguimiento que registra qué regiones de un disco están a punto de ser modificadas antes de que ocurra la escritura real. 

Su propósito principal es **evitar la reconstrucción completa de un arreglo de discos tras un corte de energía o una desconexión temporal**: al reiniciar, el sistema consulta el mapa de bits y sincroniza únicamente los bloques que quedaron a medias (*"sucios"*).

Para explicarlo de forma clara, la distinción fundamental está entre los **gestores de bloques tradicionales (RAID / LVM)**, que sobrescriben datos en el mismo lugar y necesitan este mapa como salvavidas, y los **sistemas de archivos Copy-on-Write (ZFS / Btrfs)**, que por su diseño arquitectónico no lo necesitan.

---

#### 💡 La Analogía para Explicarlo Rápido

Imagina que estás editando una enciclopedia impresa de 10,000 páginas y tienes un clon exacto de respaldo en otra habitación:

* **Sin bitmap:** Si se corta la luz mientras editas, al volver no sabes en qué página estabas trabajando. Tienes que comparar las 10,000 páginas una por una para asegurarte de que ambos libros sean idénticos (horas de escaneo inútil).
* **Con Write-Intent Bitmap (RAID/LVM):** Antes de tocar una página, anotas en un post-it: *"Voy a modificar el Capítulo 4"*. Escribes el cambio y luego borras el post-it. Si se corta la luz en medio, al volver solo miras el post-it y revisas únicamente el Capítulo 4. Sincronizar toma segundos en lugar de horas.
* **Enfoque Copy-on-Write (ZFS/Btrfs):** Nunca borras ni escribes encima de una página existente. Escribes la versión nueva en una hoja en blanco y, solo cuando terminas, actualizas el índice general. Si se va la luz a mitad de camino, el índice sigue apuntando a la hoja vieja intacta; no hay nada desincronizado que buscar.

---

#### ⚙️ Cómo Funciona en Cada Tecnología

##### 1. RAID por software (`mdadm`)

Es el caso de uso clásico. En un RAID 1, 5, 6 o 10, el arreglo se divide en regiones o *chunks* (por ejemplo, de 64 MB). Cada región está representada por un solo **bit** en el bitmap (almacenado en una zona interna del disco con `--bitmap=internal` o en un archivo externo):

```
                   ESTRUCTURA DEL DISCO EN MDADM
┌─────────────────────────────────┬─────────────────────────────────┐
│     Superbloque v1.2 (4 KiB)    │    Write-Intent Bitmap Interno  │
│  [UUID, Nivel, Eventos, Chunks] │     [ 0 | 0 | 1 | 0 | 1 | 0 ]   │
└─────────────────────────────────┴─────────────────────────────────┘
                                           │         │
                   Region 2 (Limpia) ──────┘         │
                   Region 3 (Escritura en curso) ────┘ (Bit = 1)
```

1. **Antes de escribir:** El bit de esa región pasa de `0` a `1` (indicando "escritura en curso").
2. **Durante la escritura:** Los datos y la paridad se escriben en todos los discos del RAID.
3. **Al finalizar:** Cuando el sistema confirma que todos los discos escribieron el dato exitosamente, el bit vuelve a `0` (normalmente con un ligero retraso para agrupar operaciones contiguas y evitar desgaste del disco).

* **El beneficio:** Si un disco se desconecta por un cable flojo durante 5 minutos o el servidor sufre un apagón, al volver `mdadm` lee los bits en `1` y solo resincroniza esos fragmentos específicos.
* **El costo:** Añade una pequeña penalización de rendimiento en escrituras aleatorias intensivas porque debe actualizar el bitmap antes de volcar el dato al disco.

> 🔬 **Práctica en laboratorio:**
> - Creación con bitmap: `mdadm --create /dev/md0 --bitmap=internal ...` ([Lab 3.8](raid/raid_mdadm.md#4-laboratorio-principal-raid-5--hot-spare--bitmap))
> - Inspección forense: `mdadm --examine-bitmap /dev/sdX` ([Lab 3.8](raid/raid_mdadm.md#5-inspección-forense-superbloque-y-bitmap))

##### 2. LVM (Logical Volume Manager / `lvmraid`)

En LVM (`lvm.conf`), cuando creas volúmenes espejados o con paridad (como `raid1`, `raid5`, `raid6`), LVM utiliza por debajo el mismo motor del kernel que `mdadm` (el driver `md-mod`).

En la terminología de LVM, este write-intent bitmap se gestiona de forma transparente a través de los **Sub-LVs de metadatos** (`_rmeta`):

```
      Logical Volume RAID5: lv_prod [10 GB]
     ┌──────────────────────┬──────────────────────┬──────────────────────┐
     ▼                      ▼                      ▼
  Disco PV 1             Disco PV 2             Disco PV 3
┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐
│  lv_prod_rmeta_0   │ │  lv_prod_rmeta_1   │ │  lv_prod_rmeta_2   │  <-- Superbloque MD +
│  (1 PE = 4 MiB)    │ │  (1 PE = 4 MiB)    │ │  (1 PE = 4 MiB)    │      Write-Intent Bitmap
├────────────────────┤ ├────────────────────┤ ├────────────────────┤
│  lv_prod_rimage_0  │ │  lv_prod_rimage_1  │ │  lv_prod_rimage_2  │  <-- Bloques de datos y
│  (Franja de datos) │ │  (Franja de datos) │ │  (Franja Paridad)  │      paridad XOR
└────────────────────┘ └────────────────────┘ └────────────────────┘
```

Cumple exactamente la misma función: llevar el registro de qué regiones (*regions*) están siendo modificadas para evitar resincronizaciones completas tras un cierre inesperado, o para saber qué bloques cambiaron mientras un disco estuvo temporalmente ausente.

> 🔬 **Práctica en laboratorio:**
> - Arquitectura de Sub-LVs: `lvs -a -o+devices` ([Lab 3.9](raid/raid_lvm.md#1-arquitectura-cómo-combina-lvm2-su-propia-metáfora-con-md-del-kernel))

##### 3. ZFS y Btrfs (Por qué es diferente aquí)

Si alguien pregunta cómo configurar un *write-intent bitmap* en ZFS o Btrfs, la respuesta técnica es que **no usan write-intent bitmaps tradicionales** porque son sistemas **Copy-on-Write (CoW)** transaccionales que integran el gestor de volúmenes y el sistema de archivos en una sola capa.

* **Por qué no sufren el problema de raíz:** En RAID clásico y LVM, si un bloque se sobrescribe a medias durante un apagón, los discos quedan con datos distintos en la misma posición física (fenómeno conocido como [*write hole*](#write-hole-agujero-de-escritura)). En ZFS y Btrfs nunca se sobrescribe un bloque activo; los datos nuevos se escriben en espacio libre y el árbol de metadatos se actualiza de forma atómica al final. Si hay un apagón, la transacción incompleta simplemente se descarta y el sistema sigue siendo 100% consistente.
* **Qué pasa si un disco se desconecta temporalmente:** Como ZFS y Btrfs conocen la estructura del árbol de archivos y cada bloque tiene un **número de transacción** (llamado `TXG` en ZFS o `generation` en Btrfs) además de sumas de verificación (*checksums*), si un disco se desconecta unos minutos y vuelve, el sistema no necesita un bitmap de regiones brutas: simplemente recorre el árbol de metadatos buscando qué transacciones son más recientes que la última registrada en ese disco y copia solo esos bloques exactos (en ZFS esto se conoce como [*DTL - Dirty Time Logs*](#dirty-time-logs-dtl--transaction-groups-txg)).
* **No confundir con el ZIL (ZFS Intent Log):** A veces se confunde el *write-intent bitmap* con el **ZIL** de ZFS (o el *log tree* de Btrfs). Aunque ambos tienen la palabra *"intent"*, el ZIL no es un mapa de bits de regiones sucias, sino un diario (*journal*) donde se guardan los datos completos de las escrituras síncronas para confirmarlas rápido al cliente antes de volcarlas definitivamente al pool en el siguiente commit de TXG.

---

#### 📊 Tabla Comparativa Resumen

| Tecnología | ¿Usa Write-Intent Bitmap? | Mecanismo ante un apagón o desconexión breve | Nivel en el que opera |
| :--- | :---: | :--- | :--- |
| **RAID (`mdadm`)** | **Sí** (Interno o externo) | Revisa los bits en `1` y copia solo esos segmentos de disco (*chunks*) de un disco a otro. | Bloques ciegos (no sabe si hay archivos o espacio vacío). |
| **LVM (`lvmraid`)** | **Sí** (En volúmenes `_rmeta`) | Igual que `mdadm`: sincroniza únicamente las regiones marcadas como sucias en el bitmap. | Bloques lógicos (*Logical Extents*). |
| **ZFS** | **No** (Usa CoW + DTL) | Transacciones atómicas (CoW) evitan corrupción por apagón. Si un disco vuelve tras caer, usa *Dirty Time Logs* (TXGs) para enviar solo bloques nuevos. | Sistema de archivos y bloques integrados (con *checksums* de 256 bits). |
| **Btrfs** | **No** (Usa CoW + Generation Trees) | Transacciones atómicas (CoW). Sincroniza basándose en el número de generación de los árboles de metadatos y valida con *checksums*. | Sistema de archivos y bloques integrados (con *checksums*). |

---

### Write-Hole (Agujero de Escritura)

El **write-hole** es un defecto estructural inherente a los arreglos RAID 4, 5 y 6 tradicionales basados en paridad que operan a nivel de bloques independientes. Ocurre cuando se interrumpe la alimentación eléctrica en el microsegundo exacto entre la escritura del nuevo bloque de datos y la escritura del bloque de paridad correspondiente. 

Como el sistema tradicional no tiene transacciones atómicas, la paridad calculada deja de coincidir matemáticamente con los datos de la franja (*stripe*). El desastre se manifiesta silenciosamente cuando más adelante un disco falla: al intentar reconstruir el disco ausente aplicando la fórmula XOR sobre los discos restantes, los datos calculados resultan corrompidos.

* **Mitigaciones tradicionales:** [Write-Intent Bitmap](#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura) (acota el tiempo de resincronización), diarios en SSD rápido (`mdadm --write-journal`), o baterías BBU en controladoras hardware.
* **Eliminación arquitectónica:** ZFS elimina por diseño el write-hole usando *RAIDZ* con bandas de ancho variable y asignación [Copy-on-Write](#copy-on-write-cow-copia-en-escritura).
* 📖 [Ver explicación en Lab 3.7: RAID Teoría (Sección 3.2)](raid/raid_teoria.md#32-el-write-hole-agujero-de-escritura-y-el-bitmap).

---

### Copy-on-Write (CoW / Copia en Escritura)

Estrategia de gestión de almacenamiento donde los bloques de datos existentes nunca son sobrescritos *in-place*. Cuando un bloque se modifica:
1. El sistema asigna un bloque libre nuevo en otra parte física del disco.
2. Escribe los nuevos datos en ese nuevo bloque.
3. Actualiza el puntero en el árbol de metadatos para que apunte a la nueva ubicación mediante un commit transaccional atómico.
4. Si la operación se interrumpe antes de la confirmación final, el árbol sigue apuntando al bloque anterior, garantizando cero corrupción.

Habilita snapshots instantáneos $O(1)$, clones de cero copias (*reflinks*) y elimina la necesidad de bitmaps de rescate.
* 📖 [Ver implementación en Lab 3.10: Btrfs](raid/raid_btrfs.md) y [Lab 3.11: OpenZFS](raid/raid_zfs.md).

---

### Dirty Time Logs (DTL) / Transaction Groups (TXG)

Mecanismo interno de **OpenZFS** para el rastreo de desincronizaciones entre miembros de un vdev espejo o RAIDZ. En lugar de un bitmap de bloques físicos, ZFS asigna un identificador secuencial monótono a cada grupo de transacciones (**TXG**). 

Si un disco se desconecta temporalmente, ZFS registra en los *Dirty Time Logs* el rango de TXGs que ese disco se perdió. Cuando el disco se reconecta, ZFS examina únicamente los bloques cuyo TXG pertenezca a ese intervalo y realiza un *resilvering dirigido*, sin tener que escanear todo el pool.
* 📖 [Ver arquitectura OpenZFS en Lab 3.11](raid/raid_zfs.md).

---

### ZIL (ZFS Intent Log) & SLOG (Separate Intent Log)

Área de almacenamiento temporal transaccional utilizada exclusivamente por OpenZFS para garantizar la persistencia de **escrituras síncronas** (`O_SYNC`, bases de datos, NFS) sin esperar el intervalo de commit regular del pool (que típicamente ocurre cada 5 segundos por TXG).

* **Diferencia con el Bitmap:** No marca regiones sucias para sincronizar más tarde; almacena la carga útil (*payload*) completa del dato de forma transaccional.
* **SLOG:** Cuando el ZIL se coloca en un dispositivo de almacenamiento ultrarrápido dedicado (como un disco NVMe o Intel Optane), se denomina SLOG (*Separate Log*).
* 📖 [Ver sección SLOG/ZIL en Lab 3.11](raid/raid_zfs.md).

---

### Hot Spare (Disco de Reserva en Caliente)

Unidad de almacenamiento conectada físicamente al sistema e integrada en la configuración del arreglo RAID que permanece en estado de reposo (*idle* o *standby*). 

Si uno de los discos activos experimenta un fallo irrecuperable o es expulsado por errores de I/O, el subsistema (kernel `md` o demonio `mdmonitor`/ZFS) detecta la anomalía e **inicia de inmediato la reconstrucción sobre el disco de reserva de manera 100% desatendida**, minimizando la ventana de vulnerabilidad del arreglo.
* 📖 [Ver configuración en Lab 3.8: mdadm](raid/raid_mdadm.md#4-laboratorio-principal-raid-5--hot-spare--bitmap) y [Lab 4.5: Integrador AWS](raid/integrador_aws/trabajo_integrador_raid.md#fase-1-creación-del-arreglo-y-servicio-web).

---

### Scrubbing y Resilvering

* **Scrub (Auditoría de Paridad):** Proceso periódico en segundo plano que lee exhaustivamente todos los bloques del arreglo para verificar que los datos coincidan con su paridad o checksum. Si encuentra inconsistencias, las repara automáticamente tomando los bloques válidos del resto de discos.
* **Resilvering / Rebuild (Reconstrucción):** Proceso de regeneración y copia de datos hacia un disco nuevo que reemplaza a uno averiado. En RAID tradicional (`mdadm`) se reconstruye el espacio completo del dispositivo; en ZFS/Btrfs solo se reconstruyen los bloques asignados y referenciados.
* 📖 [Ver procedimientos de Scrub en Lab 3.8](raid/raid_mdadm.md#8-scrub-auditoría-de-paridad-en-segundo-plano), [Lab 3.10](raid/raid_btrfs.md) y [Lab 3.11](raid/raid_zfs.md).

---

### Hard Link vs Soft Link (Enlaces en Filesystems)

La arquitectura de archivos en sistemas Unix/Linux implementa una separación estricta entre el **nombre visible** del archivo (`dentry` o entrada de directorio) y la **estructura de almacenamiento real** (`inodo` y bloques de datos).

* **Hard Link (Enlace Duro):** Es una segunda entrada de directorio (`dentry`) que apunta de manera directa y equivalente al **mismo número de inodo** dentro del mismo sistema de archivos. No duplica datos, no consume espacio en disco y está gobernado por el contador `nlink`. Al borrar un archivo con `rm`, el kernel únicamente llama a `unlink()`; los bloques de datos físicos solo se devuelven al bitmap libre cuando `nlink == 0` y ningún proceso en ejecución mantiene el descriptor de archivo abierto.
  - *Restricciones:* No puede cruzar fronteras de particiones (`EXDEV`) ni apuntar a directorios para prevenir bucles cíclicos en el grafo del VFS.
* **Soft Link (Enlace Simbólico o Symlink):** Es un archivo independiente de tipo `l` (`S_IFLNK`) con su propio inodo, cuyo contenido de datos es la cadena de texto con la ruta hacia el destino.
  - *Ventajas y Riesgos:* Puede cruzar cualquier sistema de archivos, montajes remotos y enlazar carpetas completas. Si el destino se borra o renombra, el symlink queda en estado **roto (*dangling*)**, retornando el error `ENOENT`.
* 💡 **Casos de Producción:** Despliegues **Zero-Downtime** mediante switches atómicos con `ln -sfn`, versionado de bibliotecas dinámicas (`.so` SONAME), y deduplicación masiva en respaldos instantáneos con `rsync --link-dest`.
* 📖 [Ver guía teórica completa y laboratorio práctico en Lab 3.12](filesystems/enlaces_hard_soft_links.md).

---

### LUKS2 & Argon2id (Cifrado de Bloques)

* **LUKS2 (Linux Unified Key Setup v2):** Estándar de facto moderno para el cifrado de datos en reposo a nivel de bloques (*Full Disk Encryption* o FDE) en el kernel de Linux a través del subsistema `dm-crypt`. A diferencia de LUKS1, incorpora una cabecera basada en JSON extensible, cabeceras redundantes primarias y secundarias con detección de auto-curación (*auto-repair*), y soporte para hasta 32 ranuras de claves (*keyslots*).
* **Argon2id (KDF):** Función de derivación de claves por defecto en LUKS2, diseñada específicamente para neutralizar ataques masivos de fuerza bruta con clústeres de GPUs y ASICs al ser intensiva en memoria RAM (*memory-hard*).
* 📖 [Ver guía de cifrado LUKS2 en Lab 3.3](luks/luks.md) y [Comparativa de Arquitecturas de Cifrado](cifrado/cifrado_arquitecturas_comparativa.md).

---

### Keyslots y Desbloqueo Moderno (TPM 2.0 & Clevis/Tang)

* **Keyslots (Ranuras de Claves):** Esquema criptográfico de dos niveles donde una clave maestra aleatoria de 256 bits (que cifra los bloques físicos) se encuentra cifrada de forma independiente en múltiples ranuras. Esto permite revocar o rotar contraseñas de administradores mediante `luksKillSlot` sin necesidad de recifrar los datos del disco.
* **TPM 2.0 (`systemd-cryptenroll`):** Desbloqueo automático del volumen cifrado durante el arranque mediante el chip de seguridad físico de la placa base, sellado a los registros de configuración de plataforma (PCR 0, 2, 7 para Secure Boot). Si el firmware o el kernel son alterados, el TPM se niega a liberar la clave.
* **NBDE (Network-Bound Disk Encryption - Clevis/Tang):** Arquitectura para centros de datos donde un oráculo en red (servidor Tang) suministra la clave de desbloqueo al cliente (Clevis) a través de la LAN corporativa. Si el servidor o disco físico es retirado de las instalaciones, el volumen no puede desbloquearse.
* 📖 [Ver sección de automatización en Lab 3.3](luks/luks.md#5-el-escenario-moderno-automatización-con-tpm-20-y-clevistang).

---

### GnuPG (GPG) y Firmas de Repositorios / Backups Asimétricos

* **Criptografía Asimétrica:** Paradigma criptográfico basado en un par de claves: una **clave pública** (ampliamente distribuida) y una **clave privada** (mantenida bajo estricta custodia).
* **Subclaves OpenPGP:** Estructura jerárquica donde la clave primaria posee la capacidad de certificación `[C]`, delegando las operaciones diarias en subclaves operativas de firma `[S]` y de cifrado `[E]`.
* **APT `[signed-by=...]`:** Estándar moderno de repositorios en Debian/Ubuntu que confina la clave binaria desarmada (`gpg --dearmor`) bajo `/etc/apt/keyrings/`, reemplazando el inseguro e histórico `apt-key add` global.
* **Backups Asimétricos:** Técnica de seguridad donde los servidores de base de datos o web solo almacenan la **clave pública** para cifrar respaldos automáticos en cron. Si el servidor es atacado, el adversario no puede descifrar los backups históricos porque la clave privada no existe en esa máquina.
* 📖 [Ver laboratorio completo de GPG y backups en Lab 3.4b](gpg/gpg_firmas_repositorios_backups.md).

---

### Estrategias de Backup, Resiliencia y Deduplicación

* **RPO (Recovery Point Objective):** Métrica de negocio que cuantifica la cantidad máxima de datos que la organización tolera perder ante un desastre, expresada en tiempo (ej: 1 hora de transacciones).
* **RTO (Recovery Time Objective):** Métrica que define el tiempo límite permitido desde que ocurre la catástrofe hasta que el servicio vuelve a estar 100% operativo (tiempo de restauración).
* **Regla 3-2-1:** Estándar de oro de respaldos: mantener **3** copias de los datos, en **2** medios o tecnologías diferentes, con **1** copia fuera de sitio (*offsite* o en la nube).
* **Backup Completo (Full):** Respaldo de la totalidad de los archivos o bloques seleccionados en un instante dado. RTO mínimo (extracción directa), pero máximo consumo de espacio y tiempo de generación.
* **Backup Incremental:** Respaldo exclusivo de los datos creados o modificados desde el **último backup** (sea Full o Incremental). Ahorro masivo de espacio, pero exige restaurar el Full inicial y la cadena completa de incrementales.
* **Backup Diferencial:** Respaldo acumulativo de todas las modificaciones producidas desde el **último backup completo**. La restauración solo requiere el Full inicial y el último diferencial.
* **CDP (Continuous Data Protection):** Captura continua de cambios en tiempo real o micro-intervalos (segundos/minutos) mediante eventos del kernel (`inotify`) o replicación de logs de transacciones (WAL/binlog). RPO cercano a cero.
* **Deduplicación por Hard Links (`rsync --link-dest`):** Técnica clásica en sistemas de archivos POSIX donde `rsync` compara con el backup previo y crea enlaces duros (inodos compartidos con `nlink > 1`) para los archivos idénticos. Cada día aparenta ser un árbol completo pero solo consume los bytes modificados.
* **Deltas Inversos (`rdiff-backup`):** Paradigma donde el directorio de destino es un espejo exacto del estado más reciente (archivos planos directamente legibles sin descompresión), mientras los deltas matemáticos para retroceder en el tiempo se almacenan hacia atrás en `rdiff-backup-data/`.
* **Zero-Trust Cloud Backup (`duplicity`):** Respaldo incremental basado en `librsync` pero con cifrado asimétrico GnuPG obligatorio antes de abandonar el host local. Protege los datos y nombres de archivos contra operadores de almacenamiento remoto (SFTP, S3).
* **Snapshots Copy-on-Write (LVM CoW):** Congelamiento atómico de metadatos en microsegundos a nivel de bloques. Permite respaldar bases de datos y sistemas de archivos activos en producción de forma 100% consistente sin detener el servicio ni incurrir en escrituras corruptas en caliente.
* 📖 [Ver guía comparativa completa en Lab 3.5.0](backup/backup_arquitecturas_comparativa.md).


---

### Monitoreo, Telemetría y Observabilidad

* **Modelo PULL vs PUSH:** En el modelo **PULL** (Prometheus), el servidor central inicia peticiones periódicas HTTP GET hacia `/metrics` de los nodos, garantizando detección instantánea de caídas y control de tráfico de red. En el modelo **PUSH** (Datadog, Telegraf, StatsD), los clientes transmiten proactivamente sus métricas, ideal para Serverless y redes con NAT cerrado.
* **TSDB (Time Series Database):** Base de datos optimizada exclusivamente para almacenar secuencias de pares `(timestamp, float64)` indexadas por etiquetas multidimensionales clave-valor.
* **PromQL (Prometheus Query Language):** Lenguaje funcional para filtrar, agregar y calcular tasas de cambio instantáneas (`rate()`, `increase()`, `sum()`) sobre series temporales.
* **Textfile Collector:** Módulo de Node Exporter que lee archivos con extensión `.prom` generados atómicamente por scripts locales en `/var/lib/prometheus/node-exporter/` y los expone en `/metrics` junto a la telemetría del kernel.
* **Systemd Timers:** Mecanismo nativo del kernel/userspace (unidades `.timer`) que sustituye al clásico `cron` para la ejecución periódica y supervisada de tareas de telemetría y mantenimiento. Permite sincronización desde el arranque (`OnBootSec`), intervalos relativos al último ciclo (`OnUnitActiveSec`), precisión de milisegundos (`AccuracySec`), y ejecución atómica desacoplada en unidades de servicio `Type=oneshot` con supervisión completa en `journalctl` y `systemctl list-timers`, eliminando bucles bash frágiles (`while sleep`).
* **OpenMetrics:** Estándar neutral de la Cloud Native Computing Foundation (CNCF) que formaliza la sintaxis de texto plano de métricas de Prometheus (`# HELP`, `# TYPE`, etiquetas y marcas de tiempo).
* **Distributed Tracing (Trazas Distribuidas):** Seguimiento del ciclo de vida completo de una petición a través de múltiples microservicios mediante identificadores de traza (*TraceID*) y bloques de tiempo (*Spans*), implementado con OpenTelemetry o Jaeger.
* **Monitoreo Sintético (Sondas / Probes):** Verificación activa de disponibilidad desde el exterior simulando el comportamiento de un usuario final (ej: verificar que una URL devuelva HTTP 200 y que su certificado TLS sea válido con Blackbox Exporter).
* 📖 [Ver taller integrador con telemetría en Lab 3.16](monitoreo/taller_integrador_web_lvm_monitoreo.md).


---

### AI SRE, Agentes Autónomos y Remediación (Self-Healing)

* **AI SRE (Site Reliability Engineering con IA):** Integración de modelos de inteligencia artificial y agentes cognitivos con los sistemas de observabilidad (Prometheus, Grafana, OpenTelemetry) para realizar detección de anomalías, investigación causal de fallas y autorremediación sin intervención humana en incidentes estándar.
* **Patrón ReAct (Reasoning + Acting):** Paradigma cognitivo donde el agente alterna secuencialmente entre formular una hipótesis de razonamiento (*Thought*), invocar una herramienta del sistema operativo (*Action / Tool Call*) e inspeccionar la respuesta obtenida (*Observation*) hasta arribar a un diagnóstico probado.
* **Model Context Protocol (MCP):** Estándar abierto cliente-servidor JSON-RPC 2.0 desarrollado para desacoplar de forma segura a los modelos de lenguaje de las herramientas de infraestructura. Permite que un agente invoque comandos o consulte métricas únicamente a través de un catálogo de herramientas autorizadas expuestas por un servidor MCP.
* **Guardrails de Seguridad (Safety Guardrails):** Mecanismos de contención que restringen las acciones que un agente autónomo puede ejecutar en producción, basados en listas blancas de acciones permitidas (*allowlists*), bloqueo de patrones peligrosos (*denylists*) y contención del radio de explosión (*blast radius*).
* **Human-in-the-Loop (HITL):** Esquema de operación donde el agente autónomo investiga la causa raíz y prepara el plan detallado de remediación con comandos exactos, pero requiere la autorización explícita de un operador humano antes de aplicar cualquier mutación en el sistema.
* **Self-Healing (Autorremediación):** Capacidad de una infraestructura para detectar fallas en tiempo real, aislar componentes degradados y ejecutar acciones correctivas (como el reinicio de servicios caídos o la reparación de arreglos RAID espejados) cerrando automáticamente el ciclo de alerta sin intervención humana.
* 📖 [Ver guía y laboratorio interactivo de AI SRE en Lab 3.6.3](monitoreo/ai_sre_agentes_observabilidad.md) y [Comparativa de Arquitecturas de Monitoreo](monitoreo/monitoreo_arquitecturas_comparativa.md#9-la-nueva-frontera-ai-sre-agentes-autónomos-y-remediación-en-observabilidad).


---

### Monitoreo Clásico, Embebido y Fire-and-Forget (collectd & StatsD)

* **StatsD Protocol:** Formato de telemetría de texto plano ultraligero creado por Etsy transmitido típicamente sobre UDP (puerto 8125). Sigue la sintaxis `<métrica>:<valor>|<tipo>` (donde `c` es contador, `g` es medidor/gauge y `ms` es temporizador/timer).
* **Fire-and-Forget (Dispara y Olvida):** Patrón de diseño donde el cliente envía paquetes de telemetría por UDP sin esperar confirmación (ACK) del servidor de monitoreo. Garantiza que la aplicación nunca se ralentice ni bloquee si el sistema de monitoreo colapsa.
* **collectd:** Demonio de sistema escrito en C diseñado para recolectar estadísticas periódicas de CPU, memoria, discos y red con un consumo mínimo de recursos (< 0.5% CPU y < 10 MB RAM), volcando los datos a archivos CSV o RRD.
* **RRDtool (Round Robin Database):** Motor de base de datos circular de tamaño fijo donde las muestras se consolidan con el tiempo mediante algoritmos de agregación (*downsampling*: average, min, max), garantizando que el archivo nunca crezca en disco pero perdiendo resolución en picos pasados.
* 📖 [Ver laboratorio interactivo de monitoreo clásico en Lab 3.6.4](monitoreo/monitoreo_clasico_collectd_statsd.md).

---

### Criptografía, Llaves, Identidad y Certificados en Linux

* **Criptografía Simétrica:** Modelo donde una única clave secreta compartida se utiliza tanto para cifrar como para descifrar datos (ej: AES-256-GCM, ChaCha20-Poly1305). Es de velocidad extrema (GB/s con aceleración por hardware AES-NI en CPU), pero padece del problema de distribución de claves (*Key Distribution Problem*): no puede enviarse por un medio inseguro sin riesgo de interceptación. Usado en almacenamiento en reposo (LUKS2, gocryptfs) y en el canal de datos de túneles ya establecidos.
* **Criptografía Asimétrica:** Modelo basado en un par matemático de claves complementarias: una **Clave Pública** (distribuible libremente) y una **Clave Privada** (secreta y personal, nunca abandona el equipo). Lo que cifra la pública solo lo descifra la privada; lo que firma la privada solo lo verifica la pública (ej: RSA, Ed25519, Curve25519). Resuelve la distribución de claves y permite autenticación sin contraseñas, pero es computacionalmente entre 1.000 y 10.000 veces más lenta que la simétrica.
* **Criptografía Híbrida:** Paradigma estándar de la industria (HTTPS/TLS, SSH, OpenVPN, WireGuard) que combina lo mejor de ambos mundos: utiliza criptografía asimétrica durante el apretón de manos inicial (*Handshake*) para autenticar a los interlocutores y acordar de forma segura una clave simétrica temporal (*Session Key*), pasando de inmediato a cifrado simétrico masivo a velocidad de línea para transferir la carga útil (*payload*).
* **Challenge-Response (Reto-Respuesta):** Mecanismo de autenticación asimétrica donde el servidor envía un número aleatorio impredecible (*challenge* o *nonce*) al cliente. El cliente lo firma con su clave privada (`id_ed25519` o `.pem`) y devuelve la firma. El servidor verifica la firma contra su `authorized_keys` usando la clave pública. Demuestra matemáticamente que el cliente posee la clave privada **sin que esta viaje jamás por la red**.
* **Mutual TLS (mTLS) y Autoridad Certificadora (PKI):** Arquitectura de seguridad (utilizada en clientes OpenVPN corporativos y mTLS en Kubernetes) donde tanto el servidor como el cliente presentan certificados digitales emitidos y firmados por una Autoridad Certificadora (`ca.crt`) común. Garantiza autenticación bidireccional estricta antes de transferir datos.
* **Perfect Forward Secrecy (PFS):** Propiedad de los protocolos de intercambio de claves (Diffie-Hellman efímero / ECDHE) donde la clave de sesión simétrica se destruye de la memoria RAM al cerrar la conexión. Garantiza que si un atacante graba el tráfico cifrado hoy y compromete la clave privada del servidor años después, **no podrá descifrar las comunicaciones del pasado**.
* **Keyslots (Ranuras de Clave en LUKS2):** Arquitectura de desacoplamiento de claves en sistemas de cifrado de bloques. El disco rígido se cifra con una única *Master Key* binaria aleatoria de 512 bits. Los usuarios no conocen la Master Key; ingresan una contraseña o token TPM que desbloquea uno de los 32 *keyslots* de la cabecera, descifrando la Master Key únicamente en memoria RAM durante el booteo.
* **Host Key vs User Key en OpenSSH (`known_hosts` vs `authorized_keys`):** En el protocolo SSH participan dos pares de llaves asimétricas independientes (más la *Session Key* simétrica efímera `ChaCha20-Poly1305` o `AES-256-GCM` calculada por Diffie-Hellman `curve25519-sha256`). La **Host Key** (`/etc/ssh/ssh_host_ed25519_key`) pertenece al servidor `sshd` y el cliente la registra en `~/.ssh/known_hosts` bajo el modelo **TOFU (*Trust On First Use*)** para detectar ataques *Man-in-the-Middle* (`REMOTE HOST IDENTIFICATION HAS CHANGED!`). La **User Key** (`~/.ssh/id_ed25519`) pertenece al usuario cliente y su parte pública se instala en `~/.ssh/authorized_keys` del servidor para autenticar al usuario sin contraseña.
* **StrictModes en SSH (`chmod 700` / `chmod 600`):** Política de seguridad de OpenSSH por la cual tanto el cliente `ssh` como el servidor `sshd` abortan la autenticación por llave pública si los permisos del directorio `~/.ssh` (debe ser `700`) o de los archivos `id_ed25519` y `authorized_keys` (deben ser `600`) permiten lectura o escritura a otros usuarios del sistema.
* **Crypto-Key Routing (WireGuard):** Mecanismo de enrutamiento criptográfico en el kernel de Linux utilizado por **WireGuard** (`wg0.conf`), donde cada vecino (*Peer*) se identifica por su llave pública `Curve25519` asociada directamente a sus direcciones IP permitidas (`AllowedIPs`), eliminando la necesidad de una Autoridad Certificadora X.509 compleja como en OpenVPN y cifrando los paquetes UDP con `ChaCha20-Poly1305`.
* 📖 [Ver guía pedagógica completa y laboratorio en Lab 3.3a](cifrado/fundamentos_criptografia_llaves_certificados.md), [Script demo_criptografia_llaves.sh](cifrado/demo_criptografia_llaves.sh), [Lab 3.3c: Cifrado en SSH Cliente/Servidor y WireGuard](cifrado/ssh_cifrado_cliente_servidor_wireguard.md) y [Script demo_ssh_cifrado.sh](cifrado/demo_ssh_cifrado.sh).

---

### Automatización, Planificación de Tareas y Sincronización NTP

* **Cron (`crond` / `cronie` / Vixie Cron):** Demonio de planificación periódica residente en memoria que despierta cada minuto para evaluar tablas de configuración globales (`/etc/crontab`, `/etc/cron.d/*`) e individuales por usuario (`/var/spool/cron/crontabs/*` vía `crontab -e`). Opera sobre 5 campos de tiempo (minuto, hora, día del mes, mes, día de la semana), operadores (`*`, `/`, `-`, `,`) y macros (`@reboot`, `@daily`, `@yearly`). Es ideal para servidores encendidos 24/7, pero ejecuta las órdenes en un entorno minimalista (`SHELL`, `PATH`, `MAILTO`) y pierde las tareas si el equipo está apagado a la hora programada.
* **Anacron (`/etc/anacrontab`):** Planificador asíncrono diseñado para sistemas intermitentes (laptops, estaciones de trabajo y VMs no 24/7). No evalúa horas exactas, sino períodos en días (`period`, `delay`, `job-identifier`, `command`) comparando la fecha actual con los sellos de tiempo (`YYYYMMDD`) almacenados en `/var/spool/anacron/`. Si una tarea quedó pendiente mientras el equipo estaba apagado, la lanza automáticamente tras esperar `delay` minutos luego del arranque.
* **Comando `at` (`atd` / `atq` / `atrm` / `batch`):** Subsistema de encolado para tareas efímeras de **ejecución única (*ad-hoc / one-shot*)**. Permite programar órdenes puntuales en el futuro (`echo "reboot" | at 2:00 AM tomorrow`) capturando automáticamente todas las variables de entorno actuales y el directorio de trabajo (`$PWD`) del usuario, eliminándose de la cola al finalizar sin dejar código residual en `crontab`.
* **Systemd Timers (`.timer` + `.service`):** Estándar moderno de automatización en distribuciones Linux contemporáneas que desacopla el *cuándo* (`mi_tarea.timer` con `OnCalendar`, `OnBootSec`, `AccuracySec`) del *qué* (`mi_tarea.service` con `Type=oneshot`). Unifica las capacidades de Cron (calendarios exactos), Anacron (`Persistent=true`) y `at` (`systemd-run --on-active`), sumando registro centralizado en `journalctl`, dependencias condicionales de red/montaje (`After=network-online.target`) y control duro de recursos mediante `cgroups v2` (`CPUQuota`, `MemoryMax`).
* **Chrony (`chronyd` / `chronyc` / NTP):** Demonio y suite cliente/servidor de sincronización de reloj de red (*Network Time Protocol*) que actúa como habilitador base de toda automatización en Linux. Mantiene el reloj del sistema alineado con servidores atómicos de referencia (*Stratum*), corrigiendo la deriva del cristal de cuarzo (*clock drift*) de forma gradual (*slewing*) o inmediata (`makestep`).
* 📖 [Ver Guía Comparativa y Matriz de Decisión en Lab 2.0](automatizacion/automatizacion_arquitecturas_comparativa.md), [Lab 2.4: Cron y Crontab](automatizacion/cron_crontab_planificacion.md), [Lab 2.5: Anacron y at](automatizacion/anacron_at_tareas_asincronas.md) y [Lab 2.6: Systemd Timers vs Cron y Chrony](automatizacion/systemd_timers_vs_cron_chrony.md).

---

### Gestión de Logs, Syslog, Journald y Arquitecturas de Logging

* **Syslog (`RFC 3164` vs `RFC 5424`):** Protocolo y estándar histórico para la recolección y transporte de registros en sistemas tipo Unix. La especificación legacy **RFC 3164** (BSD syslog) utiliza texto plano sin año ni zona horaria; la especificación moderna **RFC 5424** incorpora versión (`1`), marcas de tiempo **ISO-8601 UTC** con milisegundos, campos posicionales estrictos y bloques clave-valor `STRUCTURED-DATA` (`[meta trace="..."]`).
* **Severity, Facility y `<PRI>`:** Ejes de clasificación matemática del protocolo Syslog. La **Severity** (0 a 7) indica la gravedad del evento (`0 emerg`, `1 alert`, `2 crit`, `3 err`, `4 warning`, `5 notice`, `6 info`, `7 debug`). La **Facility** (0 a 23) agrupa el origen (`0 kern`, `2 mail`, `3 daemon`, `4 auth`, `9 cron`, `10 authpriv`, `16-23 local0-local7`). El valor de cabecera en red se calcula como `PRI = (Facility * 8) + Severity`.
* **Kernel Ring Buffer (`dmesg` / `/dev/kmsg`):** Buffer circular de tamaño fijo en memoria RAM donde el kernel Linux escribe mensajes de hardware, controladores, almacenamiento y errores críticos (`OOM Killer`, `I/O error`) desde el primer instante del arranque, antes de que existan sistemas de archivos montados. Se inspecciona con `dmesg -T` o `dmesg --level=err,warn` (sujeto a `kernel.dmesg_restrict`).
* **rsyslog (`RainerScript` y `Disk-Assisted Queues`):** Implementación modular y multihilo de Syslog de alto rendimiento configurada en `/etc/rsyslog.conf` y `/etc/rsyslog.d/*.conf`. Procesa entradas (`imudp`, `imtcp`, `imjournal`, `imfile`), aplica reglas modernas en **RainerScript** (`if/then/stop`), formatea plantillas en texto o JSON y garantiza **0% de pérdida** ante caídas del servidor central mediante colas persistentes en disco (`queue.type="LinkedList"`, `queue.filename="..."`).
* **RELP (*Reliable Event Logging Protocol*):** Protocolo de transporte sobre TCP diseñado por `rsyslog` con confirmaciones a nivel de aplicación mensaje a mensaje, evitando la pérdida de los últimos eventos en tránsito que puede ocurrir en TCP plano ante cortes abruptos de socket.
* **`systemd-journald`, `journalctl` y FSS (*Forward Secure Sealing*):** Servicio moderno de registro binario indexado integrado en `systemd`. Captura automáticamente eventos del kernel, syslog y `stdout/stderr` de unidades anexando metadatos confiables verificados por el kernel (`_PID`, `_SYSTEMD_UNIT`, `_BOOT_ID`, `_MACHINE_ID`). Puede persistir en `/var/log/journal/` o vivir en RAM (`/run/log/journal/`), exportarse con `journalctl -o json` y protegerse contra alteraciones históricas mediante sellado criptográfico **FSS** (`journalctl --setup-keys`).
* **`logrotate` (`create` + `SIGHUP` vs `copytruncate`):** Herramienta estándar de mantenimiento que rota, comprime y purga archivos de `/var/log` para impedir la saturación del disco. La estrategia `create` renombra el archivo y envía `SIGHUP` al demonio para que reabra un inodo nuevo; `copytruncate` copia y trunca en sitio para aplicaciones que no soportan señales, evitando el clásico problema de espacio retenido por archivos `(deleted)` detectables con `lsof +L1`.
* **Structured Logging (`JSON` / `ECS` / `OCSF`):** Práctica de emitir registros en formato clave-valor estructurado bajo esquemas normalizados (*Elastic Common Schema*, *Open Cybersecurity Schema Framework* u *OpenTelemetry*), permitiendo indexación instantánea, correlación por `trace_id` y consulta sin expresiones regulares frágiles.
* **Event Bus / Log Pipelines y *Backpressure* (Kafka, Fluent Bit, Vector, OTel):** Arquitectura empresarial de logging HA donde agentes ligeros en el borde (**Fluent Bit**, **Vector**, **OpenTelemetry Collector**) filtran ruido y envían eventos a una cola distribuida resiliente (**Apache Kafka**, **Redpanda**), absorbiendo picos de tráfico y alimentando en paralelo almacenes como **Grafana Loki**, **OpenSearch/ELK**, **Splunk** o **ClickHouse**.
* **SIEM y Retención WORM:** Sistemas de gestión de eventos e información de seguridad (*Security Information and Event Management*, ej: **Wazuh**, **Splunk**) combinados con almacenamiento inmutable **WORM** (*Write-Once-Read-Many*, ej: S3 Object Lock) para auditoría forense y cumplimiento normativo (ISO 27001, PCI-DSS, SOC 2).
* **Log Clustering (`Drain3`) y *Log Prompt Injection* (AI SRE):** Técnicas clave para conectar logs a agentes de Inteligencia Artificial vía **MCP**. El algoritmo **Drain3** comprime millones de líneas repetitivas en pocas plantillas paramétricas reduciendo >95% el consumo de tokens; la **cuarentena anti-injection** evita que payloads maliciosos grabados en logs (ej. en `User-Agent`) secuestren el razonamiento del agente AI SRE.
* 📖 [Ver Teoría Maestra en Lab 3.18](logs/logs_arquitecturas_teoria.md), [Lab 3.19: Fundamentos](logs/logs_fundamentos_varlog_dmesg.md), [Lab 3.20: Journald Troubleshooting](logs/journald_journalctl_troubleshooting.md), [Lab 3.21: rsyslog TLS & Queues](logs/rsyslog_filtrado_plantillas_tls_colas.md) y [Lab 3.22: Logging Centralizado & AI SRE](logs/logging_centralizado_estructurado_ai_sre.md).

---

### Arquitectura del Kernel Linux, Módulos, SysFS, Inmutabilidad, Seguridad y eBPF

#### POSIX y Familias de Sistemas Operativos (UNIX, AIX, Solaris, BSD, XNU, Windows NT, Linux y Android)
* **POSIX (*Portable Operating System Interface*, IEEE 1003):** Familia de estándares que define la interfaz de programación en C, llamadas al sistema (`open`, `fork`, `pipe`, `pthread`), estructura de señales y comportamiento del shell para que un programa escrito en Unix pueda compilar y correr casi sin cambios entre **GNU/Linux**, **FreeBSD**, **IBM AIX**, **Oracle Solaris** y **macOS**.
* **Linajes de Kernels en la Industria:** Aunque comparten conceptos, provienen de raíces distintas: **UNIX System V** (AIX y Solaris, orientados históricamente a mainframes/RISC y SPARC/POWER), **BSD** (FreeBSD/OpenBSD/NetBSD y la capa UNIX de **Apple XNU** en macOS), **Windows NT** (núcleo híbrido propietario completamente separado del árbol UNIX) y **GNU/Linux** (kernel escrito desde cero bajo **GPLv2** en 1991 siguiendo el estándar POSIX, del que también deriva **Android**).
* *Impacto en Operación:* Un SysAdmin que domina POSIX entiende rápidamente comandos, procesos, permisos y redes tanto en un servidor RHEL/Ubuntu como en un appliance FreeBSD (`pfSense`), un AIX financiero o un clúster Solaris legacy.
* 🔗 **Documentación Oficial:**
  * [IEEE POSIX / Single UNIX Specification](https://pubs.opengroup.org/onlinepubs/9699919799/)
  * [The Linux Kernel Documentation](https://docs.kernel.org/)
  * [FreeBSD Architecture Handbook](https://docs.freebsd.org/en/books/arch-handbook/)

#### Núcleo Monolítico Modular, Ring 0/3, Syscalls y Preemption
* **Núcleo Monolítico Modular:** Arquitectura adoptada por Linux donde todos los subsistemas centrales (planificador, memoria virtual, VFS, red y drivers) comparten un único espacio privilegiado de memoria (**Ring 0**), evitando la sobrecarga de paso de mensajes (IPC) típica de los micronúcleos (como MINIX, QNX o seL4) pero conservando extensibilidad dinámica en caliente mediante módulos cargables (`.ko`).
* **Ring 0 vs. Ring 3 y Syscalls:** Niveles de privilegio aplicados por hardware en la CPU (`Rings 0–3` en x86_64; `EL0–EL1` en ARM64). Las aplicaciones operan aisladas en **Ring 3 (espacio de usuario)** y solo acceden al hardware invocando llamadas al sistema (**syscalls** como `openat`, `read`, `write`, `execve`), auditables en tiempo real con `strace`.
* **Preemption (`PREEMPT_RT`):** Capacidad del núcleo para pausar momentáneamente una rutina en ejecución en Ring 0 y ceder la CPU a una tarea de mayor prioridad (`PREEMPT_NONE`, `VOLUNTARY`, `DYNAMIC`). Desde Linux `6.12` LTS, la rama **`PREEMPT_RT`** forma parte oficial del árbol principal para latencias deterministas en microsegundos (robótica, audio pro, telcos 5G).
* 🔗 **Documentación Oficial:**
  * [Linux syscalls manual (`syscalls(2)`)](https://man7.org/linux/man-pages/man2/syscalls.2.html)
  * [Linux Kernel Real-Time (`PREEMPT_RT`) Wiki](https://wiki.linuxfoundation.org/realtime/start)

#### IRQ (Interrupciones de Hardware), DMA y Top/Bottom Half
* **IRQ (*Interrupt Request*) y DMA (*Direct Memory Access*):** Señales eléctricas o mensajes PCIe (**MSI-X**) mediante los cuales un dispositivo (placa de red, NVMe, teclado) avisa a la CPU de un evento, mientras **DMA** permite al controlador transferir bloques de datos directamente hacia/desde la RAM sin gastar ciclos de CPU copiando byte por byte.
* **Top Half vs. Bottom Half (`softirq` / `kworker`):** El kernel divide la atención de cada interrupción en dos mitades: una rutina mínima e inmediata con interrupciones pausadas (*Top Half*) y un trabajo diferido (*Bottom Half* vía `softirq`, `tasklets` o `workqueues` en hilos `[kworker]`) para mantener la latencia del sistema baja. Desde Linux `7.1`, **Intel FRED** moderniza este salto en hardware x86_64.
* *Impacto en Operación:* Tormentas de interrupciones en discos o NICs se diagnostican inspeccionando `/proc/interrupts` y las columnas `%si`/`%hi` en `top` o `vmstat`.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel IRQ & Softirq Guide](https://docs.kernel.org/core-api/genericirq.html)

#### MMU (Memory Management Unit), Paginación, Page Cache y OOM Killer
* **MMU y Memoria Virtual:** Unidad de hardware dentro de la CPU que traduce direcciones de memoria virtuales de cada proceso a direcciones físicas en RAM usando páginas (típicamente `4 KiB`, o **`HugePages` de `2 MiB`/`1 GiB`** para bases de datos e hipervisores), impidiendo que un proceso lea o corrompa la RAM de otro o del kernel.
* **Page Cache y *OOM Killer*:** Linux usa toda la RAM libre no reclamada por aplicaciones como caché transparente de lectura/escritura de disco (**Page Cache**), liberándola al instante si una app pide memoria (`free -h` columna `buff/cache`). Si se agotan RAM y swap por completo, el **OOM Killer** (*Out-Of-Memory*) selecciona y mata el proceso de mayor puntaje `oom_score` para evitar un cuelgue total del host.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel Memory Management Documentation](https://docs.kernel.org/admin-guide/mm/index.html)

#### VFS (Virtual File System) y FUSE
* **VFS (*Virtual File System*):** Capa de abstracción en el kernel que expone las mismas operaciones POSIX (`open`, `read`, `stat`, `unlink`) sin importar si por debajo hay un sistema de archivos local (`ext4`, `XFS`, `Btrfs`), de red (`NFS`, `SMB`), en memoria (`tmpfs`) o en contenedores (`OverlayFS`).
* **FUSE (*Filesystem in Userspace*):** Módulo estándar del kernel (`/dev/fuse`) que redirige peticiones del VFS hacia un proceso común en **Ring 3**, permitiendo desarrollar e instalar sistemas de archivos complejos (`sshfs`, `gocryptfs`, `borg mount`, `rclone`) con aislamiento ante fallos y sin necesidad de programar ni arriesgar el kernel.
* 🔗 **Documentación Oficial:**
  * [Overview of the Linux Virtual File System (VFS)](https://docs.kernel.org/filesystems/vfs.html)
  * [Linux FUSE Kernel Documentation](https://docs.kernel.org/filesystems/fuse.html)

#### LKM (Loadable Kernel Modules), modprobe y Blacklists
* **LKM (`*.ko`):** Fragmentos compilados de código del kernel que pueden insertarse o descargarse en caliente en Ring 0 (`insmod`, `rmmod`, `modprobe`, `depmod`) sin reiniciar ni recompilar `vmlinuz`. Al compartir espacio de memoria privilegiado con el núcleo, un error grave en un LKM puede desencadenar un *Kernel Panic*.
* **Blacklists en `/etc/modprobe.d/`:** Reglas en `/etc/modprobe.d/*.conf` y `/usr/lib/modprobe.d/*.conf` para impedir la carga de controladores problemáticos o vectores físicos de riesgo (ej. `usb-storage`, `uas`, `nouveau`, `cramfs`). La directiva `blacklist <mod>` bloquea únicamente alias automáticos de `udev`, por lo que en endurecimiento estricto debe combinarse con **`install <mod> /bin/false`** y regenerar `initramfs`.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel Module Programming Guide & Kbuild](https://docs.kernel.org/kbuild/modules.html)
  * [Manual `modprobe.d(5)` y `modprobe(8)`](https://man7.org/linux/man-pages/man5/modprobe.d.5.html)

#### sysfs (/sys), procfs (/proc) y udev
* **`sysfs` (`/sys`):** Pseudo-sistema de archivos en RAM introducido en Linux `2.6` que expone la jerarquía de objetos del kernel (`kobjects`): topología física (`/sys/devices`), buses y drivers (`/sys/bus`), dispositivos por función (`/sys/class`), discos y planificadores I/O (`/sys/block`), parámetros de módulos (`/sys/module`) y estado global (`/sys/kernel`).
* **`procfs` (`/proc`) y `udev`:** `/proc` refleja procesos activos (`/proc/<PID>`), `/proc/cmdline`, `/proc/kallsyms` y estadísticas vivas; **`systemd-udevd`** escucha eventos del kernel sobre `/sys` (*uevents*) para cargar drivers automáticamente y crear nombres persistentes en `/dev/`.
* 🔗 **Documentación Oficial:**
  * [The `sysfs` Filesystem Documentation](https://docs.kernel.org/filesystems/sysfs.html)
  * [Manual `proc(5)`](https://man7.org/linux/man-pages/man5/proc.5.html) y [`udev(7)`](https://man7.org/linux/man-pages/man7/udev.7.html)

#### sysctl (/proc/sys)
* **`sysctl`:** Interfaz que permite consultar y ajustar en caliente parámetros del kernel expuestos bajo **`/proc/sys/`** (`vm.swappiness`, `net.ipv4.ip_forward`, `net.ipv4.tcp_congestion_control=bbr`, `kernel.kptr_restrict`, `fs.inotify.max_user_watches`). La persistencia entre reinicios se define por orden de prioridad en `/etc/sysctl.d/99-*.conf` y se recarga con `sysctl --system`.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel `/proc/sys/` Tuning (`sysctl`)](https://docs.kernel.org/admin-guide/sysctl/index.html)
  * [Manual `sysctl(8)` y `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html)

#### initramfs (cpio) y switch_root
* **`initramfs`:** Archivo `cpio` comprimido (`.img` / `.cpio.gz`) cargado en memoria RAM por el bootloader junto a `vmlinuz`. Resuelve la paradoja de arranque cuando el driver del disco o filesystem (`virtio_blk`, `nvme`, `xfs`, `LUKS2`, `LVM`, `RAID`) está compilado como módulo (`=m`) y no *built-in* (`=y`): su script `/init` carga los `.ko`, desbloquea discos, monta la raíz `/` real y cede el PID 1 mediante **`exec switch_root`**.
* 🔗 **Documentación Oficial:**
  * [`ramfs`, `rootfs` and `initramfs` in the Linux Kernel](https://docs.kernel.org/filesystems/ramfs-rootfs-initramfs.html)
  * [Dracut Initramfs Framework](https://github.com/dracutdevs/dracut/blob/master/README.md)

#### BLS (Boot Loader Specification) y UKI
* **BLS (*Boot Loader Specification*):** Estándar moderno donde cada versión de kernel crea un archivo declarativo independiente en `/boot/loader/entries/*.conf` (usado en Fedora, RHEL 9/10 y sistemas OSTree), simplificando actualizaciones y rollbacks sin regenerar un `grub.cfg` monolítico.
* **UKI (*Unified Kernel Image*):** Imagen EFI única ejecutable que empaqueta en un solo binario el *UEFI boot stub*, el kernel `vmlinuz`, el `initramfs`, microcódigo CPU y `/proc/cmdline`, permitiendo firmarlos como unidad criptográfica atómica bajo **UEFI Secure Boot** y medirlos con TPM 2.0.
* 🔗 **Documentación Oficial:**
  * [UAPI Group: Boot Loader Specification (BLS)](https://uapi-group.org/specifications/specs/boot_loader_specification/)
  * [UAPI Group: Unified Kernel Image (UKI)](https://uapi-group.org/specifications/specs/unified_kernel_image/)

#### Distros Inmutables (OSTree, rpm-ostree y bootc)
* **Distros Inmutables / *Image-Based Linux*:** Distribuciones como **Fedora Atomic** (Silverblue, Kinoite, Sway Atomic), **RHEL Image Mode**, **openSUSE MicroOS**, **Talos Linux** y **AWS Bottlerocket** donde `/usr` y `/lib/modules` se montan en **solo lectura (`ro`)**, `/etc` aplica fusión a tres vías (*3-way merge*) y cada actualización despliega un sistema completo versionado A/B antes de reiniciar.
* **OSTree, `rpm-ostree`, `bootc`, `fs-verity` y `dm-verity`:** **`OSTree`** actúa como "Git para árboles de sistema operativo"; **`bootc`** entrega la imagen y el kernel como un contenedor OCI estándar; **`fs-verity` / `dm-verity`** validan criptográficamente en el kernel que ningún archivo o bloque haya sido alterado. En lugar de `DKMS`, usan **`akmods`** precompilados, capas OCI o extensiones **`systemd-sysext`**.
* 🔗 **Documentación Oficial:**
  * [OSTree Architecture Documentation](https://ostreedev.github.io/ostree/)
  * [`bootc` (Bootable Containers) Docs](https://containers.github.io/bootc/)
  * [Linux Kernel `dm-verity`](https://docs.kernel.org/admin-guide/device-mapper/verity.html) y [`fs-verity`](https://docs.kernel.org/filesystems/fsverity.html)

#### DKMS y kABI
* **DKMS (*Dynamic Kernel Module Support*):** Framework que recompila automáticamente controladores externos (*out-of-tree*: NVIDIA, OpenZFS, VirtualBox) contra `linux-headers` / `kernel-devel` cada vez que se instala una nueva versión del kernel en distros mutables.
* **kABI (*Kernel Application Binary Interface*):** Garantía de estabilidad binaria (característica de RHEL / Rocky / AlmaLinux) que preserva los símbolos internos exportados del kernel durante toda una rama mayor (~10 años) para que drivers empresariales certificados no se rompan en cada parche menor.
* 🔗 **Documentación Oficial:**
  * [Dell / Community DKMS Project](https://github.com/dell/dkms)
  * [Linux Kernel Stable ABI Policy (`Documentation/ABI`)](https://docs.kernel.org/admin-guide/abi.html)

#### Livepatching (kpatch / Canonical Livepatch) y kexec
* **Livepatching (`/sys/kernel/livepatch`):** Mecanismo del kernel que redirige funciones vulnerables en memoria RAM usando **`ftrace`** hacia funciones corregidas sin descargar el módulo ni reiniciar el sistema (**0 segundos de caída**), operado con **`kpatch`** (RHEL/Fedora), **Canonical Livepatch** (Ubuntu) o **kGraft/SUSE**.
* **`kexec`:** Mecanismo que permite a un kernel en ejecución cargar directamente en memoria RAM una imagen de kernel nueva y saltar a ella **omitiendo el reinicio completo de firmware BIOS/UEFI y POST**, reduciendo ventanas de mantenimiento en servidores físicos grandes de varios minutos a pocos segundos.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel Livepatching Documentation](https://docs.kernel.org/livepatch/livepatch.html)
  * [Linux Kernel `kexec` Documentation](https://docs.kernel.org/admin-guide/kdump/kdump.html)

#### Kernel Taint, KASLR, kptr_restrict y Kernel Lockdown
* **Kernel Taint (`/proc/sys/kernel/tainted`):** Máscara de bits diagnóstica que indica si el kernel ha salido de su estado puro GPL/upstream (ej. módulo propietario bit `0 = 1`, out-of-tree bit `12 = 4096`, sin firma bit `13 = 8192`).
* **KASLR, `kptr_restrict`, `dmesg_restrict`, TOCTOU y Lockdown:** **KASLR** aleatoriza dónde carga el kernel en RAM en cada arranque; **`kernel.kptr_restrict=2`** y **`dmesg_restrict=1`** bloquean fugas de esas direcciones vía `/proc/kallsyms` o `dmesg`; **`fs.protected_symlinks=1`** impide ataques de condición de carrera **TOCTOU** (*Time-of-Check to Time-of-Use*) con enlaces en `/tmp`; y **Kernel Lockdown** (`/sys/kernel/security/lockdown`) bloquea módulos sin firma y escritura directa en RAM cuando UEFI Secure Boot está activo.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel Tainted Kernels Documentation](https://docs.kernel.org/admin-guide/tainted-kernels.html)
  * [Kernel Security Lockdown & Sysctl Hardening](https://docs.kernel.org/security/index.html)

#### eBPF, BPF Verifier, JIT y CO-RE (BTF)
* **eBPF (*Extended Berkeley Packet Filter*):** Máquina virtual segura en Ring 0 que permite ejecutar programas event-driven en *tracepoints*, *kprobes* o sockets para observabilidad (`bpftrace`), filtrado ultra-rápido en tarjeta (**XDP**, Cilium) y seguridad runtime (Falco, Tetragon) sin modificar código fuente del kernel ni cargar LKM en C.
* **BPF Verifier, JIT y CO-RE (BTF):** El **Verifier** inspecciona estáticamente todo el bytecode antes de cargarlo (prohibiendo bucles sin cota, punteros nulos o lecturas fuera de rango); el compilador **JIT** lo traduce a instrucciones nativas; y **CO-RE** (*Compile Once – Run Everywhere*) usa **`/sys/kernel/btf/vmlinux`** para portabilidad binaria entre versiones de kernel.
* 🔗 **Documentación Oficial:**
  * [eBPF Official Documentation & Architecture (ebpf.io)](https://ebpf.io/what-is-ebpf/)
  * [Linux Kernel BPF Documentation](https://docs.kernel.org/bpf/index.html)

#### io_uring, EEVDF y sched_ext
* **`io_uring`:** Subsistema de I/O asíncrono introducido en Linux `5.1` que usa dos anillos circulares compartidos en RAM entre espacio de usuario y kernel (*Submission Queue* y *Completion Queue*), reduciendo drásticamente el número de `syscalls` en servidores web y bases de datos modernas.
* **`EEVDF`, `sched_ext`, `PSI`, `TCP BBR`, `Intel FRED` y `CAS`:** **`EEVDF`** (*Earliest Eligible Virtual Deadline First*) sustituyó a CFS en Linux `6.6`; **`sched_ext`** (`6.12`) permite cargar planificadores de CPU escritos en eBPF en caliente; **`PSI`** (*Pressure Stall Information*) mide contención real de CPU/RAM/I/O en `/proc/pressure/`; **`TCP BBR`** optimiza el control de congestión de red sin esperar pérdida de paquetes; **`Intel FRED`** (`7.1`) agiliza transiciones Ring 3 ↔ Ring 0; y **`CAS`** (*Cache-Aware Scheduling*, `7.2`) agrupa hilos según caché L3 compartida.
* 🔗 **Documentación Oficial:**
  * [Efficient IO with `io_uring`](https://kernel.dk/io_uring.pdf)
  * [Linux Kernel Scheduler Documentation (`EEVDF` & `sched_ext`)](https://docs.kernel.org/scheduler/index.html)

#### Confidential Computing (AMD SEV-SNP e Intel TDX)
* **Confidential Computing en el Kernel:** Extensiones criptográficas por hardware (**AMD SEV-SNP** e **Intel TDX**) soportadas nativamente en kernels Linux modernos (`6.x`–`7.x`) que cifran por completo los registros de CPU y páginas de RAM de cada máquina virtual con llaves exclusivas dentro del procesador.
* *Impacto en Operación:* Garantiza en la nube pública que **ni siquiera el administrador del host físico, el hipervisor ni el proveedor cloud puedan leer la memoria RAM de tu kernel o VM invitada** (*tenant*).
* 🔗 **Documentación Oficial:**
  * [Linux Kernel AMD SEV Documentation](https://docs.kernel.org/virt/coco/sev-guest.html)
  * [Linux Kernel Intel TDX Guest Support](https://docs.kernel.org/virt/coco/tdx-guest.html)

#### Device Tree (.dtb), MMU, uClinux y Zephyr RTOS
* **Device Tree (`.dtb` / `.dts`):** Estructura jerárquica de hardware compilada desde archivos `.dts` (texto) hacia `.dtb` (binario) entregada por bootloaders embebidos (**U-Boot**) al kernel Linux en placas ARM/RISC-V (Raspberry Pi, NVIDIA Jetson, Edge) para describir dispositivos que no tienen autodescubrimiento BIOS/ACPI (pines GPIO, buses I2C/SPI, UART).
* **`tinyconfig`, `uClinux`, `Yocto`/`Buildroot`/`OpenWrt` y Zephyr RTOS:** Constructores como **Yocto Project**, **Buildroot** y **OpenWrt** compilan kernels minimalistas (`make tinyconfig`) + **BusyBox** para sistemas embebidos de pocos MB; **`uClinux`** (`CONFIG_MMU=n`) adapta Linux a SoCs sin MMU; mientras que en **microcontroladores (MCU)** de 64–512 KB RAM (ESP32, STM32, Cortex-M), donde Linux no cabe, el estándar moderno hermano respaldado por la Linux Foundation es **Zephyr RTOS** (junto a FreeRTOS y Apache NuttX).
* 🔗 **Documentación Oficial:**
  * [Linux and the Devicetree](https://docs.kernel.org/devicetree/usage-model.html)
  * [Zephyr RTOS Official Documentation](https://docs.zephyrproject.org/)
  * [The Yocto Project Documentation](https://docs.yoctoproject.org/)

#### Android GKI y Binder IPC
* **Android GKI (*Generic Kernel Image*) y Binder:** Todo teléfono **Android** ejecuta internamente un **Kernel Linux LTS real** mantenido junto a `kernel.org`. Mediante **GKI**, Google unifica el núcleo base separado de los módulos propietarios de cada fabricante SoC (`Qualcomm`, `MediaTek`), mientras **`Binder`** actúa como el mecanismo IPC rápido del sistema operativo móvil (reescrito progresivamente en **Rust** desde Linux `6.18` LTS).
* 🔗 **Documentación Oficial:**
  * [Android Generic Kernel Image (GKI) Overview](https://source.android.com/docs/core/architecture/kernel/generic-kernel-image)

---

### Virtualización, Contenedores, Cloud (OpenStack / Kubernetes) y HPC (Slurm)

#### Hipervisor Tipo 1 (Bare-Metal) vs Tipo 2 (Hosted)
* **Hipervisor (*Virtual Machine Monitor - VMM*):** Capa de software y firmware que particiona los recursos de un servidor físico para ejecutar múltiples sistemas operativos invitados (*Guests*) aislados simultáneamente, cada uno con su propio kernel independiente.
* **Tipo 1 (*Bare-Metal / Nativo*) vs. Tipo 2 (*Hosted / Hospedado*):** El **Tipo 1** corre directamente sobre el hardware sin un sistema operativo general debajo (o integrando el propio kernel como hipervisor: **KVM**, **VMware ESXi**, **Xen**, **Microsoft Hyper-V**, **Proxmox VE**, **FreeBSD `bhyve`**), entregando rendimiento casi nativo en servidores. El **Tipo 2** se instala como aplicación normal dentro de un SO anfitrión (**VirtualBox**, **VMware Workstation/Fusion**, **UTM**), ideal para laboratorio personal en laptops.
* 🔗 **Documentación Oficial:**
  * [Red Hat / Linux KVM Architecture Overview](https://www.linux-kvm.org/page/Main_Page)

#### Virtualización Asistida por Hardware (Intel VT-x, AMD-V, SLAT/EPT e IOMMU)
* **Intel `VT-x` y AMD `AMD-V`:** Extensiones del procesador (`vmx` / `svm` en `/proc/cpuinfo`) creadas en 2005–2006 que añaden un modo de privilegio por debajo de Ring 0 (*VMX Root Mode* / "Ring -1" para el hipervisor) y un *VMX Non-Root Mode* donde el kernel invitado cree correr en Ring 0 real sin tener que traducir instrucciones binarias en software.
* **SLAT (`EPT` / `RVI`) e IOMMU (`VT-d` / `AMD-Vi`):** **SLAT** (*Second Level Address Translation*) acelera en silicio la doble traducción de páginas RAM invitado→físico; **IOMMU** remapea accesos DMA de dispositivos PCIe físicos directamente hacia una VM aislada (habilitando `VFIO` y `SR-IOV` seguros).
* 🔗 **Documentación Oficial:**
  * [Intel Virtualization Technology Reference](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
  * [Linux IOMMU & DMA Remapping Docs](https://docs.kernel.org/driver-api/iommu.html)

#### Virtualización Completa, Paravirtualización (VirtIO) y Emulación
* **Emulación vs. Virtualización Completa vs. Paravirtualización (`VirtIO`):** La **emulación** interpreta por software instrucciones de otra arquitectura (ej. correr ARM64 en un portátil x86_64 con `qemu-system-aarch64`, más lenta pero universal). La **virtualización completa** ejecuta código en la misma CPU nativa simulando hardware estándar (`e1000`, IDE/AHCI). La **paravirtualización** utiliza controladores conscientes de estar virtualizados —en Linux/QEMU el estándar **`VirtIO`** (`virtio_blk`, `virtio_net`, `virtio_scsi`)— que intercambian colas de memoria directa (*virtqueues*) evitando emular registros lentos y alcanzando velocidad cercana al bare-metal.
* 🔗 **Documentación Oficial:**
  * [OASIS Virtual I/O Device (VIRTIO) Specification](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html)
  * [QEMU System Emulation Documentation](https://www.qemu.org/docs/master/)

#### KVM, QEMU, libvirt y Proxmox VE
* **KVM + QEMU + `libvirt`:** **`KVM`** (*Kernel-based Virtual Machine*, integrado en Linux desde `2.6.20`) convierte al kernel Linux en un hipervisor Tipo 1 exponiendo `/dev/kvm`. **`QEMU`** actúa como proceso VMM en espacio de usuario que emula periféricos y arranca las VMs aceleradas por KVM. **`libvirt`** (`libvirtd` / `virsh`) provee una API unificada y abstracción XML para administrar redes, snapshots y ciclos de vida sobre múltiples motores.
* **Proxmox VE (PVE):** Plataforma open-source empresarial basada en Debian que unifica **KVM/QEMU** (VMs completas), **LXC** (contenedores de sistema), almacenamiento **ZFS/Ceph** y alta disponibilidad en clúster con interfaz web.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel KVM Documentation](https://docs.kernel.org/virt/kvm/index.html)
  * [libvirt Virtualization API](https://libvirt.org/docs.html)
  * [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/)

#### Xen, VMware ESXi, Microsoft Hyper-V y WSL2
* **Xen Project y VMware ESXi:** **Xen** es un hipervisor Tipo 1 pionero con arquitectura micronúcleo donde un dominio privilegiado (**`Dom0`**) gestiona drivers para invitados (**`DomU`**), clave en los inicios de AWS EC2, Citrix Hypervisor y Qubes OS. **VMware ESXi** usa un kernel propietario minimalista (**`VMkernel`**) bare-metal ampliamente desplegado en datacenters corporativos con **vCenter**.
* **Microsoft Hyper-V y WSL2:** Aunque se instala desde Windows, **Hyper-V es un hipervisor Tipo 1**: al habilitarlo se inserta por debajo de Windows, degradando al propio Windows anfitrión a una *"parent partition"* virtualizada especial. **WSL2** (*Windows Subsystem for Linux 2*) aprovecha esa arquitectura ultraligera para correr un **Kernel Linux real** (drivers `hv_vmbus`, soporte GPU/red) en milisegundos dentro de Windows.
* 🔗 **Documentación Oficial:**
  * [Microsoft Hyper-V Architecture](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/reference/hyper-v-architecture)
  * [Microsoft WSL2 & Official WSL2 Linux Kernel](https://github.com/microsoft/WSL2-Linux-Kernel)
  * [Xen Project Architecture Overview](https://wiki.xenproject.org/wiki/Xen_Project_Software_Overview)

#### SR-IOV y VFIO (PCIe Passthrough)
* **SR-IOV (*Single Root I/O Virtualization*) y VFIO:** **`SR-IOV`** permite que una única tarjeta física (ej. NIC de 25/100 Gbps) se divida por hardware en una *Physical Function (PF)* y decenas de *Virtual Functions (VF)* independientes entregadas directo a cada VM. **`VFIO`** (*Virtual Function I/O*) es el framework seguro del kernel Linux para asignar tarjetas PCIe completas (como GPUs NVIDIA en servidores de IA o placas NVMe) en exclusiva a una VM sin pasar por la emulación del hipervisor.
* 🔗 **Documentación Oficial:**
  * [Linux Kernel VFIO — "Virtual Function I/O"](https://docs.kernel.org/driver-api/vfio.html)

#### AIX LPAR y WPAR (IBM PowerVM)
* **AIX LPAR / DLPAR y WPAR:** En servidores empresariales **IBM Power (POWER8/9/10/11)**, **`LPAR`** (*Logical Partition*, gobernado por el hipervisor firmware **PowerVM**) divide CPU, RAM y adaptadores I/O en máquinas virtuales aisladas capaces incluso de redimensionarse dinámicamente sin reiniciar (**DLPAR**). **`WPAR`** (*Workload Partition*, AIX 6.1+) añadió sobre AIX lo equivalente a contenedores de sistema operativo compartiendo el mismo kernel AIX.
* 🔗 **Documentación Oficial:**
  * [IBM PowerVM & LPAR Documentation](https://www.ibm.com/docs/en/powervm)
  * [IBM AIX Workload Partitions (WPAR)](https://www.ibm.com/docs/en/aix/7.3?topic=concepts-workload-partitions)

#### Solaris Zones (Containers) y LDOMs
* **Solaris Zones / Containers (`illumos`) y LDOMs:** Introducidas en **Solaris 10 (2005)**, las **Zones** crearon un sistema de aislamiento empresarial maduro mucho antes que Docker: una **`Global Zone`** administra el hardware y aloja múltiples **`Non-Global Zones`** independientes integradas de fábrica con **ZFS**, controles de recursos y **DTrace**; mientras **LDOMs** (*Oracle VM Server for SPARC*) aportaba virtualización tipo hipervisor sobre hardware SPARC.
* 🔗 **Documentación Oficial:**
  * [Oracle Solaris Zones Administration Guide](https://docs.oracle.com/cd/E37838_01/html/E61040/index.html)

#### FreeBSD Jails y bhyve
* **FreeBSD Jails y `bhyve`:** Nacidas en **FreeBSD 4.0 (2000)** como evolución directa de `chroot`, las **Jails** confinaron por primera vez procesos, root local, árbol de archivos y pila de red (`VNET`) en un servidor Unix completo sin sobrecarga de virtualización. Posteriormente, FreeBSD incorporó **`bhyve`** (*BSD Hypervisor*, Tipo 1 liviano en el propio sistema base con soporte `VirtIO` y passthrough).
* 🔗 **Documentación Oficial:**
  * [FreeBSD Handbook: Jails](https://docs.freebsd.org/en/books/handbook/jails/)
  * [FreeBSD Handbook: Virtualization with bhyve](https://docs.freebsd.org/en/books/handbook/virtualization/#virtualization-host-bhyve)

#### Contenedores Linux: chroot, Namespaces, Cgroups v2, OCI, Docker y Podman
* **Anatomía Real de un Contenedor Linux:** Un contenedor **no tiene un kernel propio ni es una VM pequeña**: es simplemente uno o más procesos Linux estándar corriendo en el **mismo kernel del anfitrión** aislados mediante tres pilares nativos del kernel: **Namespaces** (qué puede ver: `pid`, `net`, `mnt`, `uts`, `ipc`, `user`, `cgroup`, `time`), **Cgroups v2** (cuánto puede consumir: CPU, RAM, PIDs, I/O) y sistemas de archivos en capas **OverlayFS** + filtros **`seccomp-bpf`** y **Linux Capabilities**.
* **OCI, Docker y Podman:** La **Open Container Initiative (OCI)** estandariza los formatos de imagen y runtimes (`runc`, `crun`). **Docker** popularizó el flujo con demonio `dockerd` + `containerd`; **Podman** ofrece compatibilidad OCI CLI **sin demonio central (*daemonless*)** y con ejecución segura sin privilegios (**rootless** usando *user namespaces*).
* 🔗 **Documentación Oficial:**
  * [Linux Namespaces (`namespaces(7)`)](https://man7.org/linux/man-pages/man7/namespaces.7.html) y [Cgroups v2](https://docs.kernel.org/admin-guide/cgroup-v2.html)
  * [Open Container Initiative (OCI) Specifications](https://opencontainers.org/)
  * [Podman Official Documentation](https://docs.podman.io/)

#### MicroVMs y Sandboxes: Firecracker, Kata Containers y gVisor
* **MicroVMs y Sandboxes Fuerte:** Cuando ejecutar código de terceros no confiables (*multi-tenant serverless*, CI/CD, agentes IA) sobre un kernel Linux compartido resulta demasiado riesgoso, se combinan velocidad de contenedor y frontera de VM/sandbox: **AWS Firecracker** lanza microVMs sobre `/dev/kvm` eliminando emulación BIOS/PCI legacy en `<125 ms`; **Kata Containers** corre cada Pod Kubernetes dentro de una microVM KVM/QEMU dedicada; y **gVisor** (Google) intercepta las `syscalls` del contenedor en espacio de usuario escrito en Go antes de llegar al kernel del host.
* 🔗 **Documentación Oficial:**
  * [Firecracker MicroVM Documentation](https://firecracker-microvm.github.io/)
  * [Kata Containers Architecture](https://katacontainers.io/learn/)
  * [gVisor Security Architecture Guide](https://gvisor.dev/docs/architecture_guide/intro/)

#### Cloud IaaS y OpenStack (Nova, Neutron, Cinder, Glance, Keystone)
* **Cloud IaaS y OpenStack:** Las nubes públicas (**AWS**, **Azure**, **GCP**) orquestan cientos de miles de servidores físicos mediante hipervisores dedicados (como **AWS Nitro System** con KVM y tarjetas hardware dedicadas que descargan red/EBS fuera de la CPU del cliente) y redes definidas por software (**SDN**). En infraestructura privada o telecomunicaciones 5G, **OpenStack** es la plataforma IaaS open-source estándar compuesta por microservicios modulares: **`Keystone`** (identidad IAM), **`Nova`** (cómputo sobre KVM o bare-metal **`Ironic`**), **`Neutron`** (redes SDN/VPC), **`Cinder`** (volúmenes de bloque, usualmente sobre **Ceph**), **`Glance`** (imágenes), **`Swift`** (objetos) y **`Horizon`** (panel web).
* 🔗 **Documentación Oficial:**
  * [OpenStack Official Documentation](https://docs.openstack.org/)
  * [AWS Nitro System Architecture](https://aws.amazon.com/ec2/nitro/)

#### Orquestación: Kubernetes (K8s), K9s y KubeVirt
* **Kubernetes (`K8s`) y `K9s`:** Orquestador declarativo estándar de la industria para flotas de contenedores: su **Control Plane** (`kube-apiserver`, `etcd`, `kube-scheduler`, `controller-manager`) mantiene el estado deseado mientras cada **Worker Node** (`kubelet` + `containerd`/CRI-O + CNI) ejecuta los **Pods**. **`K9s`** es la consola TUI (*Terminal UI*) interactiva en tiempo real preferida por ingenieros SRE y DevOps para inspeccionar clústeres Kubernetes, cambiar contextos/namespaces, abrir logs (`l`), entrar a shells (`s`) o depurar eventos sin memorizar decenas de comandos largos `kubectl`.
* **`KubeVirt`:** Extensión declarativa de Kubernetes que permite levantar y migrar en vivo **máquinas virtuales KVM tradicionales dentro de Pods** bajo los mismos manifiestos YAML, redes CNI y almacenamiento CSI que los contenedores.
* 🔗 **Documentación Oficial:**
  * [Kubernetes Official Documentation](https://kubernetes.io/docs/home/)
  * [K9s — Kubernetes CLI To Manage Your Clusters In Style](https://k9scli.io/)
  * [KubeVirt User Guide](https://kubevirt.io/user-guide/)

#### HPC (High-Performance Computing) y Slurm
* **HPC (*High-Performance Computing*) y `Slurm`:** En supercomputadoras científicas (lista TOP500) y clústeres de entrenamiento masivo de Inteligencia Artificial (**LLMs**), cada microsegundo de latencia de red o hipervisor cuenta; por eso suelen ejecutarse **directamente sobre Linux Bare-Metal**, con enlaces **InfiniBand / RoCE RDMA**, GPUs conectadas por NVLink y sistemas de archivos paralelos (**Lustre**, **GPFS**). **`Slurm`** (*Simple Linux Utility for Resource Management*) es el gestor de colas y planificador distribuido líder (`slurmctld` controlador central, `slurmd` en nodos de cómputo usando `cgroups` y afinidad **NUMA**, y `slurmdbd` para contabilidad *fairshare*), operado mediante **`sinfo`**, **`squeue`**, **`sbatch`** y **`srun`**.
* 🔗 **Documentación Oficial:**
  * [Slurm Workload Manager Documentation](https://slurm.schedmd.com/documentation.html)

* 📖 [Ver Guía Maestra del Kernel en Lab 1.6](kernel/kernel_arquitectura_historia_guia_maestra.md), [Teoría Maestra de Virtualización, Cloud y HPC en Lab 3.29](virtualizacion/virtualizacion_contenedores_cloud_hpc_teoria.md), [Lab 1.7: Módulos y Blacklists](kernel/modulos_lkm_blacklists_boot.md), [Lab 1.8: SysFS y Sysctl](kernel/sysfs_proc_sysctl_tuning.md), [Lab 2.7: Updates y Livepatch](kernel/actualizacion_kernel_rollback_livepatch.md), [Lab 3.23: LKM en C](kernel/modulo_lkm_firmware_sim.md), [Lab 3.24: Compilación & initramfs QEMU](kernel/compilacion_kernel_initramfs.md) y [Lab 3.25: Seguridad & eBPF](kernel/seguridad_ataques_kernel_ebpf.md).

---

### Sistemas Gráficos en Linux: X11/Xorg, Wayland, Gestores y Acceso Remoto

#### X11 / X.Org, Modelo Invertido y `$DISPLAY`
* **X Window System (X11 / X.Org):** Protocolo y servidor gráfico nacido en el MIT (1984–1987, Project Athena) y bifurcado en 2004 hacia **X.Org Foundation**. Su arquitectura cliente-servidor está **invertida** respecto a la web: el **X Server** corre frente al usuario controlando monitor, GPU, teclado y ratón, mientras las aplicaciones gráficas (`Firefox`, `xclock`, `Wireshark`) son **X Clients** que solicitan dibujar ventanas.
* **`$DISPLAY`:** Variable de entorno con sintaxis `hostname:display_number.screen_number` (ambos indexados desde `0`, p. ej. `:0` para socket Unix local o `localhost:10.0` para túneles SSH) que indica a cada X Client a qué servidor X conectarse.

#### Display Server, Compositor, WM, DE y Display Manager
* **Display Server:** Componente que intermedia entre el hardware gráfico del kernel (`DRM/KMS/evdev`) y las aplicaciones (`Xorg`, `Xvfb`, o un compositor Wayland).
* **Window Manager (WM) vs. Compositor:** El **WM** administra ubicación, tamaño, bordes, foco y escritorios virtuales según su paradigma (**Stacking/Flotante** como `Openbox`/`xfwm4`/`KWin`/`Mutter`, **Tiling/Mosaico** como `i3`/`Sway`/`Hyprland`, o **Dynamic** como `dwm`/`AwesomeWM`). El **Compositor** combina texturas fuera de pantalla para aplicar transparencias, sombras y evitar *tearing* (`Picom` en X11 separado, o integrado en Wayland).
* **Desktop Environment (DE):** Suite gráfica completa con aplicaciones, ajustes y panel de sistema (**KDE Plasma** en Qt, **GNOME** en GTK, **XFCE** ligero en GTK, **COSMIC** en Rust).
* **Display Manager (DM):** Pantalla gráfica de inicio de sesión (*greeter* + PAM) al arrancar `graphical.target` (**XDM**, **KDM** reemplazado por **SDDM**, **GDM3**, **LightDM** compatible con múltiples DEs, XDMCP y VNC).

#### Wayland, DMA-BUF, XWayland y PipeWire
* **Wayland (`$WAYLAND_DISPLAY`):** Protocolo moderno (iniciado por Kristian Høgsberg en 2008) que fusiona Display Server, Compositor y Window Manager, intercambiando buffers GPU mediante **`DMA-BUF`** sin paso doble ni *tearing*, y garantizando **aislamiento estricto entre clientes** (bloqueando el *keylogging* pasivo propio de X11).
* **`XWayland` y `PipeWire`/`xdg-desktop-portal`:** **`XWayland`** ejecuta un servidor X *rootless* bajo Wayland para aplicaciones heredadas X11; **`PipeWire` + `xdg-desktop-portal`** habilitan capturas y compartición de pantalla con permiso explícito del usuario.

#### DRM / KMS, `modesetting`, `xhost`, `xauth` y `Xvfb`
* **DRM / KMS (*Kernel Mode Setting*):** Subsistema del kernel que administra modos de resolución y memoria GPU desde Ring 0, permitiendo que Xorg moderno funcione con el driver genérico **`modesetting`** y minimizando la necesidad de `/etc/X11/xorg.conf` frente a fragmentos modulares en `/etc/X11/xorg.conf.d/` (`cvt` + `00-keyboard.conf`).
* **`xhost` vs. `xauth` (`MIT-MAGIC-COOKIE-1`):** `xhost` aplica listas de acceso por host/usuario (`xhost +` **deshabilita la seguridad** y es una brecha crítica; siempre restaurar con `xhost -` o acotar con `+si:localuser:`). **`xauth`** gestiona cookies criptográficas en `~/.Xauthority`.
* **`Xvfb` (*X Virtual Framebuffer*):** Servidor X11 completo que renderiza 100% en RAM sin monitor ni GPU física, ideal para CI/CD, inspección y pruebas *headless*.

#### SSH X11 Forwarding (`-X` vs. `-Y`), Waypipe, VNC, RDP, SPICE y XDMCP
* **SSH X11 Forwarding:** Túnel cifrado TCP 22 donde `sshd` crea un proxy en loopback (`X11UseLocalhost yes`, `DISPLAY=localhost:10.0`) e inyecta cookies temporales con `xauth`. **`ssh -X`** (*Untrusted*) usa la extensión `SECURITY` para aislar al servidor remoto; **`ssh -Y`** (*Trusted*) le otorga control total del X Server local (riesgo de *keylogging* en hosts no confiables). **`Waypipe`** cumple la misma función de forma nativa para apps Wayland.
* **VNC, `noVNC`/Websockify, RDP, SPICE, XDMCP y Guacamole:** **VNC (TigerVNC/`x11vnc`/RFB, `5900+N`)** debe correr sin `root`, en loopback (`-localhost`) y con **túnel SSH `-L`** o encapsulado en un Pod hacia **`noVNC`/`websockify`** (`127.0.0.1:6080` en navegador HTML5); **RDP (`xrdp`/Remmina)** aporta cifrado/compresión WAN; **SPICE** optimiza consolas KVM/QEMU; **Apache Guacamole** traduce SSH/VNC/RDP a HTML5/HTTPS mediante su daemon **`guacd`**; y **XDMCP (UDP 177)** transmite logins X11 en texto plano y debe mantenerse deshabilitado fuera de túneles.
* **Terminales Tontas (*Dumb Terminals*), *Thin Clients* (POS/LTSP) y *Zero Clients*:** Dispositivos sin disco duro ni estado crítico en el puesto de trabajo (desde `VT100` serial y *X Terminals*/`LTSP` PXE hasta cajas de supermercado/bancos y navegadores HTML5 con `noVNC` o `Guacamole`). Toda la lógica y la sesión permanecen vivas en el servidor central, permitiendo reemplazo físico inmediato y cero datos sensibles en el mostrador.

#### Accesibilidad en Linux: AccessX, Orca, `brltty` y `kmag`
* **AccessX / XKB y Escritorio:** Funciones motoras (`StickyKeys`, `MouseKeys`, `ToggleKeys`, `SlowKeys`, `RepeatKeys`, `BounceKeys`) más teclados en pantalla (`xkbd`, `kvbd`, `onboard`).
* **Orca, `brltty` y `kmag`:** **`Orca`** (`Alt+Super+s`, `orca --setup`) es el lector de pantalla gráfico estándar para GNOME y Plasma (síntesis de voz, eco de teclado, pronunciación y soporte Braille mediante el demonio **`brltty`**); **`kmag`** y GNOME Zoom ofrecen ampliación de pantalla junto a temas de Alto Contraste.

* 📖 [Ver Teoría Maestra de Sistemas Gráficos 3.26](graficos/sistemas_graficos_x11_wayland_teoria.md), [Lab 3.27: Inspección X11 Headless con Xvfb & xauth](graficos/x11_inspeccion_headless_xvfb_xauth.md), [Lab 3.28: Acceso Gráfico Remoto Seguro (SSH -X y Túnel VNC)](graficos/acceso_grafico_remoto_ssh_x11_vnc.md) y [Lab 3.30: Stack Gráfico en Podman Pod (DOOM + noVNC HTML5)](graficos/podman_x11_vnc_novnc_doom.md).
