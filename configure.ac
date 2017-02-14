AC_INIT([wikilint], [0.1], [tim@tim-landscheidt.de])
AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_MACRO_DIR([m4])

AM_INIT_AUTOMAKE([foreign no-dist color-tests parallel-tests silent-rules -Wall])
AC_PROG_INSTALL

# For tests.
AC_REQUIRE_AUX_FILE([tap-driver.sh])
AC_PROG_AWK

AX_PROG_PERL_MODULES([CGI DBD::SQLite DBI HTML::Entities LWP::UserAgent MediaWiki::API URI::Escape],
                     [],
                     [AC_MSG_ERROR(Perl module requirements unfulfilled)])

# Directories.
AC_ARG_WITH([cgibindir],
            AS_HELP_STRING([--with-cgibindir=DIR],
                           [Install CGI executables in DIR]),
            [CGIBINDIR=${withval}],
            [CGIBINDIR=${HOME}/public_html/cgi-bin])
AC_ARG_WITH([htdocsdir],
            AS_HELP_STRING([--with-htdocsdir=DIR],
                           [Install HTML files in DIR]),
            [HTDOCSDIR=${withval}],
            [HTDOCSDIR=${HOME}/public_html/wikilint])

pmdir_relative_path=`\
  $PERL -MConfig \
        -wle '($_ = $Config{installsitelib})
              =~ s!^\Q$Config{siteprefix}/!!; \
              print'`
AC_ARG_WITH([pmdir],
            AS_HELP_STRING([--with-pmdir=DIR],
                           [Install Perl modules in DIR]),
            [PMDIR=${withval}],
            [PMDIR='${prefix}'/"$pmdir_relative_path"])

# Directories.
AC_SUBST([cgibindir],        [$CGIBINDIR])
AC_SUBST([htdocsdir],        [$HTDOCSDIR])
AC_SUBST([pkglangdatadir],   ['$(pkgdatadir)/langdata'])
AC_SUBST([pkglangdatadedir], ['$(pkgdatadir)/langdata/de'])
AC_SUBST([pkglangdataendir], ['$(pkgdatadir)/langdata/en'])
AC_SUBST([pmdir],            [$PMDIR])
AC_SUBST([pmwikilintdir],    ['$(pmdir)/Wikilint'])
AC_SUBST([pmwikilintdbdir],  ['$(pmdir)/Wikilint/DB'])

# URL paths.
AC_ARG_WITH([tool_path],
            AS_HELP_STRING([--with-tool_path=URL],
                           [Use URL as tool path]),
            [TOOL_PATH=${withval}],
            [TOOL_PATH=http://toolserver.org/~timl/cgi-bin/wikilint])
AC_ARG_WITH([static_html_path],
            AS_HELP_STRING([--with-static_html_path=URL],
                           [Use URL as static HTML path]),
            [STATIC_HTML_PATH=${withval}],
            [STATIC_HTML_PATH=/~timl/wikilint/])
AC_SUBST([tool_path],        [$TOOL_PATH])
AC_SUBST([static_html_path], [$STATIC_HTML_PATH])


AC_CONFIG_FILES([Makefile
                 cgi-bin/Makefile
                 htdocs/Makefile
                 lib/Makefile
                 lib/Wikilint/Makefile
                 lib/Wikilint/DB/Makefile
                 share/langdata/de/Makefile
                 share/langdata/en/Makefile
                 tests/Makefile])

AC_OUTPUT
