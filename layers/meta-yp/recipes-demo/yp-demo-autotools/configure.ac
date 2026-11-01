AC_INIT([yp-demo-autotools], [0.1])
AC_CONFIG_SRCDIR([demo.c])
AC_CONFIG_MACRO_DIR([m4])
AM_INIT_AUTOMAKE([foreign])
AC_PROG_CC

AC_ARG_ENABLE([static],
    [AS_HELP_STRING([--disable-static], [disable static libraries])],
    [], [enable_static=no])
AC_ARG_ENABLE([json],
    [AS_HELP_STRING([--enable-json], [enable JSON support])],
    [], [enable_json=no])
AS_CASE([$enable_static], [yes|no], [],
    [AC_MSG_ERROR([--enable-static expects yes or no])])
AS_CASE([$enable_json], [yes|no], [],
    [AC_MSG_ERROR([--enable-json expects yes or no])])

AC_CONFIG_FILES([Makefile])
AC_OUTPUT
