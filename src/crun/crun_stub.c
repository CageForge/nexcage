// Simple C stub for crun library
// This file provides a minimal implementation for the crun library

#include <stdio.h>
#include <stdlib.h>

// Simple stub functions
int crun_stub_init(void) {
    return 0;
}

void crun_stub_cleanup(void) {
    // Nothing to do
}

const char* crun_stub_version(void) {
    return "1.0.0-stub";
}
