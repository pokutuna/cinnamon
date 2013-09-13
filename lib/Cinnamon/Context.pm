package Cinnamon::Context;
use strict;
use warnings;
use Cinnamon::Task;
push our @ISA, qw(Cinnamon::Task);
use Carp qw(croak);
use Cinnamon::Logger;
use Cinnamon::Role;
use Cinnamon::TaskResult;
use Cinnamon::CommandExecutor::Local;
use Cinnamon::CommandExecutor::Remote;

our $CTX;

sub new {
    my $class = shift;
    return bless {@_, roles => {}, tasks => {}, params => {}}, $class;
}

sub run {
    my ($self, $role_name, $task_path, %opts)  = @_;
    my $role = $self->get_role($role_name) || do {
        if ($task_path eq 'cinnamon:role:list') {
            Cinnamon::Role->new(name => '', hosts => []);
        } else {
            log 'error', "Role |\@$role_name| is not defined";
            return Cinnamon::TaskResult->new(failed => 1);
        }
    };

    my $args = $opts{args};

    my $show_tasklist = $task_path =~ /:$/;

    require Cinnamon::Task::Cinnamon if $task_path eq 'cinnamon:role:hosts';
    my $task = $self->get_task($task_path);
    unless (defined $task) {
        log 'error', "Task |$task_path| is not defined";
        return Cinnamon::TaskResult->new(failed => 1);
    }
    if ($show_tasklist or not $task->is_callable) {
        unshift @$args, $task_path;
        require Cinnamon::Task::Cinnamon;
        $task_path = 'cinnamon:task:list';
        $task = $self->get_task($task_path);
    }

    my $params = $role->params;
    for my $key (keys %$params) {
        $self->set_param($key => $params->{$key});
    }
    $self->set_param(role => $role_name);
    $self->set_param(task => $task_path);

    local $self->{params} = {%{$self->{params}}};
    my $result = $task->run(
        context => $self,
        role => $role,
        hosts => $opts{hosts},
        args => $args,
        onerror => sub {
            log error => $_[0];
        },
    );

    if ($result->failed) {
        log error => "Failed";
        log info => "[OK] @{[join ', ', @{$result->succeeded_hosts}]}"
            if @{$result->succeeded_hosts};
        log error => "[NG] @{[join ', ', @{$result->failed_hosts}]}"
            if @{$result->failed_hosts};
    } else {
        log success => "Done";
        log success => "[OK] @{[join ', ', @{$result->succeeded_hosts}]}"
            if @{$result->succeeded_hosts};
        log info => "[NG] @{[join ', ', @{$result->failed_hosts}]}"
            if @{$result->failed_hosts};
    }
    return $result;
}

sub load_config ($$) {
    my $config = $_[1];
    do {
        package Cinnamon::Context::_config_script;
        do $config;
    } || do {
        if ($@) {
            log error => $@;
            exit 1;
        }

        if ($!) {
            log error => $!;
            exit 1;
        }
    };
}

sub set_role {
    my ($self, $name, $hosts, $params, $args) = @_;
    $self->{roles}->{$name} = Cinnamon::Role->new(
        name => $name,
        hosts => $hosts,
        params => $params,
        args => $args,
    );
}

*add_role = \&set_role; # compat

sub set_role_alias {
    my ($self, $n1 => $n2) = @_;
    $self->{roles}->{$n1} = $self->{roles}->{$n2} || croak "Role |$n2| is not defined";
}

sub get_role {
    my ($self, $name) = @_;
    return $self->{roles}->{$name}; # or undef
}

sub roles {
    return $_[0]->{roles};
}

sub _task_def ($$);
sub _task_def ($$) {
    my ($name, $def) = @_;
    if (UNIVERSAL::isa($def, 'Cinnamon::TaskDef')) {
        return Cinnamon::Task->new(
            name => $name,
            code => $def->[0],
            args => $def->[1],
        );
    } elsif (ref $def eq 'HASH') {
        my $ts = Cinnamon::Task->new_task_set(
            name => $name,
        );
        for (keys %$def) {
            $ts->{tasks}->{$_} = _task_def $_, $def->{$_};
        }
        return $ts;
    } else {
        return Cinnamon::Task->new(
            name => $name,
            code => $def,
        );
    }
}

sub define_tasks {
    my ($self, $defs) = @_;
    for my $def (@$defs) {
        my $path = $def->{path};
        next unless @$path;

        my $obj = $self;
        for my $i (0..$#$path) {
            $obj->tasks->{$path->[$i]} ||= Cinnamon::Task->new(
                path => [@$path[0..$i]],
            );
            $obj = $obj->tasks->{$path->[$i]};
        }

        $obj->code($def->{code}) if $def->{code};
        $obj->args($def->{args}) if $def->{args} or $def->{code};
    }
}

sub get_task {
    my ($self, $path) = @_;
    if (not ref $path) {
        $path = [split /:/, $path, -1];
        pop @$path if @$path and $path->[-1] eq '';
    }

    my $value = $self;
    for (@$path) {
        return undef unless defined $value;
        my $tasks = $value->tasks or return undef;
        $value = $tasks->{$_};
    }

    return $value;
}

sub params {
    return $_[0]->{params};
}

sub set_param {
    my ($self, $key, $value) = @_;
    $self->params->{$key} = $value;
}

sub get_param {
    my ($self, $key, @args) = @_;

    my $value = $self->params->{$key};
    $value = $value->(@args) if ref $value eq 'CODE';

    return $value;
}

sub keychain {
    return $_[0]->{keychain};
}

sub get_command_executor {
    my ($self, %args) = @_;
    if ($args{remote}) {
        my $host = $args{host};
        my $user = $args{user};
        return $self->{remote}->{$host}->{defined $user ? 'user=' . $user : ''} ||= do {
            log info => 'ssh ' . (defined $user ? "$user\@$host" : $host);
            Cinnamon::CommandExecutor::Remote->new(
                host => $host,
                user => $user,
            );
        };
    } elsif ($args{local}) {
        return $self->{local} ||= do {
            return Cinnamon::CommandExecutor::Local->new;
        };
    } else {
        die "Neither |remote| or |local| is specified";
    }
}

sub dump_info {
    my ($self) = @_;

    my $roles = $self->roles;
    my $role_info = +{
        map { $_->name => $_->info } values %$roles,
    };

    my $tasks = $self->tasks;
    my $task_info = +{
        map { %{$_->info} } values %$tasks,
    };

    require YAML;
    log 'info', YAML::Dump({
        roles => $role_info,
        tasks => $task_info,
    });
}

!!1;
