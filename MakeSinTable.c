#include <stdio.h>
#include <math.h>
#include <stdint.h>

#define SINTABLEPOWER 14
#define SINTABLEENTRIES (1 << SINTABLEPOWER)
#define VALUES_PER_LINE 8

int main()
{
    printf("wire signed [15:0] sin [0:%d] = '{\n    ", SINTABLEENTRIES-1);

    for (int i = 0; i < SINTABLEENTRIES; ++i)
    {
        int16_t value = (int16_t)(sin(i * 2.0 * M_PI / SINTABLEENTRIES) * SINTABLEENTRIES / (2.0 * M_PI));
        printf("16'h%04X", (uint16_t)value);
        if (i != SINTABLEENTRIES - 1)
        {
            printf(",");
        }
        if ((i + 1) % VALUES_PER_LINE == 0)
        {
            printf("\n");
            if (i != SINTABLEENTRIES - 1)
            {
                printf("    ");
            }
        }
    }

    printf("};\n");
    return 0;
}
