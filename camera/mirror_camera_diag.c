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
	pr_info("mirror_camera_diag: read-only CSI diagnostics ready\n");
	return 0;

proc_failed:
	iounmap(mirror_csid0);
map_failed:
	if (mirror_csiphy0)
		iounmap(mirror_csiphy0);
	return -ENOMEM;
}

static void __exit mirror_camera_diag_exit(void)
{
	remove_proc_entry("mirror_camera_diag", NULL);
	iounmap(mirror_csid0);
	iounmap(mirror_csiphy0);
}

module_init(mirror_camera_diag_init);
module_exit(mirror_camera_diag_exit);

MODULE_DESCRIPTION("Read-only camera CSI diagnostics for the Lululemon Mirror");
MODULE_AUTHOR("mirror-mirror project");
MODULE_LICENSE("GPL v2");
