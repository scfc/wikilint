TESTS_ENVIRONMENT = PERL5LIB=$(top_srcdir)/lib; export PERL5LIB;
TEST_LOG_DRIVER = env AM_TAP_AWK='$(AWK)' $(SHELL) $(top_srcdir)/build-aux/tap-driver.sh
TESTS = check_unformatted_refs.test html-output.test		\
   remove_year_and_date_links.test escapesectiontitle.test	\
   remove_stuff_to_ignore.test tag_dates_rest_line.test
