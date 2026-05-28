        use Cron::Toolkit;
        use feature qw(say);

      use Test::MockTime qw( :all );
      #set_relative_time(-600);

      # do some tests depending on time increasing from 600 seconds ago

      #set_absolute_time(0);

      # do some more tests depending on time starting from the epoch
      # epoch may vary according to platform.  see perlport.

      #set_fixed_time(CORE::time());

      # do some more tests depending on time staying at the current actual time

      #set_absolute_time('1970-01-01T00:00:00Z');

      # do some tests depending on time starting at Unix epoch time

      #set_fixed_time('05/26/2025 23:00:00', '%m/%d/%Y %H:%M:%S');
      #set_fixed_time(CORE::time);

      #say scalar localtime(time);

      set_absolute_time('1970-01-01T00:00:00Z');
        say scalar gmtime(time);

        my $c = Cron::Toolkit->new(
            #expression => "0 30 14 ? * 6-2 *",
            expression => "*/15 * * * * ? *",
            time_zone  => "America/Chicago",
        );
        set_absolute_time('1970-01-01T00:00:00Z');

        say $c->describe;
        # 2:30 PM every day from Saturday to Tuesday of every month

        # next occurence in epoch seconds
        say scalar localtime($c->next);

        # previous occurence in epoch seconds
        #say scalar localtime($c->previous);

