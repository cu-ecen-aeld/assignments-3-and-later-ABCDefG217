#include "systemcalls.h"
#include <stdlib.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdarg.h>
#include <fcntl.h>

/**
 * @brief Executes a command using system().
 * @param cmd The command to execute.
 * @return true if successful, false otherwise.
 */
bool do_system(const char *cmd)
{
    int ret = system(cmd);
    return (ret == 0);
}

/**
 * @brief Executes a command using execv().
 * @param count Number of arguments.
 * @param ... Command followed by its arguments.
 * @return true if successful, false otherwise.
 */
bool do_exec(int count, ...)
{
    va_list args;
    va_start(args, count);

    char *command[count + 1];
    for (int i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;
    va_end(args);

    pid_t pid = fork();
    if (pid == -1)
    {
        return false;
    }
    else if (pid == 0)
    {
        execv(command[0], command);
        exit(EXIT_FAILURE); // If execv fails
    }

    int status;
    if (waitpid(pid, &status, 0) == -1)
    {
        return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

/**
 * @brief Executes a command using execv() and redirects output to a file.
 * @param outputfile Path to the output file.
 * @param count Number of arguments.
 * @param ... Command followed by its arguments.
 * @return true if successful, false otherwise.
 */
bool do_exec_redirect(const char *outputfile, int count, ...)
{
    va_list args;
    va_start(args, count);

    char *command[count + 1];
    for (int i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;
    va_end(args);

    pid_t pid = fork();
    if (pid == -1)
    {
        return false;
    }
    else if (pid == 0)
    {
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd == -1)
        {
            exit(EXIT_FAILURE);
        }

        dup2(fd, STDOUT_FILENO);
        close(fd);

        execv(command[0], command);
        exit(EXIT_FAILURE);
    }

    int status;
    if (waitpid(pid, &status, 0) == -1)
    {
        return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

