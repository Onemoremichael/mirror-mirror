/*
 * Read-only diagnostics for the MSM8916 camera receiver used by the Mirror.
 *
 * The stock kernel clears CSIPHY interrupt status as soon as its handler runs,
 * and was built without dynamic debug.  This module exposes the live CSI
 * register banks through /proc before the timeout handler clears them.  It
 * deliberately performs no register writes.
 */

#include <linux/init.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/string.h>
#include <linux/kallsyms.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>
#include "msm_sensor.h"
#include "cci/msm_cci.h"

/* Named OV5640 only. Read via the stock driver's locked I2C API; never write. */
static int mirror_sensor_exposure_show(struct seq_file *out, void *unused)
{
	struct msm_sensor_ctrl_t *snapshot;
	struct msm_camera_i2c_client client;
	struct msm_camera_i2c_fn_t functions;
	struct msm_camera_cci_client cci_client;
	struct cci_device *cci;
	struct v4l2_subdev *(*get_cci)(void) = (void *)kallsyms_lookup_name("msm_cci_get_subdev");
	void *private_data;
	u8 references;
	enum msm_cci_state_t cci_state;
	struct msm_sensor_ctrl_t *ctrl = (void *)kallsyms_lookup_name("ov5640_s_ctrl");
	struct mutex *lock = (void *)kallsyms_lookup_name("ov5640_mut");
	unsigned long read_fn = kallsyms_lookup_name("msm_camera_cci_i2c_read");
	const u16 registers[] = {0x300a,0x300b,0x3500,0x3501,0x3502,0x3503,
		0x350a,0x350b,0x3406,0x3a00,0x3a18,0x3a19,0x380e,0x380f,
		0x3a0f,0x3a10,0x3a1b,0x3a1e,0x5587,0x5588};
	unsigned int i;
	/* Offsets corroborated by preserved stock sensor_config32 disassembly. */
	BUILD_BUG_ON(offsetof(struct msm_sensor_ctrl_t, sensor_i2c_client) != 2856);
	BUILD_BUG_ON(offsetof(struct msm_sensor_ctrl_t, camera_stream_type) != 2960);
	snapshot = vmalloc(sizeof(*snapshot));
	if (!snapshot) return -ENOMEM;
	if (!ctrl || !lock || !read_fn || probe_kernel_read(snapshot, ctrl, sizeof(*snapshot))
			|| snapshot->msm_sensor_mutex != lock) {
		seq_puts(out, "Expected stock sensor layout unavailable\n"); goto free_snapshot;
	}
	if (!mutex_trylock(lock)) { seq_puts(out, "Sensor busy; retry later\n"); goto free_snapshot; }
	if (probe_kernel_read(snapshot, ctrl, sizeof(*snapshot))) {
		seq_puts(out, "Sensor snapshot unavailable\n"); goto done;
	}
	if (!snapshot->sensor_i2c_client
			|| probe_kernel_read(&client, snapshot->sensor_i2c_client, sizeof(client))
			|| !client.i2c_func_tbl
			|| probe_kernel_read(&functions, client.i2c_func_tbl, sizeof(functions))
			|| (unsigned long)functions.i2c_read != read_fn
			|| client.addr_type != MSM_CAMERA_I2C_WORD_ADDR) {
		seq_puts(out, "Unexpected I2C implementation; no reads attempted\n"); goto done;
	}
	seq_printf(out, "stream_type=%d power_state=%d\n",
		snapshot->camera_stream_type, snapshot->sensor_state);
	/* The custom OV5640 power callbacks do not maintain sensor_state.
	 * Require the named, initialized CCI controller instead. Holding the
	 * OV5640 mutex excludes its power-down path throughout these reads.
	 * Check the subdevice/back-pointer relationship before using its state.
	 */
	if (!get_cci || !client.cci_client
			|| probe_kernel_read(&cci_client, client.cci_client, sizeof(cci_client))
			|| !cci_client.cci_subdev || cci_client.cci_subdev != get_cci()
			|| cci_client.cci_i2c_master < 0 || cci_client.cci_i2c_master >= MASTER_MAX
			|| probe_kernel_read(&private_data, &cci_client.cci_subdev->dev_priv, sizeof(private_data))
			|| !private_data) {
		seq_puts(out, "CCI identity unavailable; no reads attempted\n"); goto done;
	}
	cci = private_data;
	if (&cci->msm_sd.sd != cci_client.cci_subdev
			|| probe_kernel_read(&references, &cci->ref_count, sizeof(references))
			|| probe_kernel_read(&cci_state, &cci->cci_state, sizeof(cci_state))) {
		seq_puts(out, "CCI layout unavailable; no reads attempted\n"); goto done;
	}
	seq_printf(out, "cci_state=%d references=%u\n", cci_state, references);
	if (cci_state != CCI_STATE_ENABLED || references != 1) {
		seq_puts(out, "CCI not exclusively initialized; no reads attempted\n"); goto done;
	}
	for (i = 0; i < ARRAY_SIZE(registers); i++) {
		u16 value = 0;
		int rc = functions.i2c_read(snapshot->sensor_i2c_client, registers[i],
			&value, MSM_CAMERA_I2C_BYTE_DATA);
		if (rc < 0) { seq_printf(out, "READ_ERROR %04x rc=%d\n", registers[i], rc); break; }
		seq_printf(out, "%04x=%02x\n", registers[i], value);
	}
done:
	mutex_unlock(lock);
free_snapshot:
	vfree(snapshot);
	return 0;
}
static int mirror_sensor_exposure_open(struct inode *inode, struct file *file)
{ return single_open(file, mirror_sensor_exposure_show, NULL); }
static const struct file_operations mirror_sensor_exposure_fops = {
	.owner = THIS_MODULE, .open = mirror_sensor_exposure_open, .read = seq_read,
	.llseek = seq_lseek, .release = single_release,
};

