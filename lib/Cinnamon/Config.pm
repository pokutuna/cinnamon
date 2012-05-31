package Cinnamon::Config;
use strict;
use warnings;

use Coro;
use Coro::RWLock;
use Cinnamon::Config::Loader;
use Cinnamon::Logger;

my %CONFIG;
my %ROLES;
my %TASKS;

my $lock = new Coro::RWLock;

sub set ($$) {
    my ($key, $value) = @_;

    $lock->wrlock;
    $CONFIG{$key} = $value;
    $lock->unlock;
}

sub get ($@) {
    my ($key, @args) = @_;

    $lock->rdlock;
    my $value = $CONFIG{$key};
    $lock->unlock;

    $value = $value->(@args) if ref $value eq 'CODE';
    $value;
}

sub set_role ($$$) {
    my ($role, $hosts, $params) = @_;

    $lock->wrlock;
    $ROLES{$role} = [$hosts, $params];
    $lock->unlock;
}

sub get_role (@) {
    my $role  = ($_[0] || get('role')) or do {
        log error => "Role is not specified";
        return [];
    };

    $lock->rdlock;
    my ($hosts, $params) = @{$ROLES{$role} or do {
        log error => "Role |$role| not defined";
        [];
    }};
    $lock->unlock;

    for my $key (keys %$params) {
        set $key => $params->{$key};
    }

    $hosts = $hosts->() if ref $hosts eq 'CODE';
    defined $hosts ? ref $hosts eq 'ARRAY' ? $hosts : [$hosts] : do {
        log error => "Role |$role| is empty";
        [];
    };
}

sub set_task ($$) {
    my ($task, $task_def) = @_;
    $lock->wrlock;
    $TASKS{$task} = $task_def;
    $lock->unlock;
}

sub get_task (@) {
    my ($task) = @_;

    $task ||= get('task') or do {
        log error => 'Task is not specified';
        return sub { };
    };
    my @task_path = split(':', $task);

    $lock->rdlock;
    my $value = \%TASKS;
    for (@task_path) {
        $value = $value->{$_};
    }
    $lock->unlock;

    $value || do {
        log error => "Task |$task| not defined";
        sub { };
    };
}

sub user () {
    get 'user' || do {
        my $user = qx{whoami};
        chomp $user;
        $user;
    };
}

sub load (@) {
    my ($role, $task, %opt) = @_;

    $role =~ s/^\@// if defined $role;

    set role => $role;
    set task => $task;

    Cinnamon::Config::Loader->load(config => $opt{config});
}

!!1;
