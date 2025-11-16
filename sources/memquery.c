#include <stdio.h>

/**
 * Get available memory information from /proc/meminfo.
 *
 * @param availableMemoryKb Output: available system memory in KB
 * @param freeSwapKb Output: free swap space in KB
 * @param hugePagesInfoKb Optional output: free huge pages memory in KB (pass NULL to ignore)
 * @return 0 on success, 1 on error
 */
int getAvailableMemory(long *availableMemoryKb, long *freeSwapKb, long *hugePagesInfoKb) {
    FILE *meminfoFile = NULL;
    char lineBuffer[512];
    long hugeTlbTotalPages = -1;
    long hugeTlbFreePages = -1;
    long hugeTlbPageSize = -1;

    if (availableMemoryKb == NULL || freeSwapKb == NULL) {
        return 1;
    }

    meminfoFile = fopen("/proc/meminfo", "r");
    if (meminfoFile == NULL) {
        return 1;
    }

    *availableMemoryKb = -1;
    *freeSwapKb = -1;
    if (hugePagesInfoKb != NULL) {
        *hugePagesInfoKb = 0;  // Default to 0 if huge pages not configured
    }

    while (fgets(lineBuffer, sizeof(lineBuffer), meminfoFile)) {
        long value;
        if (sscanf(lineBuffer, "MemAvailable: %ld kB", &value) == 1) {
            *availableMemoryKb = value;
        } else if (sscanf(lineBuffer, "SwapFree: %ld kB", &value) == 1) {
            *freeSwapKb = value;
        } else if (sscanf(lineBuffer, "HugePages_Total: %ld", &value) == 1) {
            hugeTlbTotalPages = value;
        } else if (sscanf(lineBuffer, "HugePages_Free: %ld", &value) == 1) {
            hugeTlbFreePages = value;
        } else if (sscanf(lineBuffer, "Hugepagesize: %ld kB", &value) == 1) {
            hugeTlbPageSize = value;
        }

        // Early exit when required values are found
        if (*availableMemoryKb != -1 && *freeSwapKb != -1) {
            // Continue reading to get huge pages info if caller wants it
            if (hugePagesInfoKb == NULL ||
                (hugeTlbTotalPages != -1 && hugeTlbFreePages != -1 && hugeTlbPageSize != -1)) {
                break;
            }
        }
    }

    fclose(meminfoFile);

    // Validate that required values were found
    if (*availableMemoryKb == -1 || *freeSwapKb == -1) {
        return 1;
    }

    // Report huge pages separately if caller wants it
    if (hugePagesInfoKb != NULL &&
        hugeTlbTotalPages > 0 &&
        hugeTlbFreePages != -1 &&
        hugeTlbPageSize != -1) {
        *hugePagesInfoKb = hugeTlbFreePages * hugeTlbPageSize;
    }

    return 0;
}

int main(int argc, char const *argv[])
{
    // Get all memory info including huge pages
    long availMem, freeSwap, hugePages;
    if (getAvailableMemory(&availMem, &freeSwap, &hugePages) == 0) {
        printf("Available: %ld KB\n", availMem);
        printf("Free Swap: %ld KB\n", freeSwap);
        printf("Free Huge Pages: %ld KB\n", hugePages);

        // Caller decides how to combine them for UMA systems
        long totalAllocatable = availMem + freeSwap + hugePages;
    }
}
