#include "stdio.h"
#include "io.h"
#include "system.h"
#include <stdint.h>
#include <inttypes.h>

#include "drivers/inc/altera_avalon_timer.h"
#include "sys/alt_timestamp.h"
#include "altera_avalon_timer_regs.h"

static inline void timer_start(void)
{
    // Stop timer
    IOWR_ALTERA_AVALON_TIMER_CONTROL(
    		0x81000,
        ALTERA_AVALON_TIMER_CONTROL_STOP_MSK
    );

    // Load full 64-bit period (max value)
    IOWR_ALTERA_AVALON_TIMER_PERIOD_0(0x81000, 0xFFFF);
    IOWR_ALTERA_AVALON_TIMER_PERIOD_1(0x81000, 0xFFFF);
    IOWR_ALTERA_AVALON_TIMER_PERIOD_2(0x81000, 0xFFFF);
    IOWR_ALTERA_AVALON_TIMER_PERIOD_3(0x81000, 0xFFFF);

    // Start timer
    IOWR_ALTERA_AVALON_TIMER_CONTROL(
    		0x81000,
        ALTERA_AVALON_TIMER_CONTROL_START_MSK
    );
}

static inline uint64_t timer_read_cycles(void)
{
    // Trigger snapshot
    IOWR_ALTERA_AVALON_TIMER_SNAP_0(0x81000, 0);

    uint64_t s0 = IORD_ALTERA_AVALON_TIMER_SNAP_0(0x81000);
    uint64_t s1 = IORD_ALTERA_AVALON_TIMER_SNAP_1(0x81000);
    uint64_t s2 = IORD_ALTERA_AVALON_TIMER_SNAP_2(0x81000);
    uint64_t s3 = IORD_ALTERA_AVALON_TIMER_SNAP_3(0x81000);

    uint64_t remaining =
        (s3 << 48) |
        (s2 << 32) |
        (s1 << 16) |
        (s0);

    // Convert down-counter to up-counter
    return 0xFFFFFFFFFFFFFFFFULL - remaining;
}


uint32_t pack_2x2_int8(const int8_t A[2], const int8_t B[2]) {
    uint32_t packed = 0;

    // Layout: [ A1 | A0 | B1 | B0 ]  (MSB -> LSB)
    packed |= ((uint32_t)(uint8_t)B[0]);        // bits 7..0
//    printf("%d\n", packed);
    packed |= ((uint32_t)(uint8_t)B[1]) << 8;   // bits 15..8
//    printf("%d \n", packed);
    packed |= ((uint32_t)(uint8_t)A[0]) << 16;  // bits 23..16
//    printf("%d\n", packed);
    packed |= ((uint32_t)(uint8_t)A[1]) << 24;  // bits 31..24
//    printf("%d\n", packed);

    return packed;
}
+------------------------------------------------------------------------

//int main() {
//
//	timer_start();
//
//	uint64_t t_start = timer_read_cycles();
//
//    int A[2][2] = {
//        {1, 2},
//        {1, 2}
//    };
//
//    int B[2][2] = {
//        {1, 2},
//        {1, 2}
//    };
//
//    uint32_t C[2][2] = {0};
//
//
//    t_start = alt_timestamp();
//    // Multiply A and B (but instead of doing it in SW, pack operands per (i,j))
//    for (int i = 0; i < 2; i++) {
//        for (int j = 0; j < 2; j++) {
//
//            int8_t a_vec[2];
//            int8_t b_vec[2];
//
//            a_vec[0] = (int8_t)A[i][0];
//            a_vec[1] = (int8_t)A[i][1];
//
//            b_vec[0] = (int8_t)B[0][j];
//            b_vec[1] = (int8_t)B[1][j];
//
//            uint32_t packed = pack_2x2_int8(a_vec, b_vec);
//
//            // Send packed operands to your accelerator
//
//            IOWR(MVP_ACCELERATOR_0_BASE, 0, packed);
//
//            // If your accelerator returns a result via a read register, you'd do something like:
//            // C[i][j] = (int)IORD(MVP_ACCELERATOR_0_BASE, 1);
//            // But since you didn't ask for IORD handling, we'll leave C as-is for now.
//            uint32_t result;
//            result = IORD(MVP_ACCELERATOR_0_BASE,0);
//            C[i][j] = result;
//        }
//    }
//    uint64_t t_end = timer_read_cycles();
//
//
//    printf("Accelerator cycles: %" PRIu64 "\n",
//               (t_end - t_start));
//
//
//
//    // Print result (currently C will be zeros unless you read back results)
//    printf("Result matrix C:\n");
//    for (int i = 0; i < 2; i++) {
//        for (int j = 0; j < 2; j++) {
//            printf("%d ", C[i][j]);
//        }
//        printf("\n");
//    }
//
//    while (1) {}
//    return 0;
//}


int main() {

	timer_start();

	uint64_t t_start = timer_read_cycles();

    int A[2][2] = {
        {1, 2},
        {1, 2}
    };

    int B[2][2] = {
        {1, 2},
        {1, 2}
    };

    uint32_t C[2][2] = {0};


    t_start = alt_timestamp();
    // Multiply A and B (but instead of doing it in SW, pack operands per (i,j))
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {

            C[i][j] = 0;                 // important: reset accumulator

            for (int k = 0; k < 2; k++) {
                C[i][j] += A[i][k] * B[k][j];
            }

        }
    }

    uint64_t t_end = timer_read_cycles();

    uint64_t cpu_cycles = t_end - t_start;

    printf("without accelerator cycles: %" PRIu64 "\n",
               (cpu_cycles));

    uint64_t t_start_accelerator = timer_read_cycles();

        // Multiply A and B (but instead of doing it in SW, pack operands per (i,j))
        for (int i = 0; i < 2; i++) {
            for (int j = 0; j < 2; j++) {

                int8_t a_vec[2];
                int8_t b_vec[2];

                a_vec[0] = (int8_t)A[i][0];
                a_vec[1] = (int8_t)A[i][1];

                b_vec[0] = (int8_t)B[0][j];
                b_vec[1] = (int8_t)B[1][j];

                uint32_t packed = pack_2x2_int8(a_vec, b_vec);

                // Send packed operands to your accelerator

                IOWR(MVP_ACCELERATOR_0_BASE, 0, packed);

                // If your accelerator returns a result via a read register, you'd do something like:
                // C[i][j] = (int)IORD(MVP_ACCELERATOR_0_BASE, 1);
                // But since you didn't ask for IORD handling, we'll leave C as-is for now.
                uint32_t result;
                result = IORD(MVP_ACCELERATOR_0_BASE,0);
                C[i][j] = result;
            }
        }
        uint64_t t_end_accelerator = timer_read_cycles();

        uint64_t accelerator_cycles = t_end_accelerator - t_start_accelerator;
        printf("Accelerator cycles: %" PRIu64 "\n",
                   (accelerator_cycles));
        float speedup = ((float)cpu_cycles/(float)accelerator_cycles)*100-100.0;
        printf("speedup: %f%%\n",
                           (speedup));


    // Print result (currently C will be zeros unless you read back results)
    printf("Result matrix C:\n");
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
            printf("%d ", C[i][j]);
        }
        printf("\n");
    }

    while (1) {}
    return 0;
}
