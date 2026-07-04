#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef __EMSCRIPTEN__
extern char *kpse_remote_fetch_js(const char *name, int format);
extern int shell_escape_dispatch_js(const char *cmd, const char *cwd);
#endif

extern char *__real_kpse_find_file(const char *name, int format, int must_exist);

char *__wrap_kpse_find_file(const char *name, int format, int must_exist)
{
    char *result = __real_kpse_find_file(name, format, must_exist);
    if (result != NULL)
        return result;

#ifdef __EMSCRIPTEN__
    result = kpse_remote_fetch_js(name, format);
    if (result != NULL && access(result, F_OK) == 0)
        return result;
#endif

    return NULL;
}

#ifdef __EMSCRIPTEN__
int system(const char *cmd)
{
    char cwd[4096];

    if (cmd == NULL)
        return 0;

    if (getcwd(cwd, sizeof(cwd)) == NULL)
        cwd[0] = '\0';

    return shell_escape_dispatch_js(cmd, cwd);
}
#endif
