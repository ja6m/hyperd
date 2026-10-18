#ifndef NET_H
#define NET_H
#include <stddef.h>
#include <sys/types.h>

int     net_listen(const char *port, int backlog);   /* returns fd or -1 */
ssize_t net_write_all(int fd, const void *buf, size_t len);

#endif
