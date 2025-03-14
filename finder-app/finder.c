#include <stdio.h>
#include <syslog.h>
#include <sys/stat.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

int processDirectory(char *path, char *searchStr, size_t *fileCount, size_t *totalLineCount) {
    // path might be a dirpath or a filepath
    struct stat statResult;
    if (lstat(path, &statResult) != 0) {
        syslog(LOG_ERR, "Could not open stat: %s", path);
        return EXIT_FAILURE;
    }

    if (S_ISDIR(statResult.st_mode) == 0) {
        // this is not a directory
        FILE *file = fopen(path, "r");
        if (!file) {
            syslog(LOG_ERR, "Could not open file: %s", path);
            return EXIT_FAILURE;
        }

        size_t lineSize = 0;
        size_t file_match = 0;
        char *lineBuffer = NULL;
        // read the file line by line
        while ((getline(&lineBuffer, &lineSize, file)) > 0) {
            printf("%s\n", lineBuffer);
            if (strstr(lineBuffer, searchStr)) {
                // this line matches
                *totalLineCount += 1;
                // switch for > 1 match in a file
                if (file_match == 0) {
                    file_match = 1;
                }

            }
        }

        // record that file matches
        if (file_match == 1) {
            *fileCount += 1;
        }

        free(lineBuffer);
        fclose(file);
        return EXIT_SUCCESS;
    }

    if (S_ISDIR(statResult.st_mode) == 1) {
        // this is a directory
        DIR *dir = opendir(path);
        if (NULL == dir) {
            syslog(LOG_ERR, "Could not open directory: %s", path);
            closedir(dir);
            return EXIT_FAILURE;

        }
        struct dirent *dirEnt;

        while ((dirEnt = readdir(dir))) {
            char *fileName = dirEnt->d_name;

            // skip . and ..
            if (strcmp(fileName, ".") == 0) {
                continue;
            }
            if (strcmp(fileName, "..") == 0) {
                continue;
            }
            // construct the full file path
            char pathBuffer[PATH_MAX];
            snprintf(pathBuffer, sizeof(pathBuffer), "%s/%s", path, fileName);

            // recurse
            int result = processDirectory(pathBuffer, searchStr, fileCount, totalLineCount);
            if (result != EXIT_SUCCESS) {
                return result;
            }
        }
        closedir(dir);
        return EXIT_SUCCESS;

    }

    syslog(LOG_ERR, "Path is not a regular file or a directory: %s %d", path, statResult.st_mode);
    return EXIT_FAILURE;
}

int main(int argc, char **argv) {
    openlog(NULL, 0, LOG_USER);

    // validate that we have enough arguments
    if (argc != 3) {
        syslog(LOG_ERR, "Invalid number of arguments %d", argc);
        return 1;
    }

    char *filesDir = argv[1];
    char *searchStr = argv[2];

    size_t fileCount = 0;
    size_t totalLineCount = 0;
    int result = processDirectory(filesDir, searchStr, &fileCount, &totalLineCount);
    printf("The number of files are %zu and the number of matching lines are %zu\n", fileCount, totalLineCount);
    return result;
}
