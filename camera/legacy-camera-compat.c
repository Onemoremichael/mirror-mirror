/*
 * Compatibility hooks for the incomplete Qualcomm HY22 camera prebuilt set
 * and the older ISP userspace ABI used by those binaries.
 *
 * libmmcamera2_q3a_core.so references these optional hybrid-autofocus update
 * hooks, but the matching provider was not shipped in the public APQ8016
 * prebuilt bundle. The MIRROR OV5640 is fixed-focus, so the hooks are never
 * selected by its sensor library. Returning zero keeps the legacy dynamic
 * linker satisfied without claiming any autofocus capability.
 */

#include <dlfcn.h>
#include <stdarg.h>
#include <string.h>
#include <stdio.h>
#include <sys/types.h>
#include <android/log.h>

/* This old NDK's unistd.h also declares ioctl with an incompatible signed
 * request type. Declare readlink directly to preserve the existing hook ABI. */
extern ssize_t readlink(const char *, char *, size_t);

typedef unsigned char mirror_u8;
typedef unsigned int mirror_u32;

/*
 * HY22's ISP module was built before msm_vfe_camif_subsample_cfg was added to
 * msm_vfe_camif_cfg. Its VIDIOC_MSM_ISP_INPUT_CFG therefore encodes an
 * 88-byte payload (0xc05856c7), while the Mirror kernel accepts the current
 * 104-byte payload (0xc06856c7). The ioctl number includes sizeof(payload), so
 * the kernel otherwise rejects the request before looking at its contents.
 */
#define MIRROR_ISP_INPUT_CFG_OLD 0xc05856c7UL
#define MIRROR_ISP_INPUT_CFG_NEW 0xc06856c7UL

struct mirror_vfe_camif_cfg_old {
  mirror_u32 lines_per_frame;
  mirror_u32 pixels_per_line;
  mirror_u32 first_pixel;
  mirror_u32 last_pixel;
  mirror_u32 first_line;
  mirror_u32 last_line;
  mirror_u32 epoch_line0;
  mirror_u32 epoch_line1;
  mirror_u32 camif_input;
};

struct mirror_vfe_camif_subsample_cfg {
  mirror_u32 irq_subsample_period;
  mirror_u32 irq_subsample_pattern;
  mirror_u32 pixel_skip;
  mirror_u32 line_skip;
};

struct mirror_vfe_camif_cfg_new {
  mirror_u32 lines_per_frame;
  mirror_u32 pixels_per_line;
  mirror_u32 first_pixel;
  mirror_u32 last_pixel;
  mirror_u32 first_line;
  mirror_u32 last_line;
  mirror_u32 epoch_line0;
  mirror_u32 epoch_line1;
  mirror_u32 camif_input;
  struct mirror_vfe_camif_subsample_cfg subsample_cfg;
};

struct mirror_vfe_fetch_engine_cfg {
  mirror_u32 input_format;
  mirror_u32 buf_width;
  mirror_u32 buf_height;
  mirror_u32 fetch_width;
  mirror_u32 fetch_height;
  mirror_u32 x_offset;
  mirror_u32 y_offset;
  mirror_u32 buf_stride;
};

struct mirror_vfe_pix_cfg_old {
  struct mirror_vfe_camif_cfg_old camif_cfg;
  struct mirror_vfe_fetch_engine_cfg fetch_engine_cfg;
  mirror_u32 input_mux;
  mirror_u32 pixel_pattern;
  mirror_u32 input_format;
};

struct mirror_vfe_pix_cfg_new {
  struct mirror_vfe_camif_cfg_new camif_cfg;
  struct mirror_vfe_fetch_engine_cfg fetch_engine_cfg;
  mirror_u32 input_mux;
  mirror_u32 pixel_pattern;
  mirror_u32 input_format;
};

struct mirror_vfe_rdi_cfg {
  mirror_u8 cid;
  mirror_u8 frame_based;
};

struct mirror_vfe_input_cfg_old {
  union {
    struct mirror_vfe_pix_cfg_old pix_cfg;
    struct mirror_vfe_rdi_cfg rdi_cfg;
  } d;
  mirror_u32 input_src;
  mirror_u32 input_pix_clk;
};

struct mirror_vfe_input_cfg_new {
  union {
    struct mirror_vfe_pix_cfg_new pix_cfg;
    struct mirror_vfe_rdi_cfg rdi_cfg;
  } d;
  mirror_u32 input_src;
  mirror_u32 input_pix_clk;
};

typedef char mirror_old_input_cfg_size_must_be_88[
  sizeof(struct mirror_vfe_input_cfg_old) == 88 ? 1 : -1];
typedef char mirror_new_input_cfg_size_must_be_104[
  sizeof(struct mirror_vfe_input_cfg_new) == 104 ? 1 : -1];

typedef int (*mirror_ioctl_fn)(int, unsigned long, ...);

