#include <stdio.h>
#include <syslog.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    // validate that we have enough arguments
    if (argc != 3) {
        syslog(LOG_ERR, "Invalid number of arguments %d", argc);
        return EXIT_FAILURE;
    }

    char *filePath = argv[1];
    char *writeStr = argv[2];

    FILE *file = fopen(filePath, "w");
    if (!file) {
        syslog(LOG_ERR, "Could not open file: %s", filePath);
        return EXIT_FAILURE;
    }

    fprintf(file, "%s", writeStr);

}
