/*
 * Compatibility hooks for the incomplete Qualcomm HY22 camera prebuilt set.
 *
 * libmmcamera2_q3a_core.so references these optional hybrid-autofocus update
 * hooks, but the matching provider was not shipped in the public APQ8016
 * prebuilt bundle. The MIRROR OV5640 is fixed-focus, so the hooks are never
 * selected by its sensor library. Returning zero keeps the legacy dynamic
 * linker satisfied without claiming any autofocus capability.
 */

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