/* Bounded ABI evidence: configuration payloads only, never frame contents. */
static void mirror_trace_config(int fd, unsigned long request, const void *argument)
{
  static unsigned counts[8];
  unsigned nr = request & 255, size = (request >> 16) & 0x3fff;
  unsigned i, bucket;
  const unsigned char *bytes = argument;
  char hex[513];
  static const char digits[] = "0123456789abcdef";
  if (((request >> 8) & 255) != 'V' || !argument || nr < 193 || nr > 199)
    return;
  bucket = nr - 193;
  /* Sensor control shares this ioctl number with other camera controls.
   * Record only the leading command word and payload size; do not dereference
   * embedded pointers or label it as a sensor command without corroboration.
   */
  if (nr == 193 && size == 144) {
    unsigned command;
    char fdpath[64], target[128];
    ssize_t length;
    if (counts[bucket]++ >= 96) return;
    memcpy(&command, argument, sizeof(command));
    snprintf(fdpath, sizeof(fdpath), "/proc/self/fd/%d", fd);
    length = readlink(fdpath, target, sizeof(target) - 1);
    if (length < 0) length = 0;
    target[length] = 0;
    __android_log_print(ANDROID_LOG_INFO, "MirrorSensorABI",
      "fd=%d path=%s request=%08lx size=%u command=%u",
      fd, target, request, size, command);
    return;
  }
  if (counts[bucket]++ >= 12 || size > 256) return;
  for (i = 0; i < size; i++) {
    hex[2*i] = digits[bytes[i] >> 4];
    hex[2*i+1] = digits[bytes[i] & 15];
  }
  hex[size*2] = 0;
  __android_log_print(ANDROID_LOG_INFO, "MirrorIspABI",
    "request=%08lx size=%u data=%s", request, size, hex);
}

static void copy_camif_cfg(struct mirror_vfe_camif_cfg_new *to,
  const struct mirror_vfe_camif_cfg_old *from)
{
  to->lines_per_frame = from->lines_per_frame;
  to->pixels_per_line = from->pixels_per_line;
  to->first_pixel = from->first_pixel;
  to->last_pixel = from->last_pixel;
  to->first_line = from->first_line;
  to->last_line = from->last_line;
  to->epoch_line0 = from->epoch_line0;
  to->epoch_line1 = from->epoch_line1;
  to->camif_input = from->camif_input;
}

static void copy_fetch_cfg(struct mirror_vfe_fetch_engine_cfg *to,
  const struct mirror_vfe_fetch_engine_cfg *from)
{
  *to = *from;
}

int ioctl(int fd, unsigned long request, ...)
{
  static mirror_ioctl_fn real_ioctl;
  va_list args;
  void *argument;

  va_start(args, request);
  argument = va_arg(args, void *);
  va_end(args);

  if (!real_ioctl)
    real_ioctl = (mirror_ioctl_fn)dlsym(RTLD_NEXT, "ioctl");
  if (!real_ioctl)
    return -1;

  mirror_trace_config(fd, request, argument);

  if (request == MIRROR_ISP_INPUT_CFG_OLD && argument) {
    const struct mirror_vfe_input_cfg_old *old_cfg =
      (const struct mirror_vfe_input_cfg_old *)argument;
    struct mirror_vfe_input_cfg_new new_cfg;

    memset(&new_cfg, 0, sizeof(new_cfg));

    new_cfg.input_src = old_cfg->input_src;
    new_cfg.input_pix_clk = old_cfg->input_pix_clk;
    if (old_cfg->input_src == 0) {
      copy_camif_cfg(&new_cfg.d.pix_cfg.camif_cfg,
        &old_cfg->d.pix_cfg.camif_cfg);
      copy_fetch_cfg(&new_cfg.d.pix_cfg.fetch_engine_cfg,
        &old_cfg->d.pix_cfg.fetch_engine_cfg);
      new_cfg.d.pix_cfg.input_mux = old_cfg->d.pix_cfg.input_mux;
      new_cfg.d.pix_cfg.pixel_pattern = old_cfg->d.pix_cfg.pixel_pattern;
      new_cfg.d.pix_cfg.input_format = old_cfg->d.pix_cfg.input_format;
    } else {
      new_cfg.d.rdi_cfg = old_cfg->d.rdi_cfg;
    }
    return real_ioctl(fd, MIRROR_ISP_INPUT_CFG_NEW, &new_cfg);
  }

  return real_ioctl(fd, request, argument);
}

int af_haf_tof_update_func_tbl(void) { return 0; }
int af_haf_pdaf_update_func_tbl(void) { return 0; }
int af_haf_dciaf_update_func_tbl(void) { return 0; }
int af_haf_dbg_update_func_tbl(void) { return 0; }
int af_haf_pdaf3_update_func_tbl(void) { return 0; }
int af_haf_enter(void) { return 0; }
int af_haf_get_start_pos(void) { return 0; }
int af_haf_update_depth_input(void) { return 0; }
int af_haf_update_sad_params(void) { return 0; }
int af_haf_util_change_state(void) { return 0; }
