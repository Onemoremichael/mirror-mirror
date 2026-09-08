#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    const char *names[] = {"c2dCreateSurface", "c2dUpdateSurface",
        "c2dLensCorrection", "c2dDraw", "c2dFinish", "c2dDestroySurface",
        "c2dMapAddr", "c2dUnMapAddr"};
    unsigned i;
    void *h = dlopen(argc > 1 ? argv[1] : "libMD2.so", RTLD_NOW);
    if (!h) { puts(dlerror()); return 1; }
    for (i=0; i<sizeof(names)/sizeof(names[0]); i++) {
        if (!dlsym(h, names[i])) { puts(dlerror()); return 2; }
        puts(names[i]);
    }
    puts("All camera conversion entry points resolve; no camera call made.");
    return 0;
}