/* Read named stock-driver tables/code only; no MMIO or sensor writes here. */
static int mirror_sensor_tables_show(struct seq_file *out, void *unused)
{
	typedef int (*symbol_size_fn)(unsigned long, unsigned long *, unsigned long *);
	symbol_size_fn symbol_size = (symbol_size_fn)kallsyms_lookup_name("kallsyms_lookup_size_offset");
	const char *names[] = {"ov5640_recommend_settings", "ov5640_1080P_settings",
		"ov5640_sensor_config32", "ov5640_sensor_config",
		"ov5640_start_settings", "ov5640_stop_settings",
		"ov5640_enable_aec_settings", "ov5640_disable_aec_settings"};
	unsigned int n;
	if (!symbol_size) { seq_puts(out, "symbol sizing unavailable\n"); return 0; }
	for (n = 0; n < ARRAY_SIZE(names); n++) {
		unsigned long addr = kallsyms_lookup_name(names[n]), size = 0, offset = 0, i;
		if (!addr || !symbol_size(addr, &size, &offset) || offset || size > 32768) {
			seq_printf(out, "%s unavailable or outside bounds\n", names[n]); continue;
		}
		seq_printf(out, "SYMBOL %s size=%lu\n", names[n], size);
		for (i = 0; i < size; i += 32) {
			unsigned char bytes[32]; unsigned int j;
			unsigned int count = min_t(unsigned long, sizeof(bytes), size-i);
			if (probe_kernel_read(bytes, (void *)(addr+i), count)) { seq_puts(out, "READ_ERROR\n"); break; }
			seq_printf(out, "%04lx:", i);
			for (j=0; j<count; j++) seq_printf(out, "%02x", bytes[j]);
			seq_putc(out, '\n');
		}
	}
	return 0;
}

static int mirror_sensor_tables_open(struct inode *inode, struct file *file)
{ return single_open(file, mirror_sensor_tables_show, NULL); }
static const struct file_operations mirror_sensor_tables_fops = {
	.owner = THIS_MODULE, .open = mirror_sensor_tables_open, .read = seq_read,
	.llseek = seq_lseek, .release = single_release,
};

#define MIRROR_CSIPHY0_PHYS 0x01b0ac00
#define MIRROR_CSID0_PHYS   0x01b08000
#define MIRROR_CSI_MAP_SIZE 0x00000400

static void __iomem *mirror_csiphy0;
static void __iomem *mirror_csid0;

static void mirror_dump_words(struct seq_file *out, const char *name,
	void __iomem *base, unsigned int first, unsigned int last)
{
	unsigned int offset;

	seq_printf(out, "%s 0x%08x..0x%08x\n", name, first, last);
	for (offset = first; offset <= last; offset += 4) {
		if (((offset - first) & 0x1f) == 0)
			seq_printf(out, "  %03x:", offset);
		seq_printf(out, " %08x", readl_relaxed(base + offset));
		if (((offset - first) & 0x1f) == 0x1c || offset == last)
			seq_putc(out, '\n');
	}
}

static bool mirror_camera_node(const struct device_node *node)
{
	const char *compat;
	int length;

	if (node->full_name &&
	    (strstr(node->full_name, "camera") ||
	     strstr(node->full_name, "csiphy") ||
	     strstr(node->full_name, "csid") ||
	     strstr(node->full_name, "cci")))
		return true;

	compat = of_get_property(node, "compatible", &length);
	return compat && length > 0 &&
		(strstr(compat, "camera") || strstr(compat, "csiphy") ||
		 strstr(compat, "csid") || strstr(compat, "ov5640"));
}

