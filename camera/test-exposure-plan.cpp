#include "mirror-exposure-plan.h"
#include <assert.h>
#include <stdio.h>
int main() {
    mirror_exposure_register r[6], previous[6];
    const unsigned baseline[6] = {48,40,48,38,96,20};
    assert(mirror_exposure_plan(0,r));
    for (unsigned i=0;i<6;i++) assert(r[i].value==baseline[i]);
    assert(!mirror_exposure_plan(-13,r));
    assert(!mirror_exposure_plan(13,r));
    assert(!mirror_exposure_plan(0,0));
    for (int step=-12;step<=12;step++) {
        assert(mirror_exposure_plan(step,r));
        for(unsigned i=0;i<6;i++) {
            if(step>-12) { assert(r[i].value>=previous[i].value); assert(r[i].address==previous[i].address); }
            previous[i]=r[i];
        }
        assert(r[4].value>=r[0].value);
        assert(r[0].value>r[1].value && r[2].value>r[3].value);
        assert(r[5].value<r[1].value);
    }
    assert(mirror_exposure_plan(12,r));
    assert(r[0].value==192 && r[4].value==255);
    puts("PASS: exposure bounds, monotonic targets, window ordering, exact stock restoration");
}
