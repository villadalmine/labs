// SPDX-License-Identifier: GPL-2.0
/*
 * edu_firmware_sim.c - Módulo LKM educativo que simula un controlador de dispositivo
 * con versión de firmware configurable y actualización en caliente (rmmod + insmod).
 *
 * Demuestra:
 *  - Ciclo de vida en Ring 0 (module_init / module_exit)
 *  - Emisión de eventos al ring buffer del kernel (dmesg / journalctl -k / syslog)
 *  - Parámetros configurables en /sys/module/edu_firmware_sim/parameters/
 *  - Exposición de estado en /proc/edu_firmware_sim mediante seq_file
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/moduleparam.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/utsname.h>

#define PROC_ENTRY_NAME "edu_firmware_sim"

static char *fw_version = "1.0.0";
module_param(fw_version, charp, 0644);
MODULE_PARM_DESC(fw_version, "Version simulada del firmware cargado por el controlador");

static char *device_name = "edu-virt-nic0";
module_param(device_name, charp, 0444);
MODULE_PARM_DESC(device_name, "Nombre logico del dispositivo hardware simulado");

static int reload_count = 1;
module_param(reload_count, int, 0644);
MODULE_PARM_DESC(reload_count, "Numero de revision o secuencia de carga del firmware");

static int edu_fw_proc_show(struct seq_file *m, void *v)
{
	seq_puts(m, "=== Estado del Controlador Educativo de Firmware (Ring 0 LKM) ===\n");
	seq_printf(m, "dispositivo_simulado : %s\n", device_name);
	seq_printf(m, "firmware_version     : %s\n", fw_version);
	seq_printf(m, "secuencia_carga      : %d\n", reload_count);
	seq_printf(m, "kernel_release       : %s\n", init_utsname()->release);
	return 0;
}

static int __init edu_fw_init(void)
{
	struct proc_dir_entry *entry;

	entry = proc_create_single(PROC_ENTRY_NAME, 0444, NULL, edu_fw_proc_show);
	if (!entry) {
		pr_err("edu_firmware_sim: [ERROR] No se pudo crear /proc/%s\n", PROC_ENTRY_NAME);
		return -ENOMEM;
	}

	pr_info("edu_firmware_sim: [INIT] Cargado driver para %s | Firmware v%s | seq=%d | kernel=%s\n",
		device_name, fw_version, reload_count, init_utsname()->release);
	return 0;
}

static void __exit edu_fw_exit(void)
{
	remove_proc_entry(PROC_ENTRY_NAME, NULL);
	pr_notice("edu_firmware_sim: [EXIT] Driver descargado de %s (ultima version activa: v%s, seq=%d)\n",
		  device_name, fw_version, reload_count);
}

module_init(edu_fw_init);
module_exit(edu_fw_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Laboratorio Linux SysAdmin (villadalmine/labs)");
MODULE_DESCRIPTION("Modulo LKM educativo para simular carga, syslog/dmesg y hot-update de firmware");
MODULE_VERSION("1.0");