static void mirror_dump_property(struct seq_file *out,
	const struct device_node *node, const char *name)
{
	const unsigned char *value;
	int length;
	int i;

	value = of_get_property(node, name, &length);
	if (!value || length <= 0)
		return;

	seq_printf(out, "  %s (%d):", name, length);
	for (i = 0; i < length && i < 96; i++)
		seq_printf(out, " %02x", value[i]);
	if (length > 96)
		seq_puts(out, " ...");
	seq_putc(out, '\n');
}

static void mirror_dump_device_tree(struct seq_file *out)
{
	struct device_node *node = NULL;

	seq_puts(out, "camera device-tree nodes\n");
	while ((node = of_find_all_nodes(node)) != NULL) {
		if (!mirror_camera_node(node))
			continue;
		seq_printf(out, "%s\n", node->full_name);
		mirror_dump_property(out, node, "compatible");
		mirror_dump_property(out, node, "status");
		mirror_dump_property(out, node, "cell-index");
		mirror_dump_property(out, node, "reg");
		mirror_dump_property(out, node, "interrupts");
		mirror_dump_property(out, node, "qcom,clock-rates");
		mirror_dump_property(out, node, "qcom,special-support-sensors");
		mirror_dump_property(out, node, "qcom,csiphy-sd-index");
		mirror_dump_property(out, node, "qcom,csid-sd-index");
		mirror_dump_property(out, node, "qcom,csi-lane-assign");
		mirror_dump_property(out, node, "qcom,csi-lane-mask");
	}
}

static int mirror_camera_diag_show(struct seq_file *out, void *unused)
{
	seq_puts(out, "Mirror MSM8916 CSI read-only diagnostic v1\n");
	mirror_dump_device_tree(out);

	/*
	 * CSIPHY 3.1 configuration lives at 0x000..0x1f4.  Most useful
	 * fields are lane configuration (0x000/0x040/0x080), global power
	 * (0x144), hardware version (0x188), and eight interrupt-status
	 * words beginning at 0x18c.
	 */
	mirror_dump_words(out, "csiphy0.config", mirror_csiphy0, 0x000, 0x10c);
	mirror_dump_words(out, "csiphy0.global", mirror_csiphy0, 0x140, 0x1f4);

	/* CSID 3.1 includes core routing, packet capture, and packet counters. */
	mirror_dump_words(out, "csid0", mirror_csid0, 0x000, 0x0b4);
	return 0;
}

static int mirror_camera_diag_open(struct inode *inode, struct file *file)
{
	return single_open(file, mirror_camera_diag_show, NULL);
}

static const struct file_operations mirror_camera_diag_fops = {
	.owner = THIS_MODULE,
	.open = mirror_camera_diag_open,
	.read = seq_read,
	.llseek = seq_lseek,
	.release = single_release,
};

static int __init mirror_camera_diag_init(void)
{
	mirror_csiphy0 = ioremap(MIRROR_CSIPHY0_PHYS, MIRROR_CSI_MAP_SIZE);
	mirror_csid0 = ioremap(MIRROR_CSID0_PHYS, MIRROR_CSI_MAP_SIZE);
	if (!mirror_csiphy0 || !mirror_csid0)
		goto map_failed;
	if (!proc_create("mirror_camera_diag", 0444, NULL,
			 &mirror_camera_diag_fops))
		goto proc_failed;
	if (!proc_create("mirror_sensor_tables", 0444, NULL, &mirror_sensor_tables_fops)) {
		remove_proc_entry("mirror_camera_diag", NULL);
		goto proc_failed;
	}
	pr_info("mirror_camera_diag: read-only CSI diagnostics ready\n");
	if (!proc_create("mirror_sensor_exposure", 0444, NULL, &mirror_sensor_exposure_fops)) {
		remove_proc_entry("mirror_sensor_tables", NULL);
		remove_proc_entry("mirror_camera_diag", NULL);
		goto proc_failed;
	}
	return 0;

proc_failed:
map_failed:
	if (mirror_csid0)
		iounmap(mirror_csid0);
	if (mirror_csiphy0)
		iounmap(mirror_csiphy0);
	return -ENOMEM;
}

static void __exit mirror_camera_diag_exit(void)
{
	remove_proc_entry("mirror_camera_diag", NULL);
	remove_proc_entry("mirror_sensor_tables", NULL);
	remove_proc_entry("mirror_sensor_exposure", NULL);
	iounmap(mirror_csid0);
	iounmap(mirror_csiphy0);
}

module_init(mirror_camera_diag_init);
module_exit(mirror_camera_diag_exit);

MODULE_DESCRIPTION("Read-only camera CSI diagnostics for the Lululemon Mirror");
MODULE_AUTHOR("mirror-mirror project");
MODULE_LICENSE("GPL v2");
