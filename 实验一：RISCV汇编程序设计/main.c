// #include <stdio.h>
#include "func.h"

#define NUM_A 0xc11c6e98    /* -9.777 */  
#define NUM_B 0xbf9df3b6    /* -1.234 */  

int main()
{
    uint32 result = fadd(NUM_A, NUM_B);     
    // printf("0x%x\n", result);

    return 0;
}

