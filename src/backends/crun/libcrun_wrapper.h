#ifndef LIBCRUN_WRAPPER_H
#define LIBCRUN_WRAPPER_H

// Forward declarations to avoid full includes
struct libcrun_context_s;
struct libcrun_container_s;
struct libcrun_error_s;
struct libcrun_container_status_s;

typedef struct libcrun_context_s libcrun_context_t;
typedef struct libcrun_container_s libcrun_container_t;
typedef struct libcrun_error_s *libcrun_error_t;
typedef struct libcrun_container_status_s libcrun_container_status_t;

// Function declarations
int libcrun_container_create(libcrun_context_t *context, libcrun_container_t *container, unsigned int options, libcrun_error_t *err);
int libcrun_container_start(libcrun_context_t *context, const char *id, libcrun_error_t *err);
int libcrun_container_kill(libcrun_context_t *context, const char *id, const char *signal, libcrun_error_t *err);
int libcrun_container_delete(libcrun_context_t *context, void *def, const char *id, int force, libcrun_error_t *err);
int libcrun_container_state(libcrun_context_t *context, const char *id, void *out, libcrun_error_t *err);
int libcrun_container_delete_status(const char *state_root, const char *id, libcrun_error_t *err);
libcrun_container_t *libcrun_container_load_from_file(const char *path, libcrun_error_t *err);
void libcrun_container_free(libcrun_container_t *container);
int libcrun_read_container_status(libcrun_container_status_t *status, const char *state_root, const char *id, libcrun_error_t *err);
int libcrun_error_release(libcrun_error_t *err);

#define LIBCRUN_CREATE_OPTIONS_PREFORK (1U << 0)

#endif // LIBCRUN_WRAPPER_H

