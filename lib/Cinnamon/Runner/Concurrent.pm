package Cinnamon::Runner::Concurrent;
use strict;
use warnings;
use Cinnamon::Runner;
push our @ISA, qw(Cinnamon::Runner);

use Cinnamon::Logger;
use Cinnamon::Config;

use Coro;
use Coro::Select;

sub start {
    my ($class, $hosts, $task, @args) = @_;
    my $all_results = {};
    $hosts = [ @$hosts ];

    my $task_name           = $task->name;
    my $concurrency_setting = Cinnamon::Config::get('concurrency') || {};
    my $concurrency         = $concurrency_setting->{$task_name} || scalar @$hosts;

    while (my @target_hosts = splice @$hosts, 0, $concurrency) {
        my @coros;

        for my $host (@target_hosts) {
            my $coro = async {
                my $result = $class->execute($host, $task->code, @args);
                $all_results->{$host} = $result;
            };

            push @coros, $coro;
        }

        $_->join for @coros;
    }

    return $all_results;
}

sub execute {
    my ($class, $host, $task, @args) = @_;

    my $result = { host => $host, error => 0 };

    local $@;
    eval { $task->code->($host, @args) };
    if ($@) {
        chomp $@;
        log error => sprintf '[%s] %s', $host, $@;
        $result->{error} = 1;
    }

    return $result;
}

1;