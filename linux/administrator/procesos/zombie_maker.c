#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <unistd.h>

static void esperar(void)
{
    for (;;) {
        pause();
    }
}

int main(int argc, char *argv[])
{
    int sleep_seconds = 60;
    if (argc > 1) {
        sleep_seconds = atoi(argv[1]);
        if (sleep_seconds < 1) {
            sleep_seconds = 5;
        }
    }

    setvbuf(stdout, NULL, _IONBF, 0);

    // Este proceso adoptará al zombie si matamos a su padre original.
    if (prctl(PR_SET_CHILD_SUBREAPER, 1) == -1) {
        perror("prctl(PR_SET_CHILD_SUBREAPER)");
        return EXIT_FAILURE;
    }

    pid_t padre = fork();
    if (padre == -1) {
        perror("fork del padre");
        return EXIT_FAILURE;
    }

    if (padre == 0) {
        pid_t hijo = fork();
        if (hijo == -1) {
            perror("fork del hijo");
            _exit(EXIT_FAILURE);
        }

        if (hijo == 0) {
            printf("[Hijo PID: %d] Dormire %d segundos.\n", getpid(), sleep_seconds);
            sleep(sleep_seconds);
            printf("[Hijo PID: %d] Termine. Ahora soy zombie porque mi padre no hace wait().\n",
                   getpid());
            _exit(EXIT_SUCCESS);
        }

        printf("[Padre PID: %d] Hijo PID: %d. No llamare a wait().\n", getpid(), hijo);
        printf("Mata este padre despues de que el hijo sea zombie.\n");
        esperar();
    }

    printf("[Subreaper PID: %d] Padre original PID: %d.\n", getpid(), padre);
    printf("Este proceso tampoco llamara a wait(); mantendra al zombie adoptado.\n");
    esperar();
}
