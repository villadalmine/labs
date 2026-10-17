#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>

// Banderas modificadas por los manejadores de señales.
volatile sig_atomic_t keep_running = 1;
volatile sig_atomic_t print_status = 0;

// SIGTERM y SIGINT solicitan que el proceso termine.
void handle_sigterm(int signum) {
    (void)signum;
    keep_running = 0;
}

// SIGUSR1 solicita mostrar el estado en el bucle principal.
void handle_sigusr1(int signum) {
    (void)signum;
    print_status = 1;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    unsigned long long counter = 0;
    struct sigaction action_term = {0};
    action_term.sa_handler = handle_sigterm;
    sigemptyset(&action_term.sa_mask);
    sigaction(SIGTERM, &action_term, NULL);
    sigaction(SIGINT, &action_term, NULL);

    struct sigaction action_usr1 = {0};
    action_usr1.sa_handler = handle_sigusr1;
    sigemptyset(&action_usr1.sa_mask);
    sigaction(SIGUSR1, &action_usr1, NULL);

    printf("Proceso iniciado PID: %d\n", getpid());
    fflush(stdout);

    while (keep_running) {
        counter++;

        if (print_status) {
            printf("[PID %d] SIGUSR1 recibido. Contador: %llu\n", getpid(), counter);
            fflush(stdout);
            print_status = 0;
        }
    }

    printf("\n[PID %d] Señal de terminación recibida. Contador final: %llu\n",
           getpid(), counter);
    return EXIT_SUCCESS;
}
